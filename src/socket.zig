//! Connection to the Sway socket.

const std = @import("std");
const builtin = @import("builtin");

const main = @import("main.zig");

/// Establish a connection with the Sway socket.
pub fn connect() std.net.Stream {
    const socket_path = std.posix.getenv("SWAYSOCK") orelse
        std.process.fatal("SWAYSOCK is not set\n", .{});
    const socket = std.net.connectUnixSocket(socket_path) catch |err|
        std.process.fatal("unable to connect to socket ({})", .{err});
    return socket;
}

/// Non-exhaustive list of Sway IPC message types.
pub const MessageType = enum(u32) { command = 0, subscribe = 2, tree = 4 };

/// Cast as 4 bytes.
inline fn ipcHeader(length: usize, message_type: MessageType) [14]u8 {
    return .{ 'i', '3', '-', 'i', 'p', 'c' } ++
        @as([4]u8, @bitCast(@as(u32, @intCast(length)))) ++
        @as([4]u8, @bitCast(@intFromEnum(message_type)));
}

/// Send a message to the Sway socket.
pub fn write(
    writer: *std.Io.Writer,
    message_type: MessageType,
    payload: []const u8,
) !void {
    try writer.writeAll(&ipcHeader(payload.len, message_type));
    try writer.writeAll(payload);
}

/// Read a message from the Sway socket.
pub fn read(reader: *std.Io.Reader) ![]const u8 {
    const header = try reader.readAlloc(main.fba, 14);
    const endian = builtin.target.cpu.arch.endian();
    const payload_len = std.mem.readInt(u32, header[6..10], endian);
    return reader.readAlloc(main.fba, payload_len);
}

/// Read and parse a message from the Sway socket.
pub fn readParse(reader: *std.Io.Reader, comptime T: type) !T {
    return std.json.parseFromSliceLeaky(T, main.fba, try read(reader), .{
        .ignore_unknown_fields = true,
    });
}
