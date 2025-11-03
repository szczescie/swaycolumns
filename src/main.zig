const std = @import("std");
const builtin = @import("builtin");

const columns = @import("columns.zig");

pub const subscribe = socket(.subscribe, 50, 500_000);
pub const tree = socket(.tree, 50, 500_000);
pub const run = socket(.run, 1_000, 1_000);

var buffer_fba: [50_000]u8 = undefined;
pub var fba = std.heap.FixedBufferAllocator.init(&buffer_fba);

const MessageType = enum(u32) { run = 0, subscribe = 2, tree = 4 };

fn socket(message_type: MessageType, len_write: usize, len_read: usize) type {
    return struct {
        var buffer_write: [len_write]u8 = undefined;
        var buffer_read: [len_read]u8 = undefined;
        var writer: std.net.Stream.Writer = undefined;
        var reader: std.net.Stream.Reader = undefined;

        pub fn init() void {
            const socket_path = std.posix.getenv("SWAYSOCK") orelse
                std.process.fatal("SWAYSOCK is not set", .{});
            const stream = std.net.connectUnixSocket(socket_path) catch |err|
                std.process.fatal("unable to connect to socket ({})", .{err});
            writer = stream.writer(&buffer_write);
            reader = stream.reader(&buffer_read);
            writeHeader() catch |err|
                std.process.fatal("unable to write to socket ({})", .{err});
        }

        pub fn deinit() void {
            std.net.Stream.Reader.getStream(&reader).close();
        }

        pub fn reconnect() void {
            deinit();
            init();
        }

        fn writeHeader() !void {
            const i3_ipc: [6]u8 = .{ 'i', '3', '-', 'i', 'p', 'c' };
            const length: [4]u8 = .{ 0, 0, 0, 0 };
            const @"type": [4]u8 = @bitCast(@intFromEnum(message_type));
            try add(&(i3_ipc ++ length ++ @"type"));
        }

        pub fn addPrint(comptime fmt: []const u8, args: anytype) !void {
            try writer.interface.print(fmt, args);
        }

        pub fn add(payload: []const u8) !void {
            try writer.interface.writeAll(payload);
        }

        pub fn lengthWrite() u32 {
            return @intCast(writer.interface.end - 14);
        }

        pub fn commit() !void {
            std.debug.assert(std.mem.eql(u8, writer.interface.buffer[0..6], "i3-ipc"));
            const length: u32 = lengthWrite();
            if (message_type != .tree) std.debug.assert(length > 0);
            @memcpy(buffer_write[6..10], &@as([4]u8, @bitCast(length)));
            try writer.interface.flush();
            try writeHeader();
        }

        fn lengthRead() !u32 {
            var header: [14]u8 = undefined;
            try reader.interface().readSliceAll(&header);
            return std.mem.readInt(u32, header[6..10], builtin.target.cpu.arch.endian());
        }

        pub fn discard() !void {
            _ = try reader.interface().discard(.limited(try lengthRead()));
        }

        pub fn parse(T: type) !T {
            const length = try lengthRead();
            if (length > buffer_read.len) return error.Overflow;
            defer reader.interface().toss(length);
            const slice = try reader.interface().peek(length);
            const options: std.json.ParseOptions =
                .{ .ignore_unknown_fields = true, .allocate = .alloc_if_needed };
            return std.json.parseFromSliceLeaky(T, fba.allocator(), slice, options);
        }
    };
}

fn helpExit(status: u8) noreturn {
    @branchHint(.unlikely);
    var stdout = std.fs.File.stdout().writer(&.{});
    stdout.interface.writeAll(
        \\Usage: swaycolumns [command] [parameter]
        \\
        \\  start [modifier]    Start the daemon and set a floating modifier.
        \\  move <direction>    Move windows or swap columns.
        \\  focus <target>      Focus window, column or workspace.
        \\  layout <mode>       Switch column layout to splitv or stacking.
        \\
        \\  -h, --help          Print this message and quit.
        \\
    ) catch std.process.exit(1);
    std.process.exit(status);
}

const Subcommand = enum { start, focus, move, layout, drop, @"-h", @"--help" };

fn parameter(T: type, subcommand: Subcommand, arg_2_or_null: ?[]const u8) T {
    const arg_2 = arg_2_or_null orelse
        std.process.fatal("{t} is missing a parameter", .{subcommand});
    return std.meta.stringToEnum(T, arg_2) orelse
        std.process.fatal("{s} is an invalid parameter", .{arg_2});
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();
    const arg_1 = args.next() orelse helpExit(1);
    const subcommand = std.meta.stringToEnum(Subcommand, arg_1) orelse
        std.process.fatal("{s} is an invalid subcommand", .{arg_1});
    inline for (.{ tree, run }) |sock| sock.init();
    defer inline for (.{ tree, run }) |sock| sock.deinit();
    switch (subcommand) {
        .start => {
            const mod_or_null: ?columns.Modifier = if (args.next()) |mod| block: {
                const mod_lower = std.ascii.allocLowerString(fba.allocator(), mod) catch
                    std.process.exit(1);
                break :block parameter(columns.Modifier, .start, mod_lower);
            } else null;
            subscribe.init();
            while (true) columns.start(mod_or_null) catch |err| {
                std.log.debug("{}", .{err});
                inline for (.{ tree, run, subscribe }) |sock| sock.reconnect();
                std.Thread.sleep(3 * std.time.ns_per_s);
            };
        },
        .move => try columns.move(parameter(columns.Direction, .move, args.next())),
        .focus => try columns.focus(parameter(columns.Target, .focus, args.next())),
        .layout => try columns.layout(parameter(columns.Mode, .layout, args.next())),
        .@"-h", .@"--help" => helpExit(0),
        .drop => try columns.drop(),
    }
}
