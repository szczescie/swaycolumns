//! Manual tiling without boilerplate key presses.

const std = @import("std");
const log = std.log;
const mem = std.mem;
const os = std.os;
const posix = std.posix;

const Socket = @import("Socket.zig");
const Columns = @import("Columns.zig");

const version = "0.1";

/// Run the program.
pub fn main() (Socket.ErrorSwaysock || Socket.ErrorWriteRead)!void {
    var buf: [512 * 1024]u8 = undefined;
    const columns = try Columns.init(&buf);
    defer columns.deinit();
    log.info("swaycolumns version {s} started; good morning 🌞", .{version});
    log.debug("number of cli arguments: {d}", .{os.argv.len - 1});
    log.debug("cli arguments: {s}", .{os.argv[1..]});
    if (os.argv.len == 3) {
        const subcommands = .{
            .{ "move", Columns.containerMove },
            .{ "focus", Columns.containerFocus },
            .{ "layout", Columns.containerFocus },
        };
        inline for (subcommands) |subcommand| {
            const argument, const method = subcommand;
            if (!mem.eql(u8, mem.span(os.argv[1]), argument)) {
                continue;
            }
            const Parameter = @typeInfo(@TypeOf(method)).Fn.params[1].type.?;
            const fields = @typeInfo(Parameter).Enum.fields;
            inline for (fields) |field| {
                if (!mem.eql(u8, mem.span(os.argv[2]), field.name)) {
                    continue;
                }
                return @call(
                    .auto,
                    method,
                    .{ columns, @field(Parameter, field.name) },
                );
            }
        }
    } else if (os.argv.len == 2) {
        if (mem.eql(u8, mem.span(os.argv[1]), "start")) {
            try columns.layoutStart();
        }
    }
    log.info("no actionable arguments; exiting", .{});
    posix.exit(1);
}

// TODO: logs
// TODO: buffered reader
// TODO: oom restart
// TODO: damage tracking
