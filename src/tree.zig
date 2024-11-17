//! Tree parsing logic.

const std = @import("std");
const assert = std.debug.assert;
const indexOfPosLinear = std.mem.indexOfPosLinear;
const indexOfScalarPos = std.mem.indexOfScalarPos;
const lastIndexOfLinear = std.mem.lastIndexOfLinear;
const lastIndexOfScalar = std.mem.lastIndexOfScalar;
const log = std.log;
const parseFromSliceLeaky = std.json.parseFromSliceLeaky;

const Columns = @import("columns.zig");
const interact = &Columns.interact_sock;
const main = @import("main.zig");
const fba = &main.fba;
const Swaysock = @import("Swaysock.zig");
const json_options = Swaysock.json_options;

/// Quickly ensure that the given string is a JSON-encoded Sway layout tree.
inline fn isCorrect(tree_str: []const u8) bool {
    return tree_str.len >= 1000 and tree_str[0] == '{' and tree_str[tree_str.len - 1] == '}';
}

/// Get the layout tree in JSON form.
fn get() ![]const u8 {
    const tree_str = try interact.writeRead(.tree, "");
    log.debug("got tree of length: {d}", .{tree_str.len});
    assert(isCorrect(tree_str));
    return tree_str;
}

/// Extract all workspaces other than the scratchpad.
fn isolateAll(tree_str: []const u8) ![]const u8 {
    var @"type" = indexOfPosLinear(u8, tree_str, 800, "pe\": \"w") orelse {
        log.warn("\"type\": \"workspace\" of scratchpad not found in tree", .{});
        return error.NotFound;
    };
    @"type" = indexOfPosLinear(u8, tree_str, @"type" + 1000, "pe\": \"w") orelse {
        const format = "\"type\": \"workspace\" of first workspace not found; last index was {}";
        log.warn(format, .{@"type"});
        return error.NotFound;
    };
    const start = lastIndexOfScalar(u8, tree_str[0 .. @"type" - 10], '{') orelse {
        const format = "beginning brace of first workspace not found; last index was {}";
        log.warn(format, .{@"type"});
        return error.NotFound;
    };
    const repr = lastIndexOfLinear(u8, tree_str[0 .. tree_str.len - 500], ", \"rep") orelse {
        const format = "\"representation\" of last workspace not found; last index was {}";
        log.warn(format, .{start});
        return error.NotFound;
    };
    const end = indexOfScalarPos(u8, tree_str, repr + 15, '}') orelse {
        const format = "ending brace of last workspace not found; last index was {}";
        log.warn(format, .{repr});
        return error.NotFound;
    };
    return tree_str[start - 2 .. end + 3];
}

/// Extract the focused workspace.
fn isolateFocused(tree_str: []const u8) ![]const u8 {
    const focused = indexOfPosLinear(u8, tree_str, 2000, "d\": t") orelse {
        log.warn("\"focused\": true not found", .{});
        return error.NotFound;
    };
    const @"type" = lastIndexOfLinear(u8, tree_str[0 .. focused - 400], "pe\": \"w") orelse {
        log.warn("\"type\": \"workspace\" not found; last index was {}", .{focused});
        return error.NotFound;
    };
    const start = lastIndexOfScalar(u8, tree_str[0 .. @"type" - 10], '{') orelse {
        log.warn("beginning brace not found; last index was {}", .{@"type"});
        return error.NotFound;
    };
    const repr = indexOfPosLinear(u8, tree_str, focused + 800, ", \"rep") orelse {
        log.warn("\"representation\" not found; last index was {}", .{start});
        return error.NotFound;
    };
    const end = indexOfScalarPos(u8, tree_str, repr + 15, '}') orelse {
        log.warn("ending brace not found; last index was {}", .{repr});
        return error.NotFound;
    };
    return tree_str[start .. end + 1];
}

/// All workspaces or only the focused workspace.
pub const GetTarget = enum { all, focused };
/// Sway layout tree node.
pub const Node = struct { id: u32, layout: []const u8, focused: bool, nodes: []@This() };

/// Return the correct result type for the target.
inline fn ParseResult(comptime target: GetTarget) type {
    return if (target == .all) []Node else Node;
}

/// Read and then parse the Sway layout tree and return the result.
pub fn getParsed(comptime target: GetTarget) !ParseResult(target) {
    const T = ParseResult(target);
    const workspace_str = try (if (target == .all) isolateAll else isolateFocused)(try get());
    const result = parseFromSliceLeaky(T, fba.*, workspace_str, json_options) catch |err| {
        log.warn("{}: parsing failed for string \"{s}\"", .{ err, workspace_str });
        return err;
    };
    return result;
}
