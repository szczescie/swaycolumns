//! Tree parsing logic.

const std = @import("std");

const columns = @import("columns.zig");
const main = @import("main.zig");
const socket = @import("socket.zig");

var tree_reader: std.net.Stream.Reader = undefined;
const tree = tree_reader.interface();

pub fn init() void {
    tree_reader = socket.connect().reader(&.{});
}

pub fn deinit() void {
    std.net.Stream.Reader.getStream(&tree_reader).close();
}

/// Quickly ensure that the given string is a JSON-encoded Sway layout tree.
inline fn isCorrect(tree_str: []const u8) bool {
    return tree_str.len >= 1000 and
        tree_str[0] == '{' and
        tree_str[tree_str.len - 1] == '}';
}

/// Get the layout tree in JSON form.
fn get() ![]const u8 {
    const tree_stream = std.net.Stream.Reader.getStream(&tree_reader);
    var tree_writer = tree_stream.writer(&.{});
    try socket.write(&tree_writer.interface, .tree, "");
    const tree_str = try socket.read(tree);
    std.debug.assert(isCorrect(tree_str));
    return tree_str;
}

/// Extract all workspaces other than the scratchpad.
fn isolateAll(tree_str: []const u8) ![]const u8 {
    var @"type" = std.mem.indexOfPosLinear(u8, tree_str, 800, "pe\": \"w") orelse
        return error.NotFound;
    @"type" = std.mem.indexOfPosLinear(u8, tree_str, @"type" + 1000, "pe\": \"w") orelse
        return error.NotFound;
    const start = std.mem.lastIndexOfScalar(u8, tree_str[0 .. @"type" - 10], '{') orelse
        return error.NotFound;
    const repr = std.mem.lastIndexOfLinear(u8, tree_str[0 .. tree_str.len - 500], ", \"rep") orelse
        return error.NotFound;
    const end = std.mem.indexOfScalarPos(u8, tree_str, repr + 15, '}') orelse
        return error.NotFound;
    return tree_str[start - 2 .. end + 3];
}

/// Extract the focused workspace.
fn isolateFocused(tree_str: []const u8) ![]const u8 {
    const focused = std.mem.indexOfPosLinear(u8, tree_str, 2000, "d\": t") orelse
        return error.NotFound;
    const @"type" = std.mem.lastIndexOfLinear(u8, tree_str[0 .. focused - 400], "pe\": \"w") orelse
        return error.NotFound;
    const start = std.mem.lastIndexOfScalar(u8, tree_str[0 .. @"type" - 10], '{') orelse
        return error.NotFound;
    const repr = std.mem.indexOfPosLinear(u8, tree_str, focused + 800, ", \"rep") orelse
        return error.NotFound;
    const end = std.mem.indexOfScalarPos(u8, tree_str, repr + 15, '}') orelse
        return error.NotFound;
    return tree_str[start .. end + 1];
}

/// Sway layout tree node.
pub const Node = struct {
    id: u32,
    layout: []const u8,
    focused: bool,
    nodes: []@This(),
};

pub fn workspaceFocused() !Node {
    const string = try isolateFocused(try get());
    return std.json.parseFromSliceLeaky(Node, main.fba, string, .{
        .ignore_unknown_fields = true,
    });
}

pub fn workspaceAll() ![]Node {
    const string = try isolateAll(try get());
    return std.json.parseFromSliceLeaky([]Node, main.fba, string, .{
        .ignore_unknown_fields = true,
    });
}
