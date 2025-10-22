//! Connection to the Sway socket.

const std = @import("std");
const builtin = @import("builtin");

pub const MessageType = enum(u32) { run = 0, subscribe = 2, tree = 4 };

const Socket = struct {
    message_type: MessageType,
    write_buffer: []u8 = undefined,
    read_buffer: []u8 = undefined,
    writer: std.net.Stream.Writer,
    reader: std.net.Stream.Reader,

    fn connect() !std.net.Stream {
        const socket_path = std.posix.getenv("SWAYSOCK") orelse
            return error.SwaysockEnv;
        return std.net.connectUnixSocket(socket_path) catch
            return error.SwaysockConnection;
    }

    fn writeHeader(socket: *@This()) !void {
        const header: [14]u8 = .{ 'i', '3', '-', 'i', 'p', 'c', 0, 0, 0, 0 } ++
            @as([4]u8, @bitCast(@intFromEnum(socket.message_type)));
        try socket.write(&header);
    }

    pub fn init(
        message_type: MessageType,
        write_buffer: []u8,
        read_buffer: []u8,
    ) !@This() {
        std.debug.assert(write_buffer.len > 0);
        std.debug.assert(read_buffer.len > 0);
        const stream = try connect();
        var socket: @This() = .{
            .message_type = message_type,
            .write_buffer = write_buffer,
            .read_buffer = read_buffer,
            .writer = stream.writer(write_buffer),
            .reader = stream.reader(read_buffer),
        };
        try socket.writeHeader();
        return socket;
    }

    pub fn deinit(socket: @This()) void {
        std.net.Stream.Reader.getStream(&socket.reader).close();
    }

    pub fn write(socket: *@This(), payload: []const u8) !void {
        try socket.writer.interface.writeAll(payload);
    }

    pub fn print(
        socket: *@This(),
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        try socket.writer.interface.print(fmt, args);
    }

    pub fn commit(socket: *@This()) !void {
        const payload_len = socket.writer.interface.end - 14;
        const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(payload_len)));
        @memcpy(socket.writer.interface.buffer[6..10], &len_bytes);
        try socket.writer.interface.flush();
        try socket.writeHeader();
    }

    fn len(socket: *@This()) !u32 {
        var header: [14]u8 = undefined;
        try socket.reader.interface().readSliceAll(&header);
        const endian = builtin.target.cpu.arch.endian();
        return std.mem.readInt(u32, header[6..10], endian);
    }

    pub fn discard(socket: *@This()) !void {
        _ = try socket.reader.interface().discard(.limited(try socket.len()));
    }

    pub fn parse(socket: *@This(), comptime T: type) !T {
        var fba_buf: [64 * 1024]u8 = undefined;
        var fba_state = std.heap.FixedBufferAllocator.init(&fba_buf);
        const fba = fba_state.allocator();
        const length = try socket.len();
        const payload = try socket.reader.interface().peek(length);
        defer socket.reader.interface().toss(length);
        return std.json.parseFromSliceLeaky(T, fba, payload, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_if_needed,
        });
    }
};

var subscribe_write: [64]u8 = undefined;
var subscribe_read: [512 * 1024]u8 = undefined;
var run_write: [1024]u8 = undefined;
var run_read: [1024]u8 = undefined;
var tree_write: [64]u8 = undefined;
var tree_read: [512 * 1024]u8 = undefined;

pub var subscribe: Socket = undefined;
pub var run: Socket = undefined;
pub var tree: Socket = undefined;

pub fn init() !void {
    subscribe = try .init(.subscribe, &subscribe_write, &subscribe_read);
    run = try Socket.init(.run, &run_write, &run_read);
    tree = try Socket.init(.tree, &tree_write, &tree_read);
}

pub fn deinit() void {
    subscribe.deinit();
    run.deinit();
    tree.deinit();
}
