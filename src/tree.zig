//! Tree parsing logic.

const std = @import("std");

const socket = @import("socket.zig");

pub const Node = struct {
    id: u32,
    type: []const u8,
    layout: []const u8,
    marks: []const []const u8,
    focused: bool,
    nodes: []@This(),
    floating_nodes: []@This(),
};

fn get() !Node {
    try socket.tree.write("");
    try socket.tree.commit();
    return socket.tree.parse(Node);
}

fn containsFocused(node: Node) bool {
    if (node.focused) return true;
    for (node.nodes) |node_inner|
        if (containsFocused(node_inner)) return true;
    for (node.floating_nodes) |floating_node_inner|
        if (containsFocused(floating_node_inner)) return true;
    return false;
}

pub fn workspaceFocused() !Node {
    for ((try get()).nodes) |output|
        for (output.nodes) |workspace|
            if (containsFocused(workspace)) return workspace;
    return error.WorkspaceNotFound;
}

pub fn workspaceAll() ![]Node {
    for ((try get()).nodes) |output|
        if (containsFocused(output)) return output.nodes;
    return error.WorkspaceNotFound;
}
