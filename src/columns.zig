//! Main tiling logic.

const std = @import("std");

const main = @import("main.zig");
const socket = @import("socket.zig");
const tree = @import("tree.zig");

var subscribe_writer: std.net.Stream.Writer = undefined;
var subscribe_reader: std.net.Stream.Reader = undefined;
var run_writer: std.net.Stream.Writer = undefined;
var run_reader: std.net.Stream.Reader = undefined;

/// Connect to both sockets.
pub fn init() !void {
    const subscribe_socket = socket.connect();
    subscribe_writer = subscribe_socket.writer(&.{});
    subscribe_reader = subscribe_socket.reader(&.{});
    const run_socket = socket.connect();
    run_writer = run_socket.writer(&.{});
    run_reader = run_socket.reader(&.{});
    tree.init();
}

pub fn deinit() void {
    std.net.Stream.Reader.getStream(&subscribe_reader).close();
    std.net.Stream.Writer.getStream(&run_writer).close();
    tree.deinit();
}

/// Argument passed to the move command.
pub const MoveDirection = enum { left, right, up, down };

/// Move window or swap columns.
pub fn move(direction: MoveDirection) !void {
    const columns = (try tree.workspaceFocused()).nodes;
    for (columns, 0..) |container, index_container| {
        if (container.focused) {
            const swap_id = if (direction == .left and index_container > 0)
                columns[index_container - 1].id
            else if (direction == .right and index_container < columns.len - 1)
                columns[index_container + 1].id
            else
                return;
            try socket.print(&run_writer, .run,
                \\swap container with con_id {d}
            , .{swap_id});
            try socket.discard(&run_reader);
            return;
        }
        const windows = container.nodes;
        for (container.nodes, 0..) |window, index_window| {
            const focused_middle = window.focused and
                (direction != .up or index_window != 0) and
                (direction != .down or index_window != windows.len - 1);
            if (focused_middle) {
                try socket.print(&run_writer, .run, "move {t}", .{direction});
                try socket.discard(&run_reader);
                return;
            }
        }
    }
}

/// Argument to the focus command.
pub const FocusTarget = enum { window, column, workspace, toggle };

/// Focus column or window.
pub fn focus(target: FocusTarget) !void {
    const focused: enum { window, column, workspace } = block: {
        const workspace = try tree.workspaceFocused();
        if (workspace.focused) break :block .workspace;
        for (workspace.nodes) |column| {
            if (column.focused) break :block .column;
            for (column.nodes) |window|
                if (window.focused) break :block .window;
        } else return;
    };
    try socket.write(&run_writer, .run, switch (focused) {
        .window => switch (target) {
            .window => return,
            .column, .toggle => "focus parent",
            .workspace => "focus parent; focus parent",
        },
        .column => switch (target) {
            .window => "focus child",
            .column => return,
            .workspace, .toggle => "focus parent",
        },
        .workspace => switch (target) {
            .window, .toggle => "focus child; focus child",
            .column => "focus child",
            .workspace => return,
        },
    });
    try socket.discard(&run_reader);
}

/// Argument to the layout command.
pub const LayoutMode = enum { splitv, stacking, toggle };

/// Switch the column's layout.
pub fn layout(mode: LayoutMode) !void {
    const workspace = try tree.workspaceFocused();
    if (workspace.focused) return;
    const layout_mode =
        if (mode == .toggle) "toggle splitv stacking" else @tagName(mode);
    for (workspace.nodes) |column|
        if (column.focused) {
            try socket.print(&run_writer, .run,
                \\focus child; layout {s}; focus parent
            , .{layout_mode});
            try socket.discard(&run_reader);
            return;
        };
    try socket.print(&run_writer, .run, "layout {s}", .{layout_mode});
    try socket.discard(&run_reader);
}

