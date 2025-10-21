//! Tree parsing logic.

const std = @import("std");

const columns = @import("columns.zig");
const main = @import("main.zig");
const socket = @import("socket.zig");

var tree_writer: std.net.Stream.Writer = undefined;
var tree_reader: std.net.Stream.Reader = undefined;

pub fn init() void {
    const tree_socket = socket.connect();
    tree_writer = tree_socket.writer(&.{});
    tree_reader = tree_socket.reader(&.{});
}

pub fn deinit() void {
    std.net.Stream.Writer.getStream(&tree_writer).close();
}

/// Sway layout tree node.
pub const Node = struct {
    id: u32,
    type: []const u8,
    layout: []const u8,
    marks: []const []const u8,
    focused: bool,
    nodes: []@This(),
    floating_nodes: []@This(),
};

pub fn parse(T: type, string: []const u8) T {
    return std.json.parseFromSliceLeaky(T, main.fba, string, .{
        .ignore_unknown_fields = true,
    });
}

/// Get the layout tree.
fn get() !Node {
    try socket.write(&tree_writer, .tree, "");
    const string = try socket.read(&tree_reader);
    return parse(Node, string);
}

fn containsFocused(node: Node) bool {
    if (node.focused) return true;
    for (node.nodes) |node_inner|
        if (containsFocused(node_inner)) return true;
    for (node.floating_nodes) |node_inner|
        if (containsFocused(node_inner)) return true;
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
