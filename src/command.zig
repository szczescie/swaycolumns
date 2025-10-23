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

pub const FocusCurrent = enum { window, column, workspace };
pub const FocusTarget = enum { window, column, workspace, toggle };

pub fn focus(focused: FocusCurrent, target: FocusTarget) !void {
    const payload = switch (focused) {
        .window => switch (target) {
            .window => return,
            .column, .toggle => "focus parent;",
            .workspace => "focus parent; focus parent;",
        },
        .column => switch (target) {
            .window => "focus child;",
            .column => return,
            .workspace, .toggle => "focus parent;",
        },
        .workspace => switch (target) {
            .window, .toggle => "focus child; focus child;",
            .column => "focus child;",
            .workspace => return,
        },
    };
    try socket.run.write(payload);
}

pub const LayoutMode = enum { splitv, stacking, toggle };

pub fn layout(focused: enum { window, column }, mode: LayoutMode) !void {
    switch (focused) {
        inline else => |focused_inline| switch (mode) {
            inline else => |mode_inline| try socket.run.write(comptime block: {
                var payload: []const u8 = switch (mode_inline) {
                    .toggle => "layout toggle splitv stacking;",
                    else => "layout " ++ @tagName(mode_inline) ++ ";",
                };
                if (focused_inline == .column)
                    payload = "focus child;" ++ payload ++ "focus parent;";
                break :block payload;
            }),
        },
    }
}

pub fn drop(action: enum { move, swap }) !void {
    switch (action) {
        inline else => |action_inline| try socket.run.write(
            "[con_mark = _swaycolumns_drag]" ++ switch (action_inline) {
                .move => "move mark _swaycolumns_drop,",
                .swap => "swap container with mark _swaycolumns_drop,",
            } ++ "unmark _swaycolumns_drag, focus;" ++
                "[con_mark = _swaycolumns_drop] unmark _swaycolumns_drop;",
        ),
    }
}

pub const Modifier = enum { super, mod4, alt, mod1 };
const HotkeyState = enum { set, unset, reset };
var previous_state: HotkeyState = .unset;

pub fn drag(mod: Modifier, state: HotkeyState) !void {
    if (state == previous_state) return;
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
            try socket.run.write(if (state == .unset) unset else set);
            previous_state = if (state == .unset) .unset else .set;
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
    for (0..containers[0].nodes.len) |_|
        try socket.run.print("[con_id = {}] move up;", .{column.id});
}

pub fn columnMultiple(containers: []tree.Node) !void {
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
