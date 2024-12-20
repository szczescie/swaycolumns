//! Main tiling logic.

const std = @import("std");
const Allocator = std.mem.Allocator;
const allocPrint = std.fmt.allocPrint;
const ArrayList = std.ArrayList;
const eql = std.mem.eql;
const log = std.log;
const ns_per_s = std.time.ns_per_s;
const sleep = std.time.sleep;

const main = @import("main.zig");
const fba = &main.fba;
const fba_state = &main.fba_state;
const Swaysock = @import("Swaysock.zig");
const tree = @import("tree.zig");
const getParsed = tree.getParsed;

/// Socket used for subscribing.
pub var observe_sock: Swaysock = undefined;
/// Socket used for commands and getting the tree.
pub var interact_sock: Swaysock = undefined;

/// Connect to both sockets.
pub fn connect() !void {
    observe_sock = try Swaysock.connect();
    errdefer observe_sock.close();
    interact_sock = try Swaysock.connect();
    errdefer observe_sock.close();
}

/// Disconnect from both sockets.
pub fn close() void {
    observe_sock.close();
    interact_sock.close();
}

/// Argument passed to the move command.
pub const MoveDirection = enum { left, right, up, down };

/// Move window or swap containers.
pub fn containerMove(comptime direction: MoveDirection) !void {
    const containers = (try getParsed(.focused)).nodes;
    for (containers, 0..) |container, index_container| {
        if (container.focused) {
            const swap_id = if (direction == .left and index_container > 0)
                containers[index_container - 1].id
            else if (direction == .right and index_container < containers.len - 1)
                containers[index_container + 1].id
            else
                return;
            const format = "swap container with con_id {d}";
            const payload = allocPrint(fba.*, format, .{swap_id}) catch |err| {
                log.warn("{}: failed to format con_id {}", .{ err, swap_id });
                return err;
            };
            _ = try interact_sock.writeRead(.command, payload);
            return;
        }
        const windows = container.nodes;
        for (windows, 0..) |window, index_window| {
            const focused_middle = window.focused and
                (direction != .up or index_window != 0) and
                (direction != .down or index_window != windows.len - 1);
            if (!focused_middle) continue;
            const payload = "move " ++ @tagName(direction);
            _ = try interact_sock.writeRead(.command, payload);
            return;
        }
    }
}

/// Argument to the focus command.
pub const FocusTarget = enum { column, window, toggle };

/// Focus column or window.
pub fn containerFocus(comptime target: FocusTarget) !void {
    if (target != .column) {
        for ((try getParsed(.focused)).nodes) |container| {
            if (!container.focused) continue;
            _ = try interact_sock.writeRead(.command, "focus child");
            return;
        }
    }
    if (target == .window) return;
    _ = try interact_sock.writeRead(.command, "focus parent");
}

/// Argument to the layout command.
pub const LayoutMode = enum { splitv, stacking, toggle };

/// Switch the column's layout.
pub fn containerLayout(comptime mode: LayoutMode) !void {
    const toggle = "layout toggle splitv stacking";
    const layout = if (mode == .toggle) toggle else "layout " ++ @tagName(mode);
    for ((try getParsed(.focused)).nodes) |container| {
        if (!container.focused) continue;
        _ = try interact_sock.writeRead(.command, "focus child; " ++ layout ++ "; focus parent");
        return;
    }
    _ = try interact_sock.writeRead(.command, layout);
}

/// Option to eject nested containers.
pub const ArrangeOptions = struct { fix_nested: bool = true };

