const std = @import("std");
const logger = std.log.scoped(.wasm);
const input = @import("../input.zig");
pub const KeyCode = input.KeyCode;

pub const performance = struct {
    pub fn now() f64 {
        return wasm_performance_now();
    }
};

pub fn set_cursor(name: []const u8) void {
    wasm_set_cursor(name.ptr, name.len);
}

pub fn open_link(url: []const u8) void {
    wasm_open_link(url.ptr, url.len);
}

pub fn key_down(key: KeyCode) bool {
    return wasm_key_down(@intFromEnum(key));
}

pub fn button_down(gamepad_index: usize, button_index: usize) bool {
    return wasm_button_down(gamepad_index, button_index);
}

pub fn stick_x(gamepad_index: usize, stick_index: usize) f32 {
    return wasm_stick_x(gamepad_index, stick_index);
}

pub fn stick_y(gamepad_index: usize, stick_index: usize) f32 {
    return wasm_stick_y(gamepad_index, stick_index);
}

fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    _ = data;
    _ = splat;
    const string = w.buffered();
    wasm_log_write(string.ptr, string.len);
    return w.consumeAll();
}

/// Overwrite default log handler.
pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.Writer = .{
        .buffer = &buffer,
        .vtable = &.{
            .drain = &drain,
        },
    };

    const prefix = "[" ++ @tagName(level) ++ "] " ++ "(" ++ @tagName(scope) ++ "): ";
    writer.print(prefix ++ format ++ "\n", args) catch return;
    writer.flush() catch return;

    wasm_log_flush();
}

extern fn wasm_performance_now() callconv(.c) f64;
extern fn wasm_log_write(ptr: [*]const u8, len: usize) callconv(.c) void;
extern fn wasm_log_flush() callconv(.c) void;

extern fn wasm_set_cursor(ptr: [*]const u8, len: usize) callconv(.c) void;
extern fn wasm_open_link(ptr: [*]const u8, len: usize) callconv(.c) void;

extern fn wasm_key_down(key: c_uint) callconv(.c) bool;
extern fn wasm_button_down(gamepad_index: c_uint, button_index: c_uint) callconv(.c) bool;
extern fn wasm_stick_x(gamepad_index: c_uint, stick_index: c_uint) callconv(.c) f32;
extern fn wasm_stick_y(gamepad_index: c_uint, stick_index: c_uint) callconv(.c) f32;

export fn on_mouse_move(x: f32, y: f32) void {
    input.mx = x;
    input.my = y;
}

export fn on_mouse_down(button: u32, x: f32, y: f32) void {
    input.mx = x;
    input.my = y;
    if (button == 0) input.framedown, input.down = .{ true, true };
}

export fn on_mouse_up(button: u32, x: f32, y: f32) void {
    input.mx = x;
    input.my = y;
    if (button == 0) input.frameup, input.down = .{ true, false };
}

export fn on_key_down(key: KeyCode) void {
    _ = key;
}
