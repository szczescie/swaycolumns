//! Connection to the Sway socket.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const ConnectError = std.posix.ConnectError;
const connectUnixSocket = std.net.connectUnixSocket;
const getenv = std.posix.getenv;
const log = std.log;
const ParseError = std.json.ParseError;
const parseFromSliceLeaky = std.json.parseFromSliceLeaky;
const ReadError = std.posix.ReadError;
const readInt = std.mem.readInt;
const Scanner = std.json.Scanner;
const SocketError = std.posix.SocketError;
const Stream = std.net.Stream;
const WriteError = std.posix.WriteError;
const builtin = @import("builtin");
const endian = builtin.target.cpu.arch.endian();

const main = @import("main.zig");
const fba = &main.fba;

sock: Stream,

pub const SockConnectError =
    error{ NoEnv, NameTooLong } ||
    SocketError ||
    ConnectError;

pub fn connect() SockConnectError!@This() {
    const sock_path = getenv("SWAYSOCK") orelse {
        log.warn(
            "{}: SWAYSOCK not set",
            .{SockConnectError.NoEnv},
        );
        return SockConnectError.NoEnv;
    };
    const sock = connectUnixSocket(sock_path) catch |err| {
        log.warn(
            "{}: unable to connect to socket at path {s}",
            .{ err, sock_path },
        );
        return err;
    };
    return .{ .sock = sock };
}

pub fn close(self: @This()) void {
    self.sock.close();
}

/// Non-exhaustive list of Sway IPC message types.
pub const MessageType = enum(u32) {
    command = 0,
    subscribe = 2,
    tree = 4,
};

/// Cast as 4 bytes.
inline fn quadlet(num: u32) [4]u8 {
    return @bitCast(num);
}

pub const SockWriteError = Allocator.Error || WriteError;

pub fn write(
    self: @This(),
    comptime message_type: MessageType,
    payload: []const u8,
) SockWriteError!void {
    const header =
        "i3-ipc" ++
        quadlet(@intCast(payload.len)) ++
        comptime quadlet(@intFromEnum(message_type));
    const message_len = 14 + payload.len;
    const message_buf = fba.alloc(u8, message_len) catch |err| {
        log.warn(
            "{}: failed allocating array of lenght {}",
            .{ err, message_len },
        );
        return err;
    };
    @memcpy(message_buf[0..14], header);
    @memcpy(message_buf[14..message_len], payload);
    _ = self.sock.writeAll(message_buf) catch |err| {
        log.warn(
            "{}: failed writing message {d}, \"{s}\"",
            .{ err, header[6..], payload },
        );
        return err;
    };
}

pub const SockReadError = Allocator.Error || ReadError;

pub fn read(self: @This()) SockReadError![]const u8 {
    const header_buf = fba.alloc(u8, 14) catch |err| {
        log.warn(
            "{}: failed allocating array of length 14",
            .{err},
        );
        return err;
    };
    _ = self.sock.readAll(header_buf) catch |err| {
        log.warn(
            "{}: failed reading header of length 14",
            .{err},
        );
        return err;
    };
    const payload_len = readInt(
        u32,
        header_buf[6..10],
        endian,
    );
    const payload_buf = fba.alloc(u8, payload_len) catch |err| {
        log.warn(
            "{}: failed allocating array of length {}",
            .{ err, payload_len },
        );
        return err;
    };
    _ = self.sock.readAll(payload_buf) catch |err| {
        log.warn(
            "{}: failed reading payload of length {}",
            .{ err, payload_len },
        );
        return err;
    };
    return payload_buf;
}

pub const SockParseError = SockReadError || ParseError(Scanner);

pub fn readParse(self: @This(), comptime T: type) SockParseError!T {
    const string = try self.read();
    const result = parseFromSliceLeaky(
        T,
        fba.*,
        string,
        .{ .ignore_unknown_fields = true },
    ) catch |err| {
        log.warn(
            "{}: parsing failed for string \"{s}\"",
            .{ err, string },
        );
        return err;
    };
    return result;
}
