//! Main tiling logic.

const std = @import("std");

const command = @import("command.zig");
const main = @import("main.zig");
const socket = @import("socket.zig");
const tree = @import("tree.zig");

pub fn move(direction: command.MoveDirection) !void {
    @branchHint(.likely);
    const columns = (try tree.workspaceFocused()).nodes;
    for (columns, 0..) |column, column_index| {
        if (!column.focused) continue;
        if (direction == .left and column_index > 0)
            try command.swap(columns[column_index - 1].id)
        else if (direction == .right and column_index < columns.len - 1)
            try command.swap(columns[column_index + 1].id);
        break;
    } else for (columns, 0..) |column, column_index|
        for (column.nodes, 0..) |window, window_index| {
            if (!window.focused) continue;
            if (direction == .up and window_index == 0) continue;
            if (direction == .down and
                window_index == column.nodes.len - 1) continue;
            try command.move(direction);
            if (direction == .right and
                column_index != columns.len - 1) try command.move(.down);
            break;
        };
    try command.commit();
}

pub fn focus(target: command.FocusTarget) !void {
    const focused: command.FocusCurrent = block: {
        const workspace = try tree.workspaceFocused();
        if (workspace.focused) break :block .workspace;
        for (workspace.nodes) |column| {
            if (column.focused) break :block .column;
            for (column.nodes) |window|
                if (window.focused) break :block .window;
        } else return;
    };
    try command.focus(focused, target);
    try command.commit();
}

pub fn layout(mode: command.LayoutMode) !void {
    const workspace = try tree.workspaceFocused();
    if (workspace.focused) return;
    const focused: command.FocusCurrent = for (workspace.nodes) |column| {
        if (column.focused) break .column;
    } else .window;
    try command.layout(focused, mode);
    try command.commit();
}

pub fn drop() !void {
    const action: command.DropAction =
        outer: for ((try tree.workspaceFocused()).nodes) |column| {
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
            if (drag_column == drop_column) break :outer .swap else return;
        } else .move;
    try command.drop(action);
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

inline fn reload(mod_or_null: ?command.Modifier) !void {
    if (mod_or_null) |mod| try command.drag(mod, .reset);
    try tile();
}

const Event = struct { change: []const u8, container: ?tree.Node = null };

fn apply(mod_or_null: ?command.Modifier) !bool {
    defer main.fba_state.reset();
    const event = try command.parse(Event);
    if (std.mem.eql(u8, event.change, "exit")) return false;
    if (std.mem.eql(u8, event.change, "reload")) try reload(mod_or_null);
    const focus_change =
        std.mem.eql(u8, event.change, "focus") or
        std.mem.eql(u8, event.change, "floating");
    if (!focus_change and
        !std.mem.eql(u8, event.change, "new") and
        !std.mem.eql(u8, event.change, "close") and
        !std.mem.eql(u8, event.change, "move")) return true;
    if (mod_or_null) |mod| if (event.container) |container| if (focus_change) {
        const floating_con = std.mem.eql(u8, container.type, "floating_con");
        try command.drag(mod, if (floating_con) .unset else .set);
    };
    try tile();
    return true;
}

pub fn start(mod_or_null: ?command.Modifier) !void {
    try command.listen("[\"window\", \"workspace\", \"shutdown\"]");
    try reload(mod_or_null);
    while (try apply(mod_or_null)) {}
}
