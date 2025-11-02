//! Connection to the Sway socket.

const std = @import("std");
const builtin = @import("builtin");

const main = @import("main.zig");

pub var subscribe: Socket = undefined;
pub var tree: Socket = undefined;
pub var run: Socket = undefined;

var buffer_subscribe: struct { [50]u8, [500_000]u8 } = undefined;
var buffer_tree: struct { [50]u8, [500_000]u8 } = undefined;
var buffer_run: struct { [1000]u8, [1000]u8 } = undefined;

pub fn init() !void {
    subscribe = try .init(.subscribe, &buffer_subscribe.@"0", &buffer_subscribe.@"1");
    run = try .init(.run, &buffer_run.@"0", &buffer_run.@"1");
    tree = try .init(.tree, &buffer_tree.@"0", &buffer_tree.@"1");
}

pub fn deinit() void {
    subscribe.deinit();
    tree.deinit();
    run.deinit();
}

const MessageType = enum(u32) { run = 0, subscribe = 2, tree = 4 };

const Socket = struct {
    message_type: MessageType,
    buffer_write: []u8,
    buffer_read: []u8,
    writer: std.net.Stream.Writer,
    reader: std.net.Stream.Reader,

    pub fn init(message_type: MessageType, buffer_write: []u8, buffer_read: []u8) !Socket {
        const socket_path = std.posix.getenv("SWAYSOCK") orelse
            return error.SwaysockEnv;
        const stream = std.net.connectUnixSocket(socket_path) catch
            return error.SwaysockConnection;
        var socket: Socket = .{
            .message_type = message_type,
            .buffer_write = buffer_write,
            .buffer_read = buffer_read,
            .writer = stream.writer(buffer_write),
            .reader = stream.reader(buffer_read),
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
        @memcpy(socket.buffer_write[6..10], &@as([4]u8, @bitCast(length)));
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
        if (length > socket.buffer_read.len) return error.Overflow;
        defer socket.reader.interface().toss(length);
        const slice = try socket.reader.interface().peek(length);
        const options: std.json.ParseOptions =
            .{ .ignore_unknown_fields = true, .allocate = .alloc_if_needed };
        return std.json.parseFromSliceLeaky(T, main.fba, slice, options);
    }
};
