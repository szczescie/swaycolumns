//! Manual tiling without boilerplate key presses.

const std = @import("std");

const columns = @import("columns.zig");

var fba_buf: [1024 * 1024]u8 = undefined;
pub var fba_state = std.heap.FixedBufferAllocator.init(&fba_buf);
pub const fba = fba_state.allocator();

const Subcommand = enum { start, focus, move, layout, drop, @"-h", @"--help" };

fn stringToSubcommand(string: []const u8) Subcommand {
    return std.meta.stringToEnum(Subcommand, string) orelse
        std.process.fatal("{s} is an invalid subcommand", .{string});
}

fn stringToParameter(comptime T: type, string: []const u8) T {
    return std.meta.stringToEnum(T, string) orelse
        std.process.fatal("{s} is an invalid parameter", .{string});
}

fn help() !void {
    var stdout_writer = std.fs.File.stdout().writer(&.{});
    try stdout_writer.interface.writeAll(
        \\Usage: swaycolumns [command] [parameter]
        \\
        \\  start [modifier]    Start the daemon and use the specified floating modifier.
        \\  move <direction>    Move windows or swap columns.
        \\  focus <target>      Focus window, column or workspace.
        \\  layout <mode>       Switch column layout to splitv or stacking.
        \\
        \\  -h, --help          Print this message and quit.
        \\
    );
}

/// Run the program.
pub fn main() !void {
    try columns.init();
    defer columns.deinit();
    var args = std.process.args();
    _ = args.skip();
    const subcommand_arg = args.next() orelse
        std.process.fatal("missing subcommand", .{});
    switch (stringToSubcommand(subcommand_arg)) {
        .start => try columns.start(args.next() orelse "super"),
        .move, .focus, .layout => |subcommand| {
            const parameter_arg = args.next() orelse std.process.fatal(
                \\ {s} is missing a parameter
            , .{subcommand_arg});
            switch (subcommand) {
                .focus => try columns.focus(
                    stringToParameter(columns.FocusTarget, parameter_arg),
                ),
                .move => try columns.move(
                    stringToParameter(columns.MoveDirection, parameter_arg),
                ),
                .layout => try columns.layout(
                    stringToParameter(columns.LayoutMode, parameter_arg),
                ),
                else => unreachable,
            }
        },
        .drop => try columns.drop(),
        .@"-h", .@"--help" => try help(),
    }
}
