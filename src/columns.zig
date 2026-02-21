const std = @import("std");

const main = @import("main.zig");

fn treeParse(T: type) !T {
    @branchHint(.likely);
    try main.tree.add("");
    try main.tree.commit();
    return main.tree.parse(T);
}

fn runPrint(comptime fmt: []const u8, args: anytype) !void {
    try main.run.addPrint(fmt, args);
    try main.run.commit();
    try main.run.discard();
}

fn run(command: []const u8) !void {
    try main.run.add(command);
    try main.run.commit();
    try main.run.discard();
}

fn subscribe(events: []const u8) !void {
    try main.subscribe.add(events);
    try main.subscribe.commit();
    try main.subscribe.discard();
}

fn eql(first: []const u8, second: []const u8) bool {
    return std.mem.eql(u8, first, second);
}

const Indices = union(enum) {
    workspace: struct { u32, u32 },
    container_tiled: struct { u32, u32, u32 },
    container_float: struct { u32, u32, u32 },
    column_tiled: struct { u32, u32, u32 },
    column_float: struct { u32, u32, u32 },
    window_tiled: struct { u32, u32, u32, u32 },
    window_float: struct { u32, u32, u32, u32 },
};

fn u32Tuple(index: usize) struct { u32 } {
    return .{@intCast(index)};
}

fn focused(tree: anytype) ?Indices {
    for (tree.nodes, 0..) |output, output_index| {
        const indices_0 = u32Tuple(output_index);
        for (output.nodes, 0..) |workspace, workspace_index| {
            const indices_0_1 = indices_0 ++ u32Tuple(workspace_index);
            if (workspace.focused) return .{ .workspace = indices_0_1 };
            for (workspace.floating_nodes, 0..) |column_float, column_float_index| {
                const indices_0_1_2 = indices_0_1 ++ u32Tuple(column_float_index);
                if (column_float.focused) {
                    if (column_float.nodes.len == 0) return .{ .container_float = indices_0_1_2 };
                    return .{ .column_float = indices_0_1_2 };
                }
                for (column_float.nodes, 0..) |window_float, window_float_index| {
                    const indices_0_1_2_3 = indices_0_1_2 ++ u32Tuple(window_float_index);
                    if (window_float.focused) return .{ .window_float = indices_0_1_2_3 };
                }
            }
            for (workspace.nodes, 0..) |column, column_index| {
                const indices_0_1_2 = indices_0_1 ++ u32Tuple(column_index);
                if (column.focused) {
                    if (column.nodes.len == 0) return .{ .container_tiled = indices_0_1_2 };
                    return .{ .column_tiled = indices_0_1_2 };
                }
                for (column.nodes, 0..) |window, window_index| {
                    const indices_0_1_2_3 = indices_0_1_2 ++ u32Tuple(window_index);
                    if (window.focused) return .{ .window_tiled = indices_0_1_2_3 };
                }
            }
        }
    }
    return null;
}

pub const Direction = enum { left, right, up, down };

pub fn move(direction: Direction) !void {
    const Window = struct { focused: bool };
    const Column = struct { nodes: []const Window, focused: bool, id: u32 };
    const Workspace = struct {
        nodes: []const Column,
        floating_nodes: []const Column,
        focused: bool,
    };
    const Output = struct { nodes: []const Workspace };
    const tree = try treeParse(struct { nodes: []const Output });
    switch (focused(tree) orelse return) {
        .column_tiled => |indices| {
            const columns = tree.nodes[indices.@"0"].nodes[indices.@"1"].nodes;
            const swap_index = switch (direction) {
                .left => if (indices.@"2" > 0) indices.@"2" - 1 else return,
                .right => if (indices.@"2" < columns.len - 1) indices.@"2" + 1 else return,
                else => return,
            };
            return runPrint("swap container with con_id {};", .{columns[swap_index].id});
        },
        .window_tiled => |indices| {
            const columns = tree.nodes[indices.@"0"].nodes[indices.@"1"].nodes;
            const windows = columns[indices.@"2"].nodes;
            switch (direction) {
                .up => if (indices.@"3" > 0) return run("move up;"),
                .down => if (indices.@"3" < windows.len - 1) return run("move down;"),
                .left => if (indices.@"2" > 0 or windows.len > 1) return run("move left;"),
                .right => {
                    if (indices.@"2" < columns.len - 1) return run("move right, move down;");
                    if (windows.len > 1) return run("move right;");
                },
            }
        },
        .window_float => |indices| {
            const windows = tree.nodes[indices.@"0"].nodes[indices.@"1"].nodes[indices.@"2"].nodes;
            switch (direction) {
                .up => if (indices.@"3" > 0) return run("move up;"),
                .down => if (indices.@"3" < windows.len - 1) return run("move down;"),
                else => return,
            }
        },
        .workspace, .container_tiled, .container_float, .column_float => return,
    }
}

