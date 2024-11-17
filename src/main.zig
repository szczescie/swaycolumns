//! Manual tiling without boilerplate key presses.

const std = @import("std");
const os = std.os;
const eql = std.mem.eql;
const exit = std.posix.exit;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const log = std.log;
const span = std.mem.span;
const builtin = @import("builtin");
const mode = builtin.mode;

const columns = @import("columns.zig");

pub const version = "0.2";
var fba_buf: [1024 * 1024]u8 = undefined;
pub var fba_state = FixedBufferAllocator.init(&fba_buf);
pub const fba = fba_state.allocator();

/// Run the program.
pub fn main() !void {
    try columns.connect();
    defer columns.close();
    const argv = os.argv;
    log.info("swaycolumns version {s} started; good morning 🌞", .{version});
    log.debug("number of cli arguments: {d}", .{argv.len - 1});
    log.debug("cli arguments: {s}", .{argv[1..]});
    if (argv.len == 3) {
        const subcommands = .{
            .{ "move", columns.containerMove },
            .{ "focus", columns.containerFocus },
            .{ "layout", columns.containerLayout },
        };
        inline for (subcommands) |subcommand| {
            const argument, const func = subcommand;
            if (eql(u8, span(argv[1]), argument)) {
                const Parameter = @typeInfo(@TypeOf(func)).Fn.params[0].type.?;
                const fields = @typeInfo(Parameter).Enum.fields;
                inline for (fields) |field| {
                    if (eql(u8, span(argv[2]), field.name)) {
                        return @call(
                            .auto,
                            func,
                            .{@field(Parameter, field.name)},
                        ) catch |err| {
                            log.err(
                                "{}: unable to start swaycolumns; exiting",
                                .{err},
                            );
                            if (mode == .Debug) {
                                return err;
                            } else {
                                exit(1);
                            }
                        };
                    }
                }
            }
        }
    } else if (argv.len == 2) {
        if (eql(u8, span(argv[1]), "start")) {
            try columns.layoutStart();
            log.info("sway closed; exiting", .{});
            exit(0);
        }
    }
    log.info("no actionable arguments; exiting", .{});
    exit(1);
}
