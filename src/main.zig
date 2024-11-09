//! Manual tiling without boilerplate key presses.

const std = @import("std");
const mem = std.mem;
const os = std.os;
const posix = std.posix;

const Socket = @import("Socket.zig");
const Columns = @import("Columns.zig");

/// Run the program.
pub fn main() (Socket.ErrorSwaysock || Socket.ErrorWriteRead)!void {
    var buf: [512 * 1024]u8 = undefined;
    const columns = try Columns.init(&buf);
    defer columns.deinit();

    if (os.argv.len == 3) {
        const subcommands = .{
            .{ "move", Columns.containerMove },
            .{ "focus", Columns.containerFocus },
            .{ "layout", Columns.containerFocus },
        };
        inline for (subcommands) |subcommand| {
            const argument, const method = subcommand;
            if (mem.eql(u8, mem.span(os.argv[1]), argument)) {
                const Parameter = @typeInfo(@TypeOf(method)).Fn.params[1].type.?;
                const fields = @typeInfo(Parameter).Enum.fields;
                inline for (fields) |field| {
                    if (mem.eql(u8, mem.span(os.argv[2]), field.name)) {
                        return @call(
                            .auto,
                            method,
                            .{
                                columns,
                                @field(Parameter, field.name),
                            },
                        );
                    }
                }
            }
        }
    } else if (os.argv.len == 2) {
        if (mem.eql(u8, mem.span(os.argv[1]), "start")) {
            try columns.layoutStart();
        }
    } else {
        posix.exit(1);
    }
}

// TODO: logs
// TODO: buffered reader
// TODO: oom restart
// TODO: damage tracking
