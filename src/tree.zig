const std = @import("std");
const assert = std.debug.assert;
const indexOfPosLinear = std.mem.indexOfPosLinear;
const indexOfScalarPos = std.mem.indexOfScalarPos;
const lastIndexOfLinear = std.mem.lastIndexOfLinear;
const lastIndexOfScalar = std.mem.lastIndexOfScalar;
const log = std.log;
const ParseError = std.json.ParseError;
const parseFromSliceLeaky = std.json.parseFromSliceLeaky;
const Scanner = std.json.Scanner;

const Columns = @import("columns.zig");
const interact = &Columns.interact_sock;
const main = @import("main.zig");
const fba = &main.fba;
const Swaysock = @import("Swaysock.zig");
const SockReadError = Swaysock.SockReadError;
const SockWriteError = Swaysock.SockWriteError;

/// Quickly ensure that the given string is a JSON-encoded Sway layout tree.
inline fn isCorrect(tree_str: []const u8) bool {
    return tree_str.len >= 1000 and
        tree_str[0] == '{' and
        tree_str[tree_str.len - 1] == '}';
}

const TreeGetError = SockReadError || SockWriteError;

fn get() TreeGetError![]const u8 {
    try interact.write(.tree, "");
    const tree_str = try interact.read();
    log.debug("got tree of length: {d}", .{tree_str.len});
    assert(isCorrect(tree_str));
    return tree_str;
}

const TreeIsolateError = error{notFound};

/// Extract all workspaces other than the scratchpad.
fn isolateAll(tree_str: []const u8) TreeIsolateError![]const u8 {
    var type_workspace = indexOfPosLinear(
        u8,
        tree_str,
        800,
        "pe\": \"w",
    ) orelse {
        log.warn(
            "\"type\": \"workspace\" of scratchpad not found in tree",
            .{},
        );
        return TreeIsolateError.notFound;
    };
    type_workspace = indexOfPosLinear(
        u8,
        tree_str,
        type_workspace + 1000,
        "pe\": \"w",
    ) orelse {
        log.warn(
            "\"type\": \"workspace\" of first workspace " ++
                "not found in tree; last index was {}",
            .{type_workspace},
        );
        return TreeIsolateError.notFound;
    };
    const brace_first = lastIndexOfScalar(
        u8,
        tree_str[0 .. type_workspace - 10],
        '{',
    ) orelse {
        log.warn(
            "beginning brace of first workspace " ++
                "not found in tree; last index was {}",
            .{type_workspace},
        );
        return TreeIsolateError.notFound;
    };
    const representation = lastIndexOfLinear(
        u8,
        tree_str[0 .. tree_str.len - 500],
        ", \"rep",
    ) orelse {
        log.warn(
            "\"representation\" of last workspace " ++
                "not found in tree; last index was {}",
            .{brace_first},
        );
        return TreeIsolateError.notFound;
    };
    const brace_last = indexOfScalarPos(
        u8,
        tree_str,
        representation + 15,
        '}',
    ) orelse {
        log.warn(
            "ending brace of last workspace " ++
                "not found in tree; last index was {}",
            .{representation},
        );
        return TreeIsolateError.notFound;
    };
    return tree_str[brace_first - 2 .. brace_last + 3];
}

/// Extract the focused workspace.
fn isolateFocused(tree_str: []const u8) TreeIsolateError![]const u8 {
    const focused_true = indexOfPosLinear(
        u8,
        tree_str,
        2000,
        "d\": t",
    ) orelse {
        log.warn("\"focused\": true not found in tree", .{});
        return TreeIsolateError.notFound;
    };
    const type_workspace = lastIndexOfLinear(
        u8,
        tree_str[0 .. focused_true - 400],
        "pe\": \"w",
    ) orelse {
        log.warn(
            "\"type\": \"workspace\" not found in tree; last index was {}",
            .{focused_true},
        );
        return TreeIsolateError.notFound;
    };
    const brace_first = lastIndexOfScalar(
        u8,
        tree_str[0 .. type_workspace - 10],
        '{',
    ) orelse {
        log.warn(
            "beginning brace not found in tree; last index was {}",
            .{type_workspace},
        );
        return TreeIsolateError.notFound;
    };
    const representation = indexOfPosLinear(
        u8,
        tree_str,
        focused_true + 800,
        ", \"rep",
    ) orelse {
        log.warn(
            "\"representation\" not found in tree; last index was {}",
            .{brace_first},
        );
        return TreeIsolateError.notFound;
    };
    const brace_last = indexOfScalarPos(
        u8,
        tree_str,
        representation + 15,
        '}',
    ) orelse {
        log.warn(
            "ending brace not found in tree; last index was {}",
            .{representation},
        );
        return TreeIsolateError.notFound;
    };
    return tree_str[brace_first .. brace_last + 1];
}

pub const GetTarget = enum { all, focused };
pub const TreeParseError =
    TreeGetError ||
    TreeIsolateError ||
    ParseError(Scanner);
/// Sway layout tree node.
pub const Node = struct {
    id: u32,
    layout: []const u8,
    focused: bool,
    nodes: []@This(),
};

pub fn getParsed(
    comptime target: GetTarget,
) TreeParseError!if (target == .all) []Node else Node {
    const isolate_fn = if (target == .all) isolateAll else isolateFocused;
    const workspace_str = try isolate_fn(try get());
    const result = parseFromSliceLeaky(
        if (target == .all) []Node else Node,
        fba.*,
        workspace_str,
        .{ .ignore_unknown_fields = true },
    ) catch |err| {
        log.warn(
            "{}: parsing failed for string \"{s}\"",
            .{ err, workspace_str },
        );
        return err;
    };
    return result;
}