pub fn drop() !void {
    const action = outer: for ((try tree.workspaceFocused()).nodes) |column| {
        const drag_column = inner: for (column.nodes) |window| {
            for (window.marks) |mark|
                if (std.mem.eql(u8, mark, "swaycolumns_drag"))
                    break :inner column.id;
        } else continue;
        const drop_column = inner: for (column.nodes) |window| {
            for (window.marks) |mark|
                if (std.mem.eql(u8, mark, "swaycolumns_drop"))
                    break :inner column.id;
        } else continue;
        if (drag_column == drop_column) break :outer "swap container with";
    } else "move";
    // zig fmt: off
    try socket.print(&run_writer, .run,
        \\[con_mark = swaycolumns_drag]
        ++ \\    {s} mark swaycolumns_drop,
        ++ \\    unmark swaycolumns_drag,
        ++ \\    focus;
        ++ \\[con_mark = swaycolumns_drop] unmark swaycolumns_drop
    , .{action});
    // zig fmt: on
    try socket.discard(&run_reader);
}

const Event = struct { change: []const u8, container: ?tree.Node = null };
var dragging_bindsym = false;

fn dragging(mod: []const u8, event: Event) !void {
    const container = event.container orelse return;
    if (std.mem.eql(u8, container.type, "floating_con")) {
        if (dragging_bindsym) {
            try socket.print(&run_writer, .run,
                \\unbindsym --whole-window {0s}+button1;
                \\unbindsym --whole-window --release {0s}+button1
            , .{mod});
            try socket.discard(&run_reader);
            dragging_bindsym = false;
        }
        return;
    }
    if (!dragging_bindsym) {
        // zig fmt: off
        try socket.print(&run_writer, .run,
            \\bindsym --whole-window {0s}+button1 mark --add swaycolumns_drag;
            \\bindsym --whole-window --release {0s}+button1 "
            ++ \\    mark --add swaycolumns_drop;
            ++ \\    exec swaycolumns drop
            ++ \\"
        , .{mod});
        // zig fmt: on
        try socket.discard(&run_reader);
        dragging_bindsym = true;
    }
}

/// Split windows or flatten containers.
pub fn arrange() !void {
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
            for (0..columns[0].nodes.len) |_| try command.print(main.fba,
                \\[con_id={d}] move up; 
            , .{columns[0].id});
            continue;
        }
        for (columns) |column| {
            if (columns.len >= 2 and std.mem.eql(u8, column.layout, "none"))
                try command.print(main.fba,
                    \\[con_id={d}] split v; 
                , .{column.id});
            for (column.nodes) |window|
                if (!std.mem.eql(u8, window.layout, "none"))
                    for (0..columns.len) |_| try command.print(main.fba,
                        \\[con_id={d}] move right; 
                    , .{window.id});
        }
    }
    if (command.items.len > 0)
        try socket.write(&run_writer, .run, command.items);
}

/// Modify the layout tree.
fn apply(mod: []const u8) !bool {
    const string = try socket.read(&subscribe_reader);
    const event = try std.json.parseFromSliceLeaky(Event, main.fba, string, .{
        .ignore_unknown_fields = true,
    });
    if (std.mem.eql(u8, event.change, "exit")) return true;
    if (std.mem.eql(u8, event.change, "reload")) dragging_bindsym = false;
    const tree_changed =
        std.mem.eql(u8, event.change, "focus") or
        std.mem.eql(u8, event.change, "new") or
        std.mem.eql(u8, event.change, "close") or
        std.mem.eql(u8, event.change, "floating") or
        std.mem.eql(u8, event.change, "move");
    if (tree_changed) {
        try dragging(mod, event);
        try arrange();
    }
    return false;
}

/// Subscribe to window events and run the main loop.
pub fn start(mod: []const u8) !void {
    const events = "[\"window\", \"workspace\", \"shutdown\"]";
    try socket.write(&subscribe_writer, .subscribe, events);
    _ = try socket.read(&subscribe_reader);
    try arrange();
    while (true) {
        defer main.fba_state.reset();
        const exited = apply(mod) catch |err| switch (err) {
            error.OutOfMemory,
            error.SyntaxError,
            error.UnexpectedEndOfInput,
            error.WorkspaceNotFound,
            => {
                std.log.err("{}", .{err});
                std.Thread.sleep(1 * std.time.ns_per_s);
                continue;
            },
            else => return err,
        };
        if (exited) return;
    }
}
