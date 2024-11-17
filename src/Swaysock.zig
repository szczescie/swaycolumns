//! Connection to the Sway socket.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const connectUnixSocket = std.net.connectUnixSocket;
const getenv = std.posix.getenv;
const log = std.log;
const ParseOptions = std.json.ParseOptions;
const parseFromSliceLeaky = std.json.parseFromSliceLeaky;
const readInt = std.mem.readInt;
const Stream = std.net.Stream;
const builtin = @import("builtin");
const endian = builtin.target.cpu.arch.endian();

const main = @import("main.zig");
const fba = &main.fba;

sock: Stream,

pub fn connect() !@This() {
    const sock_path = getenv("SWAYSOCK") orelse {
        const err = error.NoEnv;
        log.warn("{}: failed to connect to socket; SWAYSOCK is not set", .{err});
        return err;
    };
    const sock = connectUnixSocket(sock_path) catch |err| {
        log.warn("{}: failed to connect to socket at path {s}", .{ err, sock_path });
        return err;
    };
    return .{ .sock = sock };
}

pub fn close(self: @This()) void {
    self.sock.close();
}

/// Non-exhaustive list of Sway IPC message types.
pub const MessageType = enum(u32) { command = 0, subscribe = 2, tree = 4 };

/// Cast as 4 bytes.
inline fn quadlet(num: u32) [4]u8 {
    return @bitCast(num);
}

pub fn write(self: @This(), comptime message_type: MessageType, payload: []const u8) !void {
    const header = "i3-ipc" ++ quadlet(@intCast(payload.len)) ++
        comptime quadlet(@intFromEnum(message_type));
    const message_len = 14 + payload.len;
    const message_buf = fba.alloc(u8, message_len) catch |err| {
        log.warn("{}: failed to allocate array of lenght {}", .{ err, message_len });
        return err;
    };
    @memcpy(message_buf[0..14], header);
    @memcpy(message_buf[14..message_len], payload);
    _ = self.sock.writeAll(message_buf) catch |err| {
        log.warn("{}: failed to write message {d}, \"{s}\"", .{ err, header[6..], payload });
        return err;
    };
}

pub fn read(self: @This()) ![]const u8 {
    const header_buf = fba.alloc(u8, 14) catch |err| {
        log.warn("{}: failed to allocate array of length 14", .{err});
        return err;
    };
    _ = self.sock.readAll(header_buf) catch |err| {
        log.warn("{}: failed to read header of length 14", .{err});
        return err;
    };
    const payload_len = readInt(u32, header_buf[6..10], endian);
    const payload_buf = fba.alloc(u8, payload_len) catch |err| {
        log.warn("{}: failed to allocate array of length {}", .{ err, payload_len });
        return err;
    };
    _ = self.sock.readAll(payload_buf) catch |err| {
        log.warn("{}: failed to read payload of length {}", .{ err, payload_len });
        return err;
    };
    return payload_buf;
}

pub const json_options: ParseOptions = .{ .ignore_unknown_fields = true };

pub fn readParse(self: @This(), comptime T: type) !T {
    const string = try self.read();
    const result = parseFromSliceLeaky(T, fba.*, string, json_options) catch |err| {
        log.warn("{}: failed to parse string \"{s}\"", .{ err, string });
        return err;
    };
    return result;
}
