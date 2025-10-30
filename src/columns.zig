//! Main tiling logic.

const std = @import("std");

const main = @import("main.zig");
const socket = @import("socket.zig");

fn tree(T: type) !T {
    try socket.tree.addString("");
    try socket.tree.commit();
    return socket.tree.parse(T);
}

fn run(comptime fmt: []const u8, args: anytype) !void {
    try socket.run.add(fmt, args);
    try socket.run.commit();
    try socket.run.discard();
}

fn runString(payload: []const u8) !void {
    try socket.run.addString(payload);
    try socket.run.commit();
    try socket.run.discard();
}

pub const Direction = enum { left, right, up, down };

pub fn move(direction: Direction) !void {
    const Root = struct {
        nodes: []const Output,
        pub const Output = struct { nodes: []const Workspace };
        pub const Workspace = struct {
            focused: bool,
            nodes: []const Column,
            floating_nodes: []const Column,
        };
        pub const Column = struct { focused: bool, id: u32, nodes: []const Window };
        pub const Window = struct { focused: bool };
    };
    const Focused = union(enum) {
        column_tiled: struct { []const Root.Column, usize },
        window_tiled: struct { []const Root.Column, usize, []const Root.Window, usize },
        window_float: struct { []const Root.Window, usize },
    };
    const root = try tree(Root);
    const focused: Focused = loop: for (root.nodes) |output| {
        for (output.nodes) |workspace| {
            if (workspace.focused) return;
            for (workspace.nodes, 0..) |column, column_index| {
                if (column.focused)
                    break :loop .{ .column_tiled = .{ workspace.nodes, column_index } };
                for (column.nodes, 0..) |window, window_index|
                    if (window.focused) {
                        const window_tiled = .{ workspace.nodes, column_index, column.nodes, window_index };
                        break :loop .{ .window_tiled = window_tiled };
                    };
            }
            for (workspace.floating_nodes) |column_float| {
                if (column_float.focused) return;
                for (column_float.nodes, 0..) |window_float, window_float_index|
                    if (window_float.focused)
                        break :loop .{ .window_float = .{ column_float.nodes, window_float_index } };
            }
        }
    } else return;
    switch (focused) {
        .column_tiled => |location| {
            const columns, const column_index = location;
            const swap_index = switch (direction) {
                .left => if (column_index > 0) column_index - 1 else return,
                .right => if (column_index < columns.len - 1) column_index + 1 else return,
                else => return,
            };
            return run("swap container with con_id {};", .{columns[swap_index].id});
        },
        .window_tiled => |location| {
            const columns, const column_index, const windows, const window_index = location;
            switch (direction) {
                .up => if (window_index > 0) return run("move up;", .{}),
                .down => if (window_index < windows.len - 1) return run("move down;", .{}),
                .left => if (column_index > 0 or windows.len > 1) return run("move left;", .{}),
                .right => {
                    if (column_index < columns.len - 1) return run("move right, move down;", .{});
                    if (windows.len > 1) return run("move right;", .{});
                },
            }
        },
        .window_float => |location| {
            const windows, const window_index = location;
            switch (direction) {
                .up => if (window_index > 0) return run("move up;", .{}),
                .down => if (window_index < windows.len - 1) return run("move down;", .{}),
                else => return,
            }
        },
    }
}

pub const Target = enum { window, column, workspace, toggle };

