//! Connection to the Sway socket.

const std = @import("std");
const builtin = @import("builtin");

const main = @import("main.zig");

pub var subscribe: Socket = undefined;
pub var run: Socket = undefined;
pub var tree: Socket = undefined;

var subscribe_buffer: Arrays(64, 524_288) = undefined;
var run_buffer: Arrays(1024, 1024) = undefined;
var tree_buffer: Arrays(64, 524_288) = undefined;

pub fn init() !void {
    subscribe = try .init(.subscribe, slices(&subscribe_buffer));
    run = try .init(.run, slices(&run_buffer));
    tree = try .init(.tree, slices(&tree_buffer));
}

pub fn deinit() void {
    subscribe.deinit();
    run.deinit();
    tree.deinit();
}

fn Arrays(comptime write_len: usize, comptime read_len: usize) type {
    std.debug.assert(write_len > 0);
    std.debug.assert(read_len > 0);
    return struct { write: [write_len]u8, read: [read_len]u8 };
}

const Buffers = struct { write: []u8, read: []u8 };

fn slices(arrays: anytype) Buffers {
    return .{ .write = &arrays.write, .read = &arrays.read };
}

const MessageType = enum(u32) { run = 0, subscribe = 2, tree = 4 };

const Socket = struct {
    message_type: MessageType,
    buffers: Buffers,
    writer: std.net.Stream.Writer,
    reader: std.net.Stream.Reader,

    pub fn init(message_type: MessageType, buffers: Buffers) !Socket {
        const socket_path = std.posix.getenv("SWAYSOCK") orelse
            return error.SwaysockEnv;
        const stream = std.net.connectUnixSocket(socket_path) catch
            return error.SwaysockConnection;
        var socket: Socket = .{
            .message_type = message_type,
            .buffers = buffers,
            .writer = stream.writer(buffers.write),
            .reader = stream.reader(buffers.read),
        };
        try socket.writeHeader();
        return socket;
    }

    pub fn deinit(socket: Socket) void {
        std.net.Stream.Reader.getStream(&socket.reader).close();
    }

    fn writeHeader(socket: *Socket) !void {
        const i3_ipc: [6]u8 = .{ 'i', '3', '-', 'i', 'p', 'c' };
        const length: [4]u8 = .{ 0, 0, 0, 0 };
        const message_type: [4]u8 = @bitCast(@intFromEnum(socket.message_type));
        try socket.write(&(i3_ipc ++ length ++ message_type));
    }

    fn wroteHeader(socket: Socket) bool {
        return std.mem.eql(u8, socket.writer.interface.buffer[0..6], "i3-ipc");
    }

    fn nonZero(socket: Socket, length: u32) bool {
        return if (socket.message_type == .tree) true else length > 0;
    }

    pub inline fn write(socket: *Socket, payload: []const u8) !void {
        const length: u32 = @intCast(payload.len);
        std.debug.assert(socket.nonZero(length));
        try socket.writer.interface.writeAll(payload);
    }

    pub inline fn print(socket: *Socket, fmt: []const u8, args: anytype) !void {
        try socket.writer.interface.print(fmt, args);
    }

    pub fn commit(socket: *Socket) !void {
        std.debug.assert(socket.wroteHeader());
        const length: u32 = @intCast(socket.writer.interface.end - 14);
        std.debug.assert(socket.nonZero(length));
        const length_bytes: [4]u8 = @bitCast(length);
        @memcpy(socket.buffers.write[6..10], &length_bytes);
        try socket.writer.interface.flush();
        try socket.writeHeader();
    }

    fn payload_length(socket: *Socket) !u32 {
        var header: [14]u8 = undefined;
        try socket.reader.interface().readSliceAll(&header);
        const endian = builtin.target.cpu.arch.endian();
        const length = std.mem.readInt(u32, header[6..10], endian);
        std.debug.assert(length > 0);
        return length;
    }

    pub fn discard(socket: *Socket) !void {
        const limit: std.Io.Limit = .limited(try socket.payload_length());
        _ = try socket.reader.interface().discard(limit);
    }

    pub fn parse(socket: *Socket, T: type) !T {
        const length = try socket.payload_length();
        if (length > socket.buffers.read.len) {
            @branchHint(.cold);
            return error.Overflow;
        }
        const payload = try socket.reader.interface().peek(length);
        socket.reader.interface().toss(length);
        return std.json.parseFromSliceLeaky(T, main.fba, payload, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_if_needed,
        }) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => unreachable,
        };
    }
};
