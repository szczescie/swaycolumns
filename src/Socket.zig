//! Connection to the Sway socket.

const std = @import("std");
const debug = std.debug;
const heap = std.heap;
const json = std.json;
const log = std.log;
const net = std.net;
const posix = std.posix;

sock: net.Stream,
buf: []u8,

pub const ErrorSwaysock =
    error{ NoEnv, NameTooLong } ||
    posix.SocketError ||
    posix.ConnectError;

/// Connect to the socket.
pub fn init(buf: []u8) ErrorSwaysock!@This() {
    debug.assert(buf.len >= 500);
    const sock_path = posix.getenv("SWAYSOCK") orelse {
        log.err("SWAYSOCK not set", .{});
        return ErrorSwaysock.NoEnv;
    };
    const sock = net.connectUnixSocket(sock_path) catch |err| switch (err) {
        error.NameTooLong => unreachable,
        else => {
            log.err("unable to connect to socket", .{});
            return err;
        },
    };
    return .{ .sock = sock, .buf = buf };
}

/// Disconnect from the socket.
pub fn deinit(self: @This()) void {
    self.sock.close();
}

/// Cast as 4 bytes.
fn quadlet(num: u32) [4]u8 {
    return @bitCast(num);
}

/// Non-exhaustive list of Sway IPC message types.
const MessageType = enum(u32) {
    command = 0,
    subscribe = 2,
    tree = 4,
};

/// Send a Sway IPC message.
pub fn write(
    self: @This(),
    comptime message_type: MessageType,
    string: []const u8,
) posix.WriteError!void {
    const head =
        "i3-ipc" ++
        quadlet(@intCast(string.len)) ++
        comptime quadlet(@intFromEnum(message_type));
    @memcpy(self.buf[0..head.len], head);
    @memcpy(self.buf[head.len .. head.len + string.len], string);

    const buf = self.buf[0 .. head.len + string.len];
    _ = self.sock.write(buf) catch |err| switch (err) {
        posix.WriteError.FileTooBig => unreachable,
        else => {
            log.err("unable to write to socket", .{});
            return err;
        },
    };
}

pub const ErrorReadRaw = error{MessageTooBig} || posix.ReadError;

/// Read a single Sway IPC message without parsing.
pub fn readRaw(self: @This()) ErrorReadRaw![]const u8 {
    _ = try self.sock.read(self.buf[0..14]);
    const len: u32 = @bitCast(self.buf[6..10].*);
    if (len > self.buf.len) {
        log.err(
            "message of length {d} too big for buffer or length {d}",
            .{ len, self.buf.len },
        );
        return ErrorRead.MessageTooBig;
    }
    _ = try self.sock.read(self.buf[0..len]);
    return self.buf[0..len];
}

pub const ErrorRead = ErrorReadRaw || json.ParseError(json.Scanner);

/// Read a single Sway IPC message with parsing.
pub fn read(self: @This(), comptime T: type) ErrorRead!T {
    const string = try self.readRaw();
    var fba = heap.FixedBufferAllocator.init(self.buf[string.len..]);
    return json.parseFromSliceLeaky(
        T,
        fba.allocator(),
        string,
        .{ .ignore_unknown_fields = true },
    );
}

pub const ErrorWriteReadRaw = ErrorReadRaw || posix.WriteError;

/// Send a Sway IPC message and return the unparsed reply.
pub fn writeReadRaw(
    self: @This(),
    comptime message_type: MessageType,
    string: []const u8,
) ErrorWriteReadRaw![]const u8 {
    try self.write(message_type, string);
    return self.readRaw();
}

pub const ErrorWriteRead = ErrorRead || posix.WriteError;

/// Send a Sway IPC message and return the parsed reply.
pub fn writeRead(
    self: @This(),
    comptime T: type,
    comptime message_type: MessageType,
    string: []const u8,
) ErrorWriteRead!T {
    try self.write(message_type, string);
    return self.read(T);
}
