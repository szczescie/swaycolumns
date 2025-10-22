//! Manual tiling without boilerplate key presses.

const std = @import("std");

const columns = @import("columns.zig");
const command = @import("command.zig");
const socket = @import("socket.zig");

fn help(status: u8) noreturn {
    var stdout_writer = std.fs.File.stdout().writer(&.{});
    stdout_writer.interface.writeAll(
        \\Usage: swaycolumns [command] [parameter]
        \\
        \\  start [modifier]    Start the daemon and use the specified floating modifier.
        \\  move <direction>    Move windows or swap columns.
        \\  focus <target>      Focus window, column or workspace.
        \\  layout <mode>       Switch column layout to splitv or stacking.
        \\
        \\  -h, --help          Print this message and quit.
        \\
    ) catch {};
    std.process.exit(status);
}

const Subcommand = enum { start, focus, move, layout, drop, @"-h", @"--help" };

fn stringToSubcommand(subcommand: ?[]const u8) Subcommand {
    const subcommand_string = subcommand orelse help(1);
    return std.meta.stringToEnum(Subcommand, subcommand_string) orelse
        std.process.fatal("{s} is an invalid subcommand", .{subcommand_string});
}

fn stringToParameter(
    comptime T: type,
    subcommand: Subcommand,
    parameter: ?[]const u8,
) T {
    const parameter_string = parameter orelse
        std.process.fatal("{t} is missing a parameter", .{subcommand});
    return std.meta.stringToEnum(T, parameter_string) orelse
        std.process.fatal("{s} is an invalid parameter", .{parameter_string});
}

pub fn main() !void {
    socket.init() catch |err| switch (err) {
        error.SwaysockEnv => {
            std.process.fatal("SWAYSOCK is not set", .{});
        },
        error.SwaysockConnection => {
            std.process.fatal("unable to connect to socket ({})", .{err});
        },
        else => return err,
    };
    defer socket.deinit();
    var args = std.process.args();
    _ = args.skip();
    const subcommand = stringToSubcommand(args.next());
    switch (subcommand) {
        .start => try columns.start(args.next() orelse "super"),
        .focus => try columns.focus(
            stringToParameter(command.FocusTarget, subcommand, args.next()),
        ),
        .move => try columns.move(
            stringToParameter(command.MoveDirection, subcommand, args.next()),
        ),
        .layout => try columns.layout(
            stringToParameter(command.LayoutMode, subcommand, args.next()),
        ),
        .drop => try columns.drop(),
        .@"-h", .@"--help" => help(0),
    }
}
