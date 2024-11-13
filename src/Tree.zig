const std = @import("std");
const debug = std.debug;
const log = std.log;
const mem = std.mem;

const Socket = @import("Socket.zig");

json_str: []const u8,

pub fn init(socket: Socket) Socket.ErrorWriteReadRaw!@This() {
    var tree: @This() = undefined;
    tree.json_str = try socket.writeReadRaw(.tree, "");
    log.debug("got tree of length: {d}", .{tree.json_str.len});
    debug.assert(tree.isCorrect());
    return tree;
}

/// Quickly ensure that the given string is a JSON-encoded Sway layout tree.
pub inline fn isCorrect(self: @This()) bool {
    return self.json_str.len >= 1000 and
        self.json_str[0] == '{' and
        self.json_str[self.json_str.len - 1] == '}';
}

/// Extract the focused workspace.
pub fn isolateFocused(self: @This()) ?[]const u8 {
    debug.assert(self.isCorrect());
    const focused_true = mem.indexOfPosLinear(
        u8,
        self.json_str,
        2000,
        "d\": t",
    ) orelse {
        log.warn("\"focused\": true not found in tree", .{});
        return null;
    };
    const type_workspace = mem.lastIndexOfLinear(
        u8,
        self.json_str[0 .. focused_true - 400],
        "pe\": \"w",
    ) orelse {
        log.warn("\"type\": \"workspace\" not found in tree", .{});
        return null;
    };
    const brace_first = mem.lastIndexOfScalar(
        u8,
        self.json_str[0 .. type_workspace - 10],
        '{',
    ) orelse {
        log.warn("beginning brace not found in tree", .{});
        return null;
    };
    const representation = mem.indexOfPosLinear(
        u8,
        self.json_str,
        focused_true + 800,
        ", \"rep",
    ) orelse {
        log.warn("\"representation\" not found in tree", .{});
        return null;
    };
    const brace_last = mem.indexOfScalarPos(
        u8,
        self.json_str,
        representation + 15,
        '}',
    ) orelse {
        log.warn("ending brace not found in tree", .{});
        return null;
    };
    return self.json_str[brace_first .. brace_last + 1];
}

/// Extract all workspaces other than the scratchpad.
pub fn isolateAll(self: @This()) ?[]const u8 {
    debug.assert(self.isCorrect());
    var type_workspace = mem.indexOfPosLinear(
        u8,
        self.json_str,
        800,
        "pe\": \"w",
    ) orelse {
        log.warn("\"type\": \"workspace\" of scratchpad not found in tree", .{});
        return null;
    };
    type_workspace = mem.indexOfPosLinear(
        u8,
        self.json_str,
        type_workspace + 1000,
        "pe\": \"w",
    ) orelse {
        log.warn("\"type\": \"workspace\" of first workspace not found in tree", .{});
        return null;
    };
    const brace_first = mem.lastIndexOfScalar(
        u8,
        self.json_str[0 .. type_workspace - 10],
        '{',
    ) orelse {
        log.warn("beginning brace of first workspace not found in tree", .{});
        return null;
    };
    const representation = mem.lastIndexOfLinear(
        u8,
        self.json_str[0 .. self.json_str.len - 500],
        ", \"rep",
    ) orelse {
        log.warn("\"representation\" of last workspace not found in tree", .{});
        return null;
    };
    const brace_last = mem.indexOfScalarPos(
        u8,
        self.json_str,
        representation + 15,
        '}',
    ) orelse {
        log.warn("ending brace of last workspace not found in tree", .{});
        return null;
    };
    return self.json_str[brace_first - 2 .. brace_last + 3];
}
