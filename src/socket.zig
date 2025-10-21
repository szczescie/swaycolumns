//! Connection to the Sway socket.

const std = @import("std");
const builtin = @import("builtin");

const main = @import("main.zig");

const endian = builtin.target.cpu.arch.endian();

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
    writer: *std.net.Stream.Writer,
    message_type: MessageType,
    payload: []const u8,
) !void {
    try writer.interface.writeAll(&ipcHeader(payload.len, message_type));
    try writer.interface.writeAll(payload);
}

fn len(reader: *std.net.Stream.Reader) !u32 {
    const header = try reader.interface().readAlloc(main.fba, 14);
    return std.mem.readInt(u32, header[6..10], endian);
}

/// Read a message from the Sway socket.
pub fn read(reader: *std.net.Stream.Reader) ![]const u8 {
    return reader.interface().readAlloc(main.fba, try len(reader));
}

pub fn discard(reader: *std.net.Stream.Reader) !void {
    _ = try reader.interface().discard(.limited(try len(reader)));
}