pub fn moveWorkspace(target: enum { name, number }, identifier: []const u8) !void {
    const Window = struct { focused: bool, id: u32 };
    const Column = struct { nodes: []const Window, focused: bool, id: u32 };
    const Workspace = struct {
        nodes: []const Column,
        floating_nodes: []const Column,
        focused: bool,
        name: []const u8,
        num: ?i32 = null,
    };
    const Output = struct { nodes: []const Workspace };
    const tree = try treeParse(struct { nodes: []const Output });
    const target_container_count = switch (target) {
        .name => block: {
            for (tree.nodes) |output|
                for (output.nodes) |workspace|
                    if (eql(workspace.name, identifier)) break :block workspace.nodes.len;
            break :block null;
        },
        .number => block: {
            const number_parsed = std.fmt.parseUnsigned(u32, identifier, 10) catch
                return error.NumberInvalid;
            for (tree.nodes) |output|
                for (output.nodes) |workspace|
                    if (workspace.num orelse continue == number_parsed)
                        break :block workspace.nodes.len;
            break :block null;
        },
    };
    const specifier = switch (target) {
        .name => "",
        .number => "number",
    };
    switch (focused(tree) orelse return) {
        .column_tiled => |indices| {
            const column = tree.nodes[indices.@"0"].nodes[indices.@"1"].nodes[indices.@"2"];
            const count = target_container_count orelse 0;
            if (count == 0) {
                return runPrint(
                    "[con_id = {}] move workspace {s} {s};" ++
                        "[con_id = {}] layout splith, layout splitv;",
                    .{ column.id, specifier, identifier, column.nodes[0].id },
                );
            }
            try main.run.addPrint(
                "[con_id = {}] move workspace {s} {s};",
                .{ column.id, specifier, identifier },
            );
            for (0..count) |_|
                try main.run.addPrint("[con_id = {}] move right,", .{column.id});
            return main.run.commit();
        },
        .workspace => if (target_container_count orelse 0 != 0) return,
        else => {},
    }
    return runPrint("move workspace {s} {s};", .{ specifier, identifier });
}

pub const Target = enum { window, column, workspace, toggle };

pub fn focus(target: Target) !void {
    const Window = struct { focused: bool };
    const Column = struct { nodes: []const Window, focused: bool };
    const Workspace = struct {
        nodes: []const Column,
        floating_nodes: []const Column,
        focused: bool,
    };
    const Output = struct { nodes: []const Workspace };
    const tree = try treeParse(struct { nodes: []const Output });
    switch (focused(tree) orelse return) {
        .workspace => switch (target) {
            .window, .toggle => return run("focus child, focus child;"),
            .column => return run("focus child;"),
            .workspace => return,
        },
        .column_tiled, .column_float => switch (target) {
            .window => return run("focus child;"),
            .column => return,
            .workspace, .toggle => return run("focus parent;"),
        },
        .window_tiled, .window_float => switch (target) {
            .window => return,
            .column, .toggle => return run("focus parent;"),
            .workspace => return run("focus parent, focus parent;"),
        },
        .container_tiled, .container_float => switch (target) {
            .window, .column => return,
            .workspace, .toggle => return run("focus parent;"),
        },
    }
}

pub const Mode = enum { splitv, stacking, toggle };

pub fn layout(mode: Mode) !void {
    const Window = struct { focused: bool };
    const Column = struct { nodes: []const Window, focused: bool };
    const Workspace = struct {
        nodes: []const Column,
        floating_nodes: []const Column,
        focused: bool,
    };
    const Output = struct { nodes: []const Workspace };
    const tree = try treeParse(struct { nodes: []const Output });
    switch (mode) {
        inline else => |mode_inline| {
            const toggle = "layout toggle splitv stacking;";
            const set = "layout " ++ @tagName(mode_inline) ++ ";";
            const command = switch (focused(tree) orelse return) {
                .container_tiled => switch (mode_inline) {
                    .toggle => "layout toggle stacking splitv;",
                    .splitv, .stacking => set,
                },
                .column_tiled => switch (mode_inline) {
                    .toggle => "focus child;" ++ toggle ++ "focus parent;",
                    .splitv, .stacking => "focus child;" ++ set ++ "focus parent;",
                },
                .window_tiled => switch (mode_inline) {
                    .toggle => toggle,
                    .splitv, .stacking => set,
                },
                .container_float => switch (mode_inline) {
                    .toggle => "split v; " ++ toggle,
                    .splitv, .stacking => "split v; " ++ set,
                },
                .column_float => |indices| block: {
                    const windows = tree.nodes[indices.@"0"].nodes[indices.@"1"]
                        .floating_nodes[indices.@"2"].nodes;
                    if (windows.len != 1) return;
                    switch (mode_inline) {
                        .toggle, .splitv => break :block "focus child; split n;",
                        .stacking => return,
                    }
                },
                .window_float => switch (mode_inline) {
                    .toggle, .splitv => "split n;",
                    .stacking => return,
                },
                .workspace => return,
            };
            return run(command);
        },
    }
}

