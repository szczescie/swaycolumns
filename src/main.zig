//! Manual tiling without boilerplate key presses.

const std = @import("std");

const columns = @import("columns.zig");
const socket = @import("socket.zig");

var fba_buf: [64 * 1024]u8 = undefined;
pub var fba_state = std.heap.FixedBufferAllocator.init(&fba_buf);
pub const fba = fba_state.allocator();

fn help(status: u8) noreturn {
    @branchHint(.unlikely);
    var stdout_writer = std.fs.File.stdout().writer(&.{});
    const stdout = &stdout_writer.interface;
    stdout.writeAll(
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

fn stringToSubcommand(arg_1: ?[]const u8) Subcommand {
    const subcommand = arg_1 orelse help(1);
    return std.meta.stringToEnum(Subcommand, subcommand) orelse
        std.process.fatal("{s} is an invalid subcommand", .{subcommand});
}

fn stringToParameter(T: type, subcommand: Subcommand, arg_2: ?[]const u8) T {
    const parameter = arg_2 orelse
        std.process.fatal("{t} is missing a parameter", .{subcommand});
    return std.meta.stringToEnum(T, parameter) orelse
        std.process.fatal("{s} is an invalid parameter", .{parameter});
}

fn socketFailed(err: anyerror) noreturn {
    switch (err) {
        error.SwaysockEnv => std.process.fatal("SWAYSOCK is not set", .{}),
        error.SwaysockConnection => std.process.fatal("unable to connect to socket ({})", .{err}),
        else => std.process.fatal("unable to write to socket ({})", .{err}),
    }
}

pub fn main() !void {
    socket.init() catch |err| socketFailed(err);
    defer socket.deinit();
    var args = std.process.args();
    _ = args.skip();
    switch (stringToSubcommand(args.next() orelse help(1))) {
        .start => {
            const mod_or_null: ?columns.Modifier = if (args.next()) |mod| block: {
                const mod_lower = std.ascii.allocLowerString(fba, mod) catch std.process.exit(1);
                break :block stringToParameter(columns.Modifier, .start, mod_lower);
            } else null;
            while (true) columns.start(mod_or_null) catch |columns_err| {
                std.log.debug("{}", .{columns_err});
                socket.deinit();
                std.Thread.sleep(1 * std.time.ns_per_s);
                socket.init() catch |socket_err| socketFailed(socket_err);
                std.Thread.sleep(1 * std.time.ns_per_s);
            };
        },
        .move => try columns.move(stringToParameter(columns.Direction, .move, args.next())),
        .focus => try columns.focus(stringToParameter(columns.Target, .focus, args.next())),
        .layout => try columns.layout(stringToParameter(columns.Mode, .layout, args.next())),
        .drop => try columns.drop(),
        .@"-h", .@"--help" => help(0),
    }
}