pub fn focus(target: Target) !void {
    const Root = struct {
        nodes: []const Output,
        pub const Output = struct { nodes: []const Workspace };
        pub const Workspace = struct {
            focused: bool,
            nodes: []const Column,
            floating_nodes: []const Column,
        };
        pub const Column = struct { focused: bool, nodes: []const Window };
        pub const Window = struct { focused: bool };
    };
    const Focused = enum {
        workspace,
        column_tiled,
        window_tiled,
        container_float,
        column_float,
        window_float,
    };
    const root = try tree(Root);
    const focused: Focused = loop: for (root.nodes) |output| {
        for (output.nodes) |workspace| {
            if (workspace.focused) break :loop .workspace;
            for (workspace.nodes) |column| {
                if (column.focused) break :loop .column_tiled;
                for (column.nodes) |window|
                    if (window.focused) break :loop .window_tiled;
            }
            for (workspace.floating_nodes) |column_float| {
                if (column_float.focused) {
                    if (column_float.nodes.len == 0) break :loop .container_float;
                    break :loop .column_float;
                }
                for (column_float.nodes) |window_float|
                    if (window_float.focused) break :loop .window_float;
            }
        }
    } else return;
    switch (focused) {
        .workspace => switch (target) {
            .window, .toggle => return runString("focus child, focus child;"),
            .column => return runString("focus child;"),
            .workspace => return,
        },
        .column_tiled, .column_float => switch (target) {
            .window => return runString("focus child;"),
            .column => return,
            .workspace, .toggle => return runString("focus parent;"),
        },
        .window_tiled, .window_float => switch (target) {
            .window => return,
            .column, .toggle => return runString("focus parent;"),
            .workspace => return runString("focus parent, focus parent;"),
        },
        .container_float => switch (target) {
            .window, .column => return,
            .workspace, .toggle => return runString("focus parent;"),
        },
    }
}

pub const Mode = enum { splitv, stacking, toggle };

pub fn layout(mode: Mode) !void {
    const Root = struct {
        nodes: []const Output,
        pub const Output = struct { nodes: []const Workspace };
        pub const Workspace = struct {
            focused: bool,
            nodes: []const Column,
            floating_nodes: []const Column,
        };
        pub const Column = struct { focused: bool, nodes: []const Window };
        pub const Window = struct { focused: bool };
    };
    const Focused = union(enum) {
        column_tiled,
        window_tiled,
        container_float,
        column_float: usize,
        window_float,
    };
    const root = try tree(Root);
    const focused: Focused = loop: for (root.nodes) |output| {
        for (output.nodes) |workspace| {
            if (workspace.focused) return;
            for (workspace.nodes) |column| {
                if (column.focused) break :loop .column_tiled;
                for (column.nodes) |window|
                    if (window.focused) break :loop .window_tiled;
            }
            for (workspace.floating_nodes) |column_float| {
                if (column_float.focused) {
                    const window_count = column_float.nodes.len;
                    if (window_count == 0) break :loop .container_float;
                    break :loop .{ .column_float = window_count };
                }
                for (column_float.nodes) |window_float|
                    if (window_float.focused) break :loop .window_float;
            }
        }
    } else return;
    switch (mode) {
        inline else => |mode_inline| {
            const toggle = "layout toggle splitv stacking;";
            const set = "layout " ++ @tagName(mode_inline) ++ ";";
            const payload = switch (focused) {
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
                .column_float => |window_count| switch (mode_inline) {
                    .toggle, .splitv => if (window_count == 1) "focus child; split n" else return,
                    .stacking => return,
                },
                .window_float => switch (mode_inline) {
                    .toggle, .splitv => "split n;",
                    .stacking => return,
                },
            };
            return runString(payload);
        },
    }
}

pub fn tile() !void {
    @branchHint(.likely);
    const Root = struct {
        nodes: []const Output,
        pub const Output = struct { nodes: []const Workspace };
        pub const Workspace = struct { layout: []const u8, nodes: []const Column };
        pub const Column = struct { id: u32, layout: []const u8, nodes: []const Window };
        pub const Window = struct { layout: []const u8, id: u32 };
    };
    const root = try tree(Root);
    for (root.nodes) |output| {
        for (output.nodes) |workspace| {
            const columns = workspace.nodes;
            if (columns.len == 1 and columns[0].nodes.len == 1) {
                const windows = columns[0].nodes;
                try socket.run.add("[con_id = {}] split n;", .{windows[0].id});
            } else if (columns.len >= 1 and std.mem.eql(u8, workspace.layout, "splitv")) {
                try socket.run.add("[con_id = {}] move right, move left;", .{columns[0].id});
                for (0..columns[0].nodes.len) |_|
                    try socket.run.add("[con_id = {}] move up;", .{columns[0].id});
            } else for (columns) |column| {
                if (columns.len >= 2 and std.mem.eql(u8, column.layout, "none"))
                    try socket.run.add("[con_id = {}] split v;", .{column.id});
                for (column.nodes) |window| {
                    if (!std.mem.eql(u8, window.layout, "none")) // eject nested
                        for (0..columns.len) |_|
                            try socket.run.add("[con_id = {}] move right;", .{window.id});
                }
            }
        }
    }
    if (socket.run.writer.interface.end - 14 == 0) return;
    try socket.run.commit();
    try socket.run.discard();
}

