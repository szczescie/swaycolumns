const std = @import("std");
const builtin = @import("builtin");

const columns = @import("columns.zig");

pub var subscribe: Socket = undefined;
pub var tree: Socket = undefined;
pub var run: Socket = undefined;
pub var fba: std.heap.FixedBufferAllocator = undefined;

const MessageType = enum(u32) { run = 0, subscribe = 2, tree = 4 };

const Socket = struct {
    writer: std.net.Stream.Writer,
    reader: std.net.Stream.Reader,
    message_type: MessageType,

    fn init(message_type: MessageType, buffer_write: []u8, buffer_read: []u8) @This() {
        const socket_path = std.posix.getenv("SWAYSOCK") orelse
            std.process.fatal("SWAYSOCK is not set", .{});
        const stream = std.net.connectUnixSocket(socket_path) catch |err|
            std.process.fatal("unable to connect to socket: {}", .{err});
        var socket: @This() = .{
            .writer = stream.writer(buffer_write),
            .reader = stream.reader(buffer_read),
            .message_type = message_type,
        };
        socket.writeHeader() catch |err|
            std.process.fatal("unable to write to socket ({})", .{err});
        return socket;
    }

    fn deinit(self: @This()) void {
        std.net.Stream.Reader.getStream(&self.reader).close();
    }

    fn reconnect(self: *@This()) void {
        self.deinit();
        self.* = init(
            self.message_type,
            self.writer.interface.buffer,
            self.reader.interface().buffer,
        );
    }

    const header_length = 14;

    fn writeHeader(self: *@This()) !void {
        const i3_ipc: [6]u8 = .{ 'i', '3', '-', 'i', 'p', 'c' };
        const length: [4]u8 = .{ 0, 0, 0, 0 };
        const @"type": [4]u8 = @bitCast(@intFromEnum(self.message_type));
        try self.add(&(i3_ipc ++ length ++ @"type"));
    }

    pub fn addPrint(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
        try self.writer.interface.print(fmt, args);
    }

    pub fn add(self: *@This(), payload: []const u8) !void {
        try self.writer.interface.writeAll(payload);
    }

    pub fn lengthWrite(self: @This()) u32 {
        return @intCast(self.writer.interface.end - header_length);
    }

    pub fn commit(self: *@This()) !void {
        std.debug.assert(std.mem.eql(u8, self.writer.interface.buffer[0..6], "i3-ipc"));
        const length: u32 = self.lengthWrite();
        if (self.message_type != .tree) std.debug.assert(length > 0);
        @memcpy(self.writer.interface.buffer[6..10], &@as([4]u8, @bitCast(length)));
        // if (self.writer.interface.end > header_length)
        //     std.debug.print("{s}\n", .{self.writer.interface.buffered()});
        try self.writer.interface.flush();
        try self.writeHeader();
    }

    fn lengthRead(self: *@This()) !u32 {
        var header: [14]u8 = undefined;
        try self.reader.interface().readSliceAll(&header);
        return std.mem.readInt(u32, header[6..10], builtin.target.cpu.arch.endian());
    }

    pub fn discard(self: *@This()) !void {
        _ = try self.reader.interface().discard(.limited(try self.lengthRead()));
    }

    pub fn parse(self: *@This(), T: type) !T {
        const length = try self.lengthRead();
        if (length > self.reader.interface().buffer.len) return error.Overflow;
        defer self.reader.interface().toss(length);
        const slice = try self.reader.interface().peek(length);
        const options: std.json.ParseOptions =
            .{ .ignore_unknown_fields = true, .allocate = .alloc_if_needed };
        return std.json.parseFromSliceLeaky(T, fba.allocator(), slice, options);
    }
};

const help_text =
    \\Usage: swaycolumns [option] <command>
    \\
    \\Commands:
    \\
    \\  start                             Start the background process
    \\  start <modifier>                  Start the background process and set a floating modifier
    \\  move <direction>                  Move windows or swap columns
    \\  move workspace <name>             Move a window or column to a named workspace
    \\  move workspace number <number>    Move a window or column to an indexed workspace
    \\  focus <target>                    Focus a window, column or workspace
    \\  layout <mode>                     Switch the column layout to splitv or stacking
    \\  floating <state>                  Switch the window or stacked column's floating state.
    \\
    \\Options:
    \\
    \\  -m, --memory                      Change the amount of bytes allocated at startup (default: 1Mib)
    \\  -h, --help                        Print this message and exit
;

fn exitHelp(status: u8) noreturn {
    @branchHint(.unlikely);
    var stdout = std.fs.File.stdout().writer(&.{});
    stdout.interface.writeAll(help_text) catch std.process.exit(1);
    std.process.exit(status);
}

fn take(amount: usize, buffer: []u8) struct { []u8, []u8 } {
    return .{ buffer[0..amount], buffer[amount..] };
}

const Command = union(enum) {
    start: ?columns.Modifier,
    move: union(enum) {
        direction: columns.MoveDirection,
        workspace_name: []const u8,
        workspace_number: u32,
    },
    focus: columns.FocusTarget,
    layout: columns.LayoutMode,
    floating: columns.FloatingState,
    drop,
};
const Option = enum { @"-m", @"--memory", @"-h", @"--help" };