/// Split windows or flatten containers.
pub fn layoutArrange(comptime options: ArrangeOptions) !void {
    var command = ArrayList(u8).init(fba.*);
    for (try getParsed(.all)) |workspace| {
        const columns = workspace.nodes;
        if (columns.len == 1 and columns[0].nodes.len == 1) {
            const windows = columns[0].nodes;
            const format = "[con_id={d}] split n; ";
            const subcommand = allocPrint(fba.*, format, .{windows[0].id}) catch |err| {
                log.warn("{}: failed to format con_id {}", .{ err, windows[0].id });
                return err;
            };
            command.appendSlice(subcommand) catch |err| {
                log.warn("{}: failed to append slice {s}", .{ err, subcommand });
                return err;
            };
            continue;
        }
        if (columns.len >= 1 and eql(u8, workspace.layout, "splitv")) {
            {
                const format = "[con_id={d}] move right, move left; ";
                const subcommand = allocPrint(fba.*, format, .{columns[0].id}) catch |err| {
                    log.warn("{}: failed to format con_id {}", .{ err, columns[0].id });
                    return err;
                };
                command.appendSlice(subcommand) catch |err| {
                    log.warn("{}: failed to append slice {s}", .{ err, subcommand });
                    return err;
                };
            }
            for (0..columns[0].nodes.len) |_| {
                const format = "[con_id={d}] move up; ";
                const subcommand = allocPrint(fba.*, format, .{columns[0].id}) catch |err| {
                    log.warn("{}: failed to format con_id {}", .{ err, columns[0].id });
                    return err;
                };
                command.appendSlice(subcommand) catch |err| {
                    log.warn("{}: failed to append slice {s}", .{ err, subcommand });
                    return err;
                };
            }
            continue;
        }
        for (columns) |column| {
            if (columns.len >= 2 and eql(u8, column.layout, "none")) {
                const format = "[con_id={d}] split v; ";
                const subcommand = allocPrint(fba.*, format, .{column.id}) catch |err| {
                    log.warn("{}: failed to format con_id {}", .{ err, column.id });
                    return err;
                };
                command.appendSlice(subcommand) catch |err| {
                    log.warn("{}: failed to append slice {s}", .{ err, subcommand });
                    return err;
                };
            }
            if (!options.fix_nested) continue;
            for (column.nodes) |window| {
                if (eql(u8, window.layout, "none")) continue;
                const format = "[con_id={0d}] mark swaycolumns_last; " ++
                    "[con_id={1d}] move mark swaycolumns_last, move right; " ++
                    "[con_id={0d}] unmark swaycolumns_last; ";
                const args = .{ workspace.nodes[workspace.nodes.len - 1].id, window.id };
                const subcommand = allocPrint(fba.*, format, args) catch |err| {
                    log.warn("{}: failed to format con_id {}, {}", .{err} ++ args);
                    return err;
                };
                command.appendSlice(subcommand) catch |err| {
                    log.warn("{}: failed to append slice {s}", .{ err, subcommand });
                    return err;
                };
            }
        }
    }
    if (command.items.len > 0) {
        log.debug("running command: {s}", .{command.items});
        _ = try interact_sock.writeRead(.command, command.items);
    }
}

/// Change the layout tree and reset memory.
fn layoutApply() !bool {
    defer {
        log.debug("resetting fixed buffer allocator", .{});
        fba_state.reset();
    }
    const event = try observe_sock.readParse(struct { change: []const u8 });
    if (eql(u8, event.change, "exit")) return true;
    const tree_changed = eql(u8, event.change, "focus") or
        eql(u8, event.change, "new") or eql(u8, event.change, "close") or
        eql(u8, event.change, "floating") or eql(u8, event.change, "move");
    if (tree_changed) try layoutArrange(.{});
    return false;
}

/// Subscribe to window events and run the main loop.
pub fn layoutStart() !void {
    _ = try observe_sock.writeRead(.subscribe, "[\"window\", \"shutdown\"]");
    try layoutArrange(.{});
    while (true) {
        const exited = layoutApply() catch |err| {
            if (err != error.OutOfMemory and err != error.SyntaxError and
                err != error.UnexpectedEndOfInput and err != error.NotFound) return err;
            const retry_time_sec = 5;
            const format = "{}: failed to apply layout; trying again in {d} seconds";
            log.err(format, .{ err, retry_time_sec });
            sleep(retry_time_sec * ns_per_s);
            continue;
        };
        if (!exited) continue;
        log.info("exiting swaycolumns; goodbye", .{});
        return;
    }
}
