const std = @import("std");

const socket = @import("socket.zig");
const tree = @import("tree.zig");

pub fn swap(con_id: u32) !void {
    try socket.run.print("swap container with con_id {d};", .{con_id});
}

pub const MoveDirection = enum { left, right, up, down };

pub fn move(direction: MoveDirection) !void {
    try socket.run.print("move {t};", .{direction});
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
    const layout_choice =
        if (mode == .toggle) "toggle splitv stacking" else @tagName(mode);
    switch (focused) {
        .window => try socket.run.print(
            \\layout {s};
        , .{layout_choice}),
        .column => try socket.run.print(
            \\focus child; layout {s}; focus parent;
        , .{layout_choice}),
    }
}

pub fn drop(action: enum { move, swap }) !void {
    const drop_action =
        if (action == .move) "move" else "swap container with";
    // zig fmt: off
    try socket.run.print(
        \\[con_mark = _swaycolumns_drag]
        ++ \\    {s} mark _swaycolumns_drop,
        ++ \\    unmark _swaycolumns_drag,
        ++ \\    focus;
        ++ \\[con_mark = _swaycolumns_drop] unmark _swaycolumns_drop;
    , .{drop_action});
    // zig fmt: on
}

const BindsymState = enum { set, unset, reset };
var previous_state: BindsymState = .unset;

pub fn drag(state: BindsymState, mod: []const u8) !void {
    if (state == .unset and previous_state != .unset) {
        try socket.run.print(
            \\unbindsym --whole-window {0s}+button1;
            \\unbindsym --whole-window --release {0s}+button1;
        , .{mod});
        previous_state = .unset;
    } else if (state == .set and previous_state != .set or state == .reset) {
        // zig fmt: off
        try socket.run.print(
            \\bindsym --whole-window {0s}+button1 mark --add _swaycolumns_drag;
            \\bindsym --whole-window --release {0s}+button1 "
            ++ \\    mark --add _swaycolumns_drop;
            ++ \\    exec swaycolumns drop;
            ++ \\"
        , .{mod});
        // zig fmt: on
        previous_state = .set;
    }
}

pub fn columnNone(containers: []tree.Node) !void {
    try socket.run.print(
        \\[con_id={d}] split n;
    , .{containers[0].nodes[0].id});
}

pub fn columnSingle(containers: []tree.Node) !void {
    try socket.run.print(
        \\[con_id={d}] move right, move left;
    , .{containers[0].id});
    for (0..containers[0].nodes.len) |_|
        try socket.run.print(
            \\[con_id={d}] move up; 
        , .{containers[0].id});
}

pub fn columnMultiple(containers: []tree.Node) !void {
    for (containers) |column| {
        if (containers.len >= 2 and std.mem.eql(u8, column.layout, "none"))
            try socket.run.print(
                \\[con_id={d}] split v;
            , .{column.id});
        for (column.nodes) |window|
            if (!std.mem.eql(u8, window.layout, "none"))
                for (0..containers.len) |_|
                    try socket.run.print(
                        \\[con_id={d}] move right;
                    , .{window.id});
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
