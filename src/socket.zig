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
        try socket.addString(&(i3_ipc ++ length ++ message_type));
    }

    fn nonZero(socket: Socket, length: u32) bool {
        return if (socket.message_type == .tree) true else length > 0;
    }

    pub fn add(socket: *Socket, comptime fmt: []const u8, args: anytype) !void {
        try socket.writer.interface.print(fmt, args);
    }

    pub fn addString(socket: *Socket, payload: []const u8) !void {
        const length: u32 = @intCast(payload.len);
        std.debug.assert(socket.nonZero(length));
        try socket.writer.interface.writeAll(payload);
    }

    pub fn lengthWrite(socket: *Socket) u32 {
        return @intCast(socket.writer.interface.end - 14);
    }

    pub fn commit(socket: *Socket) !void {
        std.debug.assert(std.mem.eql(u8, socket.writer.interface.buffer[0..6], "i3-ipc"));
        const length: u32 = socket.lengthWrite();
        std.debug.assert(socket.nonZero(length));
        @memcpy(socket.buffers.write[6..10], &@as([4]u8, @bitCast(length)));
        try socket.writer.interface.flush();
        try socket.writeHeader();
    }

    fn lengthRead(socket: *Socket) !u32 {
        var header: [14]u8 = undefined;
        try socket.reader.interface().readSliceAll(&header);
        return std.mem.readInt(u32, header[6..10], builtin.target.cpu.arch.endian());
    }

    pub fn discard(socket: *Socket) !void {
        _ = try socket.reader.interface().discard(.limited(try socket.lengthRead()));
    }

    pub fn parse(socket: *Socket, T: type) !T {
        const length = try socket.lengthRead();
        if (length > socket.buffers.read.len) return error.Overflow;
        defer socket.reader.interface().toss(length);
        const slice = try socket.reader.interface().peek(length);
        const options: std.json.ParseOptions =
            .{ .ignore_unknown_fields = true, .allocate = .alloc_if_needed };
        return std.json.parseFromSliceLeaky(T, main.fba, slice, options);
    }
};
