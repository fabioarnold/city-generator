const builtin = @import("builtin");
const wasm = @import("web/wasm.zig");
const sdl = @import("sdl3");

pub var mx: f32 = 0;
pub var my: f32 = 0;
pub var mx_prev: f32 = 0;
pub var my_prev: f32 = 0;
pub var framedown: bool = false; // Transitioned down within this frame.
pub var frameup: bool = false; // Transitioned up within this frame.
pub var down: bool = false;

pub fn key_down(key: KeyCode) bool {
    if (builtin.cpu.arch.isWasm()) {
        return wasm.key_down(key);
    } else {
        const key_state = sdl.keyboard.getState();
        return key_state[@intFromEnum(key.sdl_scancode())];
    }
}

pub fn end_frame() void {
    framedown = false;
    frameup = false;
    mx_prev = mx;
    my_prev = my;
}

pub const KeyCode = enum(u32) {
    backspace = 8,
    tab = 9,
    enter = 13,
    shift = 16,
    ctrl = 17,
    alt = 18,
    pause = 19,
    caps_lock = 20,
    escape = 27,
    space = 32,
    pageup = 33,
    pagedown = 34,
    end = 35,
    home = 36,
    left = 37,
    up = 38,
    right = 39,
    down = 40,
    insert = 45,
    delete = 46,
    zero = 48,
    one = 49,
    two = 50,
    three = 51,
    four = 52,
    five = 53,
    six = 54,
    seven = 55,
    eight = 56,
    nine = 57,
    a = 65,
    b = 66,
    c = 67,
    d = 68,
    e = 69,
    f = 70,
    g = 71,
    h = 72,
    i = 73,
    j = 74,
    k = 75,
    l = 76,
    m = 77,
    n = 78,
    o = 79,
    p = 80,
    q = 81,
    r = 82,
    s = 83,
    t = 84,
    u = 85,
    v = 86,
    w = 87,
    x = 88,
    y = 89,
    z = 90,
    meta_left = 91,
    meta_right = 92,
    select = 93,
    np0 = 96,
    np1 = 97,
    np2 = 98,
    np3 = 99,
    np4 = 100,
    np5 = 101,
    np6 = 102,
    np7 = 103,
    np8 = 104,
    np9 = 105,
    npmultiply = 106,
    npadd = 107,
    npsubtract = 109,
    npdecimal = 110,
    npdivide = 111,
    f1 = 112,
    f2 = 113,
    f3 = 114,
    f4 = 115,
    f5 = 116,
    f6 = 117,
    f7 = 118,
    f8 = 119,
    f9 = 120,
    f10 = 121,
    f11 = 122,
    f12 = 123,
    num_lock = 144,
    scroll_lock = 145,
    semicolon = 186,
    equal_sign = 187,
    comma = 188,
    minus = 189,
    period = 190,
    slash = 191,
    backquote = 192,
    bracket_left = 219,
    backslash = 220,
    bracket_right = 221,
    quote = 22,
    _,

    pub fn is_modifier(key: KeyCode) bool {
        return switch (key) {
            .shift, .alt, .ctrl, .meta_left, .meta_right => true,
            else => false,
        };
    }

    pub fn in_range(self: KeyCode, minimum: KeyCode, maximum: KeyCode) bool {
        return @intFromEnum(self) >= @intFromEnum(minimum) and @intFromEnum(self) <= @intFromEnum(maximum);
    }

    fn sdl_scancode(key: KeyCode) sdl.Scancode {
        return switch (key) {
            .w => .w,
            .a => .a,
            .s => .s,
            .d => .d,
            .e => .e,
            .q => .q,
            .right => .right,
            .left => .left,
            .up => .up,
            .down => .down,
            else => @panic("not implemented"),
        };
    }
};