pub const Modifier = enum { super, mod4, alt, mod1 };
const HotkeyState = enum { set, unset, reset };
var state_previous: HotkeyState = .unset;

fn dragReset(mod: Modifier) !void {
    state_previous = .reset;
    try drag(mod);
}

inline fn drag(mod: Modifier) !void {
    const Root = struct {
        nodes: []const Output,
        const Output = struct { nodes: []const Workspace };
        const Workspace = struct { focused: bool, floating_nodes: []const Column };
        const Column = struct { focused: bool, nodes: []const Window };
        const Window = struct { focused: bool };
    };
    const root = try tree(Root);
    const state: HotkeyState = loop: for (root.nodes) |output| {
        for (output.nodes) |workspace|
            for (workspace.floating_nodes) |column_float| {
                if (column_float.focused) break :loop .unset;
                for (column_float.nodes) |window_float|
                    if (window_float.focused) break :loop .unset;
            };
    } else .set;
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
            const payload, const current_state: HotkeyState =
                if (state == .unset) .{ unset, .unset } else .{ set, .set };
            try runString(payload);
            state_previous = current_state;
        },
    };
}

pub fn drop() !void {
    const Root = struct {
        nodes: []const Output,
        const Output = struct { nodes: []const Workspace };
        const Workspace = struct { nodes: []const Column };
        const Column = struct { id: u32, nodes: []const Window };
        const Window = struct { marks: []const []const u8 };
    };
    const root = try tree(Root);
    const DropAction = enum { move, swap };
    const action: DropAction = outer: for (root.nodes) |output| {
        for (output.nodes) |workspace|
            for (workspace.nodes) |column| {
                const drag_column = inner: for (column.nodes) |window| {
                    for (window.marks) |mark|
                        if (std.mem.eql(u8, mark, "_swaycolumns_drag")) break :inner column.id;
                } else continue;
                const drop_column = inner: for (column.nodes) |window| {
                    for (window.marks) |mark|
                        if (std.mem.eql(u8, mark, "_swaycolumns_drop")) break :inner column.id;
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
            return runString(mark_drag ++ mark_drop);
        },
    }
}

inline fn reload(mod_or_null: ?Modifier) !void {
    try tile();
    if (mod_or_null) |mod| try dragReset(mod);
}

pub fn start(mod_or_null: ?Modifier) !void {
    try socket.subscribe.addString("[\"window\", \"workspace\", \"shutdown\"]");
    try socket.subscribe.commit();
    try socket.subscribe.discard();
    try reload(mod_or_null);
    while (true) {
        defer main.fba_state.reset();
        const event = try socket.subscribe.parse(struct { change: []const u8 });
        if (std.mem.eql(u8, event.change, "reload")) {
            @branchHint(.unlikely);
            return reload(mod_or_null);
        }
        const tree_changed =
            std.mem.eql(u8, event.change, "focus") or
            std.mem.eql(u8, event.change, "floating") or
            std.mem.eql(u8, event.change, "new") or
            std.mem.eql(u8, event.change, "close") or
            std.mem.eql(u8, event.change, "move");
        if (tree_changed) {
            try tile();
            if (mod_or_null) |mod| try drag(mod);
        }
    }
}
