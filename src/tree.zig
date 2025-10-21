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

/// Quickly ensure that the given string is a JSON-encoded Sway layout tree.
inline fn isCorrect(tree_str: []const u8) bool {
    return tree_str.len >= 1000 and
        tree_str[0] == '{' and
        tree_str[tree_str.len - 1] == '}';
}

/// Get the layout tree in JSON form.
fn get() ![]const u8 {
    try socket.write(&tree_writer, .tree, "");
    const tree_str = try socket.read(&tree_reader);
    std.debug.assert(isCorrect(tree_str));
    return tree_str;
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

fn containsFocused(node: Node) bool {
    if (node.focused) return true;
    for (node.nodes) |node_inner|
        if (containsFocused(node_inner)) return true;
    for (node.floating_nodes) |node_inner|
        if (containsFocused(node_inner)) return true;
    return false;
}

pub fn workspaceFocused() !Node {
    const string = try get();
    const tree = try std.json.parseFromSliceLeaky(Node, main.fba, string, .{
        .ignore_unknown_fields = true,
    });
    for (tree.nodes) |output|
        for (output.nodes) |workspace|
            if (containsFocused(workspace)) return workspace;
    return error.WorkspaceNotFound;
}

pub fn workspaceAll() ![]Node {
    const string = try get();
    const tree = try std.json.parseFromSliceLeaky(Node, main.fba, string, .{
        .ignore_unknown_fields = true,
    });
    for (tree.nodes) |output|
        if (containsFocused(output))
            return output.nodes;
    return error.WorkspaceNotFound;
}
