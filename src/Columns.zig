//! Main tiling logic.

const std = @import("std");
const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const json = std.json;
const mem = std.mem;

const Socket = @import("Socket.zig");
const Tree = @import("Tree.zig");

subscribe: Socket,
command: Socket,

/// Connect to both sockets.
pub fn init(buf: []u8) Socket.ErrorSwaysock!@This() {
    debug.assert(buf.len >= 1500);
    const subscribe = try Socket.init(buf[buf.len / 8 ..]);
    errdefer subscribe.deinit();
    const command = try Socket.init(buf[0 .. buf.len / 8]);
    errdefer command.deinit();
    return .{ .subscribe = subscribe, .command = command };
}

/// Disconnect from both sockets.
pub fn deinit(self: @This()) void {
    self.subscribe.deinit();
    self.command.deinit();
}

/// Sway layout tree node.
pub const Node = struct {
    id: u32,
    layout: []const u8,
    focused: bool,
    nodes: []@This(),
};

pub const GetTarget = enum { focused, all };

/// Parse the layout tree and return workspaces.
pub fn workspaceGet(self: @This(), comptime target: GetTarget) Socket.ErrorWriteRead![]const Node {
    const tree = try Tree.init(self.command);
    const buf = self.command.buf[tree.json_str.len..];
    var fba = heap.FixedBufferAllocator.init(buf);
    const allocator = fba.allocator();
    const isolate = if (target == .all)
        Tree.isolateAll
    else
        Tree.isolateFocused;
    const string = isolate(tree) orelse {
        return allocator.dupe(Node, &.{});
    };
    const options: json.ParseOptions = .{ .ignore_unknown_fields = true };
    if (target == .all) {
        return json.parseFromSliceLeaky(
            []const Node,
            allocator,
            string,
            options,
        );
    } else {
        const parsed = try json.parseFromSliceLeaky(
            Node,
            allocator,
            string,
            options,
        );
        return allocator.dupe(Node, &.{parsed});
    }
}

pub const MoveDirection = enum { left, right, up, down };

/// Move window or swap containers.
pub fn containerMove(self: @This(), comptime direction: MoveDirection) Socket.ErrorWriteRead!void {
    const tree = (try self.workspaceGet(.focused))[0];
    for (tree.nodes, 0..) |container, index_container| {
        if (container.focused) {
            const swap_id = if (direction == .left and index_container > 0)
                tree.nodes[index_container - 1].id
            else if (direction == .right and index_container < tree.nodes.len - 1)
                tree.nodes[index_container + 1].id
            else
                return;
            const string = fmt.bufPrint(
                self.subscribe.buf,
                "swap container with con_id {d}",
                .{swap_id},
            ) catch unreachable;
            _ = try self.command.writeReadRaw(.command, string);
            return;
        }
        for (container.nodes, 0..) |window, index_window| {
            const focused_middle =
                window.focused and
                (direction != .up or index_window != 0) and
                (direction != .down or index_window != container.nodes.len - 1);
            if (!focused_middle) {
                continue;
            }
            const string = "move " ++ @tagName(direction);
            _ = try self.command.writeReadRaw(.command, string);
            return;
        }
    }
}

pub const FocusTarget = enum { column, window, toggle };

/// Focus column or window.
pub fn containerFocus(self: @This(), comptime target: FocusTarget) Socket.ErrorWriteRead!void {
    const tree = (try self.workspaceGet(.focused))[0];
    if (target != .column) {
        for (tree.nodes) |container| {
            if (!container.focused) {
                continue;
            }
            _ = try self.command.writeReadRaw(.command, "focus child");
            return;
        }
    }
    if (target != .window) {
        _ = try self.command.writeReadRaw(.command, "focus parent");
    }
}

pub const LayoutMode = enum { splitv, stacking, toggle };

/// Switch the column's layout.
pub fn containerLayout(self: @This(), comptime mode: LayoutMode) Socket.ErrorWriteRead!void {
    const tree = (try self.workspaceGet(.focused))[0];
    const layout = if (mode == .toggle)
        "layout toggle splitv stacking"
    else
        "layout " ++ @tagName(mode);
    for (tree.nodes) |container| {
        if (!container.focused) {
            continue;
        }
        const string = "focus child;" ++ layout ++ "; focus parent";
        _ = try self.command.writeReadRaw(.command, string);
        return;
    }
    _ = try self.command.writeReadRaw(.command, layout);
}

pub const ArrangeOptions = struct { fix_nested: bool = true };

/// Split windows or flatten containers with an option to eject nested containers.
pub fn layoutArrange(self: @This(), comptime options: ArrangeOptions) Socket.ErrorWriteRead!void {
    const trees = try self.workspaceGet(.all);
    var len: usize = 0;
    for (trees) |workspace| {
        if (workspace.nodes.len == 1) {
            const column = workspace.nodes[0];
            if (column.nodes.len != 1) {
                continue;
            }
            const window = column.nodes[0];
            const commands = fmt.bufPrint(
                self.subscribe.buf[len..],
                "[con_id={d}] split n; ",
                .{window.id},
            ) catch unreachable;
            len += commands.len;
            continue;
        }
        for (workspace.nodes) |column| {
            if (workspace.nodes.len >= 2 and mem.eql(u8, column.layout, "none")) {
                const commands = fmt.bufPrint(
                    self.subscribe.buf[len..],
                    "[con_id={d}] split v; ",
                    .{column.id},
                ) catch unreachable;
                len += commands.len;
            }
            if (!options.fix_nested) {
                continue;
            }
            for (column.nodes) |window| {
                if (mem.eql(u8, window.layout, "none")) {
                    continue;
                }
                const commands = fmt.bufPrint(
                    self.subscribe.buf[len..],
                    "mark swaycolumns_before; " ++
                        "[con_id={0d}] mark swaycolumns_last; " ++
                        "[con_id={1d}] move mark swaycolumns_last, move right; " ++
                        "[con_id={0d}] unmark swaycolumns_last; " ++
                        "[con_mark=swaycolumns_before] focus; " ++
                        "unmark swaycolumns_before",
                    .{
                        workspace.nodes[workspace.nodes.len - 1].id,
                        window.id,
                    },
                ) catch unreachable;
                len += commands.len;
            }
        }
    }
    if (len > 0) {
        _ = try self.command.writeReadRaw(.command, self.subscribe.buf[0..len]);
    }
}

/// Subscribe to window events and run the main loop.
pub fn layoutStart(self: @This()) Socket.ErrorWriteRead!noreturn {
    const Result = struct { success: bool };
    const subscribed = try self.subscribe.writeRead(
        Result,
        .subscribe,
        "[\"window\", \"workspace\"]",
    );
    debug.assert(subscribed.success);
    try self.layoutArrange(.{});
    while (true) {
        const Event = struct { change: []const u8, current: ?struct {} = null };
        const event = try self.subscribe.read(Event);
        const tree_changed =
            (event.current != null and mem.eql(u8, event.change, "focus")) or
            mem.eql(u8, event.change, "new") or
            mem.eql(u8, event.change, "close") or
            mem.eql(u8, event.change, "move") or
            mem.eql(u8, event.change, "floating");
        if (tree_changed) {
            try self.layoutArrange(.{});
        }
    }
}
