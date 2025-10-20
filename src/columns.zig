//! Main tiling logic.

const std = @import("std");

const main = @import("main.zig");
const socket = @import("socket.zig");
const tree = @import("tree.zig");

var subscribe_reader: std.net.Stream.Reader = undefined;
const subscribe = subscribe_reader.interface();
var run_writer: std.net.Stream.Writer = undefined;
const run = &run_writer.interface;

/// Connect to both sockets.
pub fn init() !void {
    subscribe_reader = socket.connect().reader(&.{});
    run_writer = socket.connect().writer(&.{});
    tree.init();
}

pub fn deinit() void {
    std.net.Stream.Reader.getStream(&subscribe_reader).close();
    std.net.Stream.Writer.getStream(&run_writer).close();
    tree.deinit();
}

/// Argument passed to the move command.
pub const MoveDirection = enum { left, right, up, down };

/// Move window or swap containers.
pub fn containerMove(direction: MoveDirection) !void {
    const containers = (try tree.workspaceFocused()).nodes;
    for (containers, 0..) |container, index_container| {
        if (container.focused) {
            const swap_id = if (direction == .left and index_container > 0)
                containers[index_container - 1].id
            else if (direction == .right and index_container < containers.len - 1)
                containers[index_container + 1].id
            else
                return;
            return socket.write(run, .command, try std.fmt.allocPrint(
                main.fba,
                "swap container with con_id {d}",
                .{swap_id},
            ));
        }
        const windows = container.nodes;
        for (windows, 0..) |window, index_window| {
            const focused_middle = window.focused and
                (direction != .up or index_window != 0) and
                (direction != .down or index_window != windows.len - 1);
            if (focused_middle)
                return socket.write(run, .command, try std.fmt.allocPrint(main.fba,
                    \\ move {t}
                , .{direction}));
        }
    }
}

/// Argument to the focus command.
pub const FocusTarget = enum { column, window, toggle };

/// Focus column or window.
pub fn containerFocus(target: FocusTarget) !void {
    if (target != .column)
        for ((try tree.workspaceFocused()).nodes) |container|
            if (container.focused)
                return socket.write(run, .command, "focus child");
    if (target != .window)
        return socket.write(run, .command, "focus parent");
}

/// Argument to the layout command.
pub const LayoutMode = enum { splitv, stacking, toggle };

/// Switch the column's layout.
pub fn containerLayout(mode: LayoutMode) !void {
    const layout =
        if (mode == .toggle) "toggle splitv stacking" else @tagName(mode);
    for ((try tree.workspaceFocused()).nodes) |container|
        if (container.focused)
            return socket.write(run, .command, try std.fmt.allocPrint(main.fba,
                \\focus child; layout {s}; focus parent
            , .{layout}));
    return socket.write(run, .command, try std.fmt.allocPrint(main.fba,
        \\layout {s}
    , .{layout}));
}

/// Split windows or flatten containers.
pub fn layoutArrange() !void {
    var command: std.ArrayList(u8) = .empty;
    for (try tree.workspaceAll()) |workspace| {
        const columns = workspace.nodes;
        if (columns.len == 1 and columns[0].nodes.len == 1) {
            try command.print(main.fba,
                \\[con_id={d}] split n; 
            , .{columns[0].nodes[0].id});
            continue;
        }
        if (columns.len >= 1 and std.mem.eql(u8, workspace.layout, "splitv")) {
            try command.print(main.fba,
                \\[con_id={d}] move right, move left; 
            , .{columns[0].id});
            for (0..columns[0].nodes.len) |_|
                try command.print(main.fba,
                    \\[con_id={d}] move up; 
                , .{columns[0].id});
            continue;
        }
        for (columns) |column| {
            if (columns.len >= 2 and std.mem.eql(u8, column.layout, "none"))
                try command.print(main.fba,
                    \\[con_id={d}] split v; 
                , .{column.id});
            for (column.nodes) |window| {
                if (std.mem.eql(u8, window.layout, "none")) continue;
                try command.print(main.fba,
                    \\[con_id={0d}] mark swaycolumns_last; 
                    \\[con_id={1d}] move mark swaycolumns_last, move right; 
                    \\[con_id={0d}] unmark swaycolumns_last; 
                , .{ workspace.nodes[workspace.nodes.len - 1].id, window.id });
            }
        }
    }
    if (command.items.len > 0)
        return socket.write(run, .command, command.items);
}

/// Change the layout tree and reset buffer.
fn layoutApply() !bool {
    defer main.fba_state.reset();
    const event =
        try socket.readParse(subscribe, struct { change: []const u8 });
    if (std.mem.eql(u8, event.change, "exit")) return true;
    const tree_changed =
        std.mem.eql(u8, event.change, "focus") or
        std.mem.eql(u8, event.change, "new") or
        std.mem.eql(u8, event.change, "close") or
        std.mem.eql(u8, event.change, "floating") or
        std.mem.eql(u8, event.change, "move");
    if (tree_changed) try layoutArrange();
    return false;
}

/// Subscribe to window events and run the main loop.
pub fn layoutStart() !void {
    const subscribe_stream = std.net.Stream.Reader.getStream(&subscribe_reader);
    var subscribe_writer = subscribe_stream.writer(&.{});
    const events = "[\"window\", \"shutdown\"]";
    try socket.write(&subscribe_writer.interface, .subscribe, events);
    _ = try socket.read(subscribe);
    try layoutArrange();
    while (true) {
        const exited = layoutApply() catch |err| switch (err) {
            error.OutOfMemory,
            error.SyntaxError,
            error.UnexpectedEndOfInput,
            error.NotFound,
            => {
                std.log.err("{}\n", .{err});
                std.Thread.sleep(5 * std.time.ns_per_s);
                continue;
            },
            else => return err,
        };
        if (exited) return;
    }
}
