//! Main tiling logic.

const std = @import("std");

const command = @import("command.zig");
const tree = @import("tree.zig");

pub fn move(direction: command.MoveDirection) !void {
    const columns = (try tree.workspaceFocused()).nodes;
    for (columns, 0..) |column, column_index| {
        if (!column.focused) continue;
        if (direction == .left and column_index > 0)
            try command.swap(columns[column_index - 1].id)
        else if (direction == .right and column_index < columns.len - 1)
            try command.swap(columns[column_index + 1].id);
        try command.commit();
        return;
    }
    for (columns, 0..) |column, column_index|
        for (column.nodes, 0..) |window, window_index| {
            if (!window.focused) continue;
            if (direction == .up and window_index == 0) continue;
            if (direction == .down and
                window_index == column.nodes.len - 1) continue;
            try command.move(direction);
            if (direction == .right and
                column_index != columns.len - 1) try command.move(.down);
            try command.commit();
            return;
        };
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
    for (workspace.nodes) |column| {
        if (!column.focused) continue;
        try command.layout(.column, mode);
        break;
    } else try command.layout(.window, mode);
    try command.commit();
}

pub fn drop() !void {
    for ((try tree.workspaceFocused()).nodes) |column| {
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
        if (drag_column == drop_column) {
            try command.drop(.swap);
            break;
        } else return;
    } else try command.drop(.move);
    try command.commit();
}

const Event = struct { change: []const u8, container: ?tree.Node = null };

fn tile() !void {
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

fn reload(mod: []const u8) !void {
    try command.drag(.reset, mod);
    try tile();
}

fn apply(mod: []const u8) !bool {
    const event = try command.parse(Event);
    if (std.mem.eql(u8, event.change, "exit")) return true;
    if (std.mem.eql(u8, event.change, "reload")) try reload(mod);
    const tree_changed =
        std.mem.eql(u8, event.change, "focus") or
        std.mem.eql(u8, event.change, "new") or
        std.mem.eql(u8, event.change, "close") or
        std.mem.eql(u8, event.change, "floating") or
        std.mem.eql(u8, event.change, "move");
    if (!tree_changed) return false;
    if (event.container) |container|
        if (std.mem.eql(u8, container.type, "floating_con")) {
            try command.drag(.unset, mod);
        } else try command.drag(.set, mod);
    try tile();
    return false;
}

pub fn start(mod: []const u8) !void {
    try command.listen("[\"window\", \"workspace\", \"shutdown\"]");
    try reload(mod);
    while (true) {
        const exited = apply(mod) catch |err| switch (err) {
            error.OutOfMemory,
            error.SyntaxError,
            error.UnexpectedEndOfInput,
            error.WorkspaceNotFound,
            => {
                std.log.debug("{}", .{err});
                std.Thread.sleep(1 * std.time.ns_per_s);
                continue;
            },
            else => return err,
        };
        if (exited) return;
    }
}