fn tile() !void {
    @branchHint(.likely);
    const Window = struct { id: u32, layout: []const u8 };
    const Column = struct { nodes: []const Window, id: u32, layout: []const u8 };
    const Workspace = struct { nodes: []const Column, orientation: []const u8 };
    const Output = struct { nodes: []const Workspace };
    const tree = try treeParse(struct { nodes: []const Output });
    for (tree.nodes) |output|
        for (output.nodes) |workspace|
            for (workspace.nodes) |column| {
                const window_to_unsplit =
                    workspace.nodes.len == 1 and
                    column.nodes.len == 1 and
                    eql(column.layout, "splitv");
                if (window_to_unsplit) {
                    try main.run.addPrint("[con_id = {}] split n;", .{column.nodes[0].id});
                    break;
                }
                const workspace_is_vertical =
                    workspace.nodes.len == 1 and
                    eql(workspace.orientation, "vertical");
                if (workspace_is_vertical) {
                    try main.run.addPrint("[con_id = {}] split h;", .{column.id});
                    break;
                }
                const windows_to_split =
                    workspace.nodes.len >= 2 and
                    eql(column.layout, "none") and
                    !eql(workspace.orientation, "vertical");
                if (windows_to_split) {
                    try main.run.addPrint("[con_id = {}] split v;", .{column.id});
                    continue;
                }
            };
    if (main.run.lengthWrite() == 0) return;
    try main.run.commit();
    try main.run.discard();
}

pub const Modifier = enum { super, mod4, alt, mod1 };
const HotkeyState = enum { set, unset, reset };
var state_previous: HotkeyState = .unset;

fn dragReset(mod: Modifier) !void {
    state_previous = .reset;
    try drag(mod);
}

inline fn drag(mod: Modifier) !void {
    @branchHint(.likely);
    const Window = struct { focused: bool };
    const Column = struct { nodes: []const Window, focused: bool };
    const Workspace = struct {
        nodes: []const Column,
        floating_nodes: []const Column,
        focused: bool,
    };
    const Output = struct { nodes: []const Workspace };
    const tree = try treeParse(struct { nodes: []const Output });
    const state: HotkeyState = block: {
        switch (focused(tree) orelse break :block .set) {
            .container_float, .column_float, .window_float => break :block .unset,
            else => break :block .set,
        }
    };
    if (state != state_previous) switch (mod) {
        inline else => |mod_inline| {
            const button = @tagName(mod_inline) ++ "+button1 ";
            const unset =
                "unbindsym --whole-window " ++ button ++ ";" ++
                "unbindsym --whole-window --release " ++ button ++ ";";
            const set =
                "bindsym --whole-window " ++ button ++
                "mark --add _swaycolumns_drag;" ++
                "bindsym --whole-window --release " ++ button ++
                "'mark --add _swaycolumns_drop; exec swaycolumns drop';";
            const command, const current_state: HotkeyState =
                if (state == .unset) .{ unset, .unset } else .{ set, .set };
            defer state_previous = current_state;
            return run(command);
        },
    };
}

pub fn drop() !void {
    const Window = struct { marks: []const []const u8 };
    const Column = struct { nodes: []const Window, id: u32 };
    const Workspace = struct { nodes: []const Column };
    const Output = struct { nodes: []const Workspace };
    const tree = try treeParse(struct { nodes: []const Output });
    const action: enum { move, swap } = outer: for (tree.nodes) |output| {
        for (output.nodes) |workspace|
            for (workspace.nodes) |column| {
                const drag_column = inner: for (column.nodes) |window| {
                    for (window.marks) |mark|
                        if (eql(mark, "_swaycolumns_drag")) break :inner column.id;
                } else continue;
                const drop_column = inner: for (column.nodes) |window| {
                    for (window.marks) |mark|
                        if (eql(mark, "_swaycolumns_drop")) break :inner column.id;
                } else continue;
                if (drag_column == drop_column) break :outer .swap else return;
            };
    } else .move;
    switch (action) {
        inline else => |action_inline| {
            const mark_drag =
                "[con_mark = _swaycolumns_drag]" ++ switch (action_inline) {
                    .move => "move mark _swaycolumns_drop,",
                    .swap => "swap container with mark _swaycolumns_drop,",
                } ++ "unmark _swaycolumns_drag, focus;";
            const mark_drop =
                "[con_mark = _swaycolumns_drop] unmark _swaycolumns_drop;";
            return run(mark_drag ++ mark_drop);
        },
    }
}

inline fn reload(mod_or_null: ?Modifier) !void {
    @branchHint(.unlikely);
    try tile();
    if (mod_or_null) |mod| try dragReset(mod);
}

pub fn start(mod_or_null: ?Modifier) !void {
    try subscribe("[\"window\", \"workspace\", \"shutdown\"]");
    try reload(mod_or_null);
    while (true) {
        defer main.fba.reset();
        const event = try main.subscribe.parse(struct { change: []const u8 });
        if (eql(event.change, "reload")) return reload(mod_or_null);
        const tree_changed =
            eql(event.change, "focus") or
            eql(event.change, "new") or
            eql(event.change, "close") or
            eql(event.change, "move") or
            eql(event.change, "floating");
        if (!tree_changed) continue;
        try tile();
        if (mod_or_null) |mod| try drag(mod);
    }
}