pub fn main() !void {
    var iterator = std.process.args();
    _ = iterator.skip();
    const command_tag, const memory = b: {
        var memory: usize = 1024 * 1024;
        while (iterator.next()) |argument| {
            const option = std.meta.stringToEnum(Option, argument) orelse {
                const command_tag = std.meta.stringToEnum(std.meta.Tag(Command), argument) orelse
                    std.process.fatal("invalid command: {s}", .{argument});
                break :b .{ command_tag, memory };
            };
            switch (option) {
                .@"-h", .@"--help" => exitHelp(0),
                .@"-m", .@"--memory" => {
                    const number = iterator.next() orelse
                        std.process.fatal("expected argument to: {t}", .{option});
                    memory = std.fmt.parseUnsigned(usize, number, 10) catch
                        std.process.fatal("invalid number of bytes: {s}", .{number});
                },
            }
        } else std.process.fatal("expected command", .{});
    };
    const length_subscribe_write = columns.subscribed_events.len + Socket.header_length;
    const length_tree_write = Socket.header_length;
    const length = memory - length_subscribe_write - length_tree_write;
    const buffer = try std.heap.page_allocator.alloc(u8, memory);
    var rest = buffer;
    const buffer_subscribe_write, rest = take(length_subscribe_write, rest);
    const buffer_subscribe_read, rest = take(length * 44 / 100, rest);
    const buffer_tree_write, rest = take(length_tree_write, rest);
    const buffer_tree_read, rest = take(length * 44 / 100, rest);
    const buffer_run_write, rest = take(length * 1 / 100, rest);
    const buffer_run_read, rest = take(length * 1 / 100, rest);
    fba = .init(rest);
    const command: Command = switch (command_tag) {
        .start => .{
            .start = if (iterator.next()) |mod| b: {
                const mod_lower = std.ascii.allocLowerString(fba.allocator(), mod) catch
                    std.process.fatal("out of memory", .{});
                break :b std.meta.stringToEnum(columns.Modifier, mod_lower) orelse
                    std.process.fatal("invalid modifier: {s}", .{mod});
            } else null,
        },
        .move => .{ .move = b: {
            const parameter = iterator.next() orelse
                std.process.fatal("expected argument to: {t}", .{command_tag});
            if (std.mem.eql(u8, parameter, "workspace")) {
                const name_or_specifier = iterator.next() orelse
                    std.process.fatal("expected argument to: {s}", .{parameter});
                if (std.mem.eql(u8, name_or_specifier, "number")) {
                    const number = iterator.next() orelse
                        std.process.fatal("expected argument to: {s}", .{name_or_specifier});
                    break :b .{
                        .workspace_number = std.fmt.parseUnsigned(u32, number, 10) catch
                            std.process.fatal("invalid number: {s}", .{number}),
                    };
                } else break :b .{ .workspace_name = name_or_specifier };
            }
            break :b .{
                .direction = std.meta.stringToEnum(columns.MoveDirection, parameter) orelse
                    std.process.fatal("invalid direction: {s}", .{parameter}),
            };
        } },
        .focus => .{ .focus = b: {
            const parameter = iterator.next() orelse
                std.process.fatal("expected argument to: {t}", .{command_tag});
            break :b std.meta.stringToEnum(columns.FocusTarget, parameter) orelse
                std.process.fatal("invalid target: {s}", .{parameter});
        } },
        .layout => .{ .layout = b: {
            const parameter = iterator.next() orelse
                std.process.fatal("expected argument to: {t}", .{command_tag});
            break :b std.meta.stringToEnum(columns.LayoutMode, parameter) orelse
                std.process.fatal("invalid mode: {s}", .{parameter});
        } },
        .floating => .{ .floating = b: {
            const parameter = iterator.next() orelse
                std.process.fatal("expected argument to: {t}", .{command_tag});
            break :b std.meta.stringToEnum(columns.FloatingState, parameter) orelse
                std.process.fatal("invalid state: {s}", .{parameter});
        } },
        .drop => .drop,
    };
    if (iterator.next()) |argument|
        std.process.fatal("unexpected argument: {s}", .{argument});
    tree = .init(.tree, buffer_tree_write, buffer_tree_read);
    run = .init(.run, buffer_run_write, buffer_run_read);
    defer inline for (.{ tree, run }) |sock| sock.deinit();
    switch (command) {
        .start => |mod_or_null| {
            subscribe = .init(.subscribe, buffer_subscribe_write, buffer_subscribe_read);
            while (true) columns.start(mod_or_null) catch |err| {
                std.log.debug("{}", .{err});
                inline for (.{ &tree, &run, &subscribe }) |sock| sock.reconnect();
                std.Thread.sleep(3 * std.time.ns_per_s);
            };
        },
        .move => |specifier| switch (specifier) {
            .direction => |direction| try columns.move(direction),
            .workspace_name => |name| try columns.moveWorkspace(.{ .name = name }),
            .workspace_number => |number| try columns.moveWorkspace(.{ .number = number }),
        },
        .focus => |target| try columns.focus(target),
        .layout => |mode| try columns.layout(mode),
        .floating => |state| try columns.floating(state),
        .drop => try columns.drop(),
    }
}
