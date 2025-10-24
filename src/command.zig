const std = @import("std");

const socket = @import("socket.zig");
const tree = @import("tree.zig");

pub fn swap(con_id: u32) !void {
    try socket.run.print("swap container with con_id {};", .{con_id});
}

pub const MoveDirection = enum { left, right, up, down };

pub fn move(direction: MoveDirection) !void {
    switch (direction) {
        inline else => |direction_inline| {
            try socket.run.write("move " ++ @tagName(direction_inline) ++ ";");
        },
    }
}

pub const FocusCurrent =
    enum { window, column, workspace, float, float_window, float_column };
pub const FocusTarget =
    enum { window, column, workspace, toggle };

pub fn focus(focused: FocusCurrent, target: FocusTarget) !void {
    try socket.run.write(switch (focused) {
        .window, .float_window => switch (target) {
            .window => return,
            .column, .toggle => "focus parent;",
            .workspace => "focus parent; focus parent;",
        },
        .column, .float_column => switch (target) {
            .window => "focus child;",
            .column => return,
            .workspace, .toggle => "focus parent;",
        },
        .workspace => switch (target) {
            .window, .toggle => "focus child; focus child;",
            .column => "focus child;",
            .workspace => return,
        },
        .float => switch (target) {
            .window, .column => return,
            .workspace, .toggle => "focus parent;",
        },
    });
}

pub const LayoutMode = enum { splitv, stacking, toggle };

pub fn layout(focused: FocusCurrent, mode: LayoutMode) !void {
    switch (mode) {
        inline else => |mode_inline| {
            const toggle = "layout toggle splitv stacking;";
            const set = "layout " ++ @tagName(mode_inline) ++ ";";
            try socket.run.write(switch (focused) {
                .window => switch (mode_inline) {
                    .toggle => toggle,
                    else => set,
                },
                .column => switch (mode_inline) {
                    .toggle => "focus child;" ++ toggle ++ "focus parent;",
                    else => "focus child;" ++ set ++ "focus parent;",
                },
                .float => switch (mode_inline) {
                    .toggle => "split v; " ++ toggle,
                    else => "split v; " ++ set,
                },
                .float_window => switch (mode_inline) {
                    .toggle, .splitv => "split n;",
                    .stacking => return,
                },
                .float_column => switch (mode_inline) {
                    .toggle, .splitv => "focus child; split n",
                    .stacking => return,
                },
                .workspace => return,
            });
        },
    }
}

pub const DropAction = enum { move, swap };

pub fn drop(action: DropAction) !void {
    switch (action) {
        inline else => |action_inline| {
            const mark_drag =
                "[con_mark = _swaycolumns_drag]" ++ switch (action_inline) {
                    .move => "move mark _swaycolumns_drop,",
                    .swap => "swap container with mark _swaycolumns_drop,",
                } ++ "unmark _swaycolumns_drag, focus;";
            const mark_drop =
                "[con_mark = _swaycolumns_drop] unmark _swaycolumns_drop;";
            try socket.run.write(mark_drag ++ mark_drop);
        },
    }
}

pub const Modifier = enum { super, mod4, alt, mod1 };
const HotkeyState = enum { set, unset, reset };
var previous_state: HotkeyState = .unset;

pub fn drag(mod: Modifier, state: HotkeyState) !void {
    std.debug.assert(previous_state != .reset);
    if (state == previous_state) {
        @branchHint(.likely);
        return;
    }
    switch (mod) {
        inline else => |mod_inline| {
            const hotkey = @tagName(mod_inline) ++ "+button1 ";
            const unset =
                "unbindsym --whole-window " ++ hotkey ++ ";" ++
                "unbindsym --whole-window --release " ++ hotkey ++ ";";
            const set =
                "bindsym --whole-window " ++ hotkey ++
                "mark --add _swaycolumns_drag;" ++
                "bindsym --whole-window --release " ++ hotkey ++
                "'mark --add _swaycolumns_drop; exec swaycolumns drop';";
            const payload, const current_state: HotkeyState =
                if (state == .unset) .{ unset, .unset } else .{ set, .set };
            try socket.run.write(payload);
            previous_state = current_state;
        },
    }
}

pub fn columnNone(containers: []tree.Node) !void {
    const window = containers[0].nodes[0];
    try socket.run.print("[con_id = {}] split n;", .{window.id});
}

pub fn columnSingle(containers: []tree.Node) !void {
    const column = containers[0];
    try socket.run.print("[con_id = {}] move right, move left;", .{column.id});
    for (0..column.nodes.len) |_|
        try socket.run.print("[con_id = {}] move up;", .{column.id});
}

pub fn columnMultiple(containers: []tree.Node) !void {
    @branchHint(.likely);
    for (containers) |column| {
        if (containers.len >= 2 and std.mem.eql(u8, column.layout, "none"))
            try socket.run.print("[con_id = {}] split v;", .{column.id});
        for (column.nodes) |window| {
            if (std.mem.eql(u8, window.layout, "none")) continue;
            for (0..containers.len) |_|
                try socket.run.print("[con_id = {}] move right;", .{window.id});
        }
    }
}

pub fn commit() !void {
    if (socket.run.writer.interface.end - 14 == 0) return;
    try socket.run.commit();
    try socket.run.discard();
}

pub fn listen(events: []const u8) !void {
    try socket.subscribe.write(events);
    try socket.subscribe.commit();
    try socket.subscribe.discard();
}

pub fn parse(T: type) !T {
    return try socket.subscribe.parse(T);
}
