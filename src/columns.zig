//! Main tiling logic.

const std = @import("std");

const command = @import("command.zig");
const main = @import("main.zig");
const socket = @import("socket.zig");
const tree = @import("tree.zig");

pub fn move(direction: command.MoveDirection) !void {
    @branchHint(.likely);
    const workspace = try tree.workspaceFocused();
    const columns = workspace.nodes;
    for (columns, 0..) |column, column_index| {
        if (!column.focused) continue;
        if (direction == .left and column_index > 0)
            try command.swap(columns[column_index - 1].id)
        else if (direction == .right and column_index < columns.len - 1)
            try command.swap(columns[column_index + 1].id);
        break;
    } else for (columns, 0..) |column, column_index| {
        for (column.nodes, 0..) |window, window_index| {
            if (!window.focused) continue;
            if (direction == .up and window_index == 0) continue;
            if (direction == .down and
                window_index == column.nodes.len - 1) continue;
            try command.move(direction);
            if (direction == .right and
                column_index != columns.len - 1) try command.move(.down);
            break;
        }
    } else if (try focused() orelse return == .float_window) // TODO
        try command.move(direction);
    try command.commit();
}

fn focused() !?command.FocusCurrent {
    const workspace = try tree.workspaceFocused();
    if (workspace.focused) return .workspace;
    for (workspace.floating_nodes) |float|
        if (float.focused) {
            if (std.mem.eql(u8, float.layout, "none")) return .float;
            return .float_column;
        } else for (float.nodes) |float_window|
            if (float_window.focused) return .float_window;
    for (workspace.nodes) |column| {
        if (column.focused) return .column;
        for (column.nodes) |window|
            if (window.focused) return .window;
    } else return null;
}
pub fn focus(target: command.FocusTarget) !void {
    try command.focus(try focused() orelse return, target);
    try command.commit();
}

pub fn layout(mode: command.LayoutMode) !void {
    try command.layout(try focused() orelse return, mode);
    try command.commit();
}

pub fn drop() !void {
    try command.drop(for ((try tree.workspaceFocused()).nodes) |column| {
        const drag_column = inner: for (column.nodes) |window| {
            for (window.marks) |mark|
                if (std.mem.eql(u8, mark, "_swaycolumns_drag"))
                    break :inner column.id;
        } else continue;
        const drop_column = inner: for (column.nodes) |window| {
            for (window.marks) |mark|
                if (std.mem.eql(u8, mark, "_swaycolumns_drop"))
                    break :inner column.id;
        } else continue;
        if (drag_column == drop_column) break .swap else return;
    } else .move);
    try command.commit();
}

fn tile() !void {
    @branchHint(.likely);
    for (try tree.workspaceAll()) |workspace| {
        const mode = workspace.layout;
        const columns = workspace.nodes;
        if (columns.len == 1 and columns[0].nodes.len == 1)
            try command.columnNone(columns)
        else if (columns.len >= 1 and std.mem.eql(u8, mode, "splitv"))
            try command.columnSingle(columns)
        else
            try command.columnMultiple(columns);
    }
    try command.commit();
}

inline fn drag(mod_or_null: ?command.Modifier) !void {
    const mod = mod_or_null orelse return;
    const float_focused = switch (try focused() orelse return) {
        .float, .float_window, .float_column => true,
        else => false,
    };
    try command.drag(mod, if (float_focused) .unset else .set);
}

inline fn reload(mod_or_null: ?command.Modifier) !void {
    @branchHint(.unlikely);
    try tile();
    try command.drag(mod_or_null orelse return, .reset);
}

const Event = struct { change: []const u8, container: ?tree.Node = null };

fn apply(mod_or_null: ?command.Modifier) !bool {
    defer main.fba_state.reset();
    const event = try command.parse(Event);
    if (std.mem.eql(u8, event.change, "reload")) try reload(mod_or_null);
    const tree_changed =
        std.mem.eql(u8, event.change, "focus") or
        std.mem.eql(u8, event.change, "floating") or
        std.mem.eql(u8, event.change, "new") or
        std.mem.eql(u8, event.change, "close") or
        std.mem.eql(u8, event.change, "move");
    if (tree_changed) {
        try drag(mod_or_null);
        try tile();
    }
    return true;
}

pub fn start(mod_or_null: ?command.Modifier) !void {
    try command.listen("[\"window\", \"workspace\", \"shutdown\"]");
    try reload(mod_or_null);
    while (try apply(mod_or_null)) {}
}
