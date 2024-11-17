//! Manual tiling without boilerplate key presses.

const std = @import("std");
const os = std.os;
const eql = std.mem.eql;
const exit = std.posix.exit;
const fatal = std.zig.fatal;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const log = std.log;
const span = std.mem.span;

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
                inline for (@typeInfo(Parameter).Enum.fields) |field| {
                    if (eql(u8, span(argv[2]), field.name)) {
                        return @call(.auto, func, .{@field(Parameter, field.name)}) catch |err| {
                            fatal("{}: unable to start swaycolumns; exiting", .{err});
                        };
                    }
                }
            }
        }
    } else if (argv.len == 2) {
        if (eql(u8, span(argv[1]), "start")) {
            columns.layoutStart() catch |err| {
                fatal("{}: unable to start swaycolumns; exiting", .{err});
            };
            fatal("sway closed; exiting", .{});
        }
    }
    fatal("no actionable arguments; exiting", .{});
}
