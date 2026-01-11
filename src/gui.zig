const std = @import("std");
const log = std.log.scoped(.gui);
const builtin = @import("builtin");
const wasm = @import("web/wasm.zig");
const is_wasm = builtin.cpu.arch.isWasm();
const la = @import("linear_algebra.zig");
const time = @import("time.zig");
const math = @import("math.zig");
const gfx = @import("gfx.zig");
const input = @import("input.zig");
const layout = @import("layout.zig");

/// Element that has current text input focus.
var input_focus: ?*const anyopaque = null;

/// Selection drag start.
var input_select_start: ?usize = null;

export fn on_gui_focus(id: ?*const anyopaque) callconv(.c) void {
    input_focus = id;
}

export fn on_gui_cancel_select() callconv(.c) void {
    input_select_start = null;
}

pub fn begin_frame() void {
    if (is_wasm) wasm.gui_begin_frame();
    if (input.framedown) input_focus = null;
}

pub const TextOptions = struct {
    align_x: layout.Alignment = .start,
    align_y: layout.Alignment = .start,
    font_size: f32 = 16,
};

pub fn text(string: []const u8, rect: gfx.Rect, options: TextOptions) void {
    if (is_wasm) {
        const screen = gfx.point_to_screen(.{ rect.x, rect.y });
        wasm.gui_text(string.ptr, string.len, screen[0], screen[1], rect.w, rect.h);
    }

    gfx.set_font_size(options.font_size);
    const text_width = gfx.get_text_width(string);
    const text_height = gfx.get_text_height();
    const x: f32 = rect.x + options.align_x.factor() * (rect.w - text_width);
    const y: f32 = rect.y + options.align_y.factor() * (rect.h - text_height);
    gfx.draw_text(string, x, y);
}

pub const InputTextOptions = struct {
    font_size: f32 = 20,
    placeholder: []const u8 = "",
    enabled: bool = true,
};

const InputTextState = struct {
    text_size: usize, // In bytes.
    selection_start: usize, // In codepoints.
    selection_end: usize,
};

pub fn input_text(buffer: []u8, rect: gfx.Rect, options: InputTextOptions) []const u8 {
    var state: InputTextState = .{
        .text_size = 0,
        .selection_start = 0,
        .selection_end = 0,
    };
    const screen = gfx.point_to_screen(.{ rect.x, rect.y });
    if (is_wasm) {
        wasm.gui_input_text(buffer.ptr, buffer.len, &state, screen[0], screen[1], rect.w, rect.h);
    }
    const id: *const anyopaque = buffer.ptr;

    const string = buffer[0..state.text_size];
    const view = std.unicode.Utf8View.initUnchecked(string);
    var it = view.iterator();

    const mouse = gfx.point_from_screen(.{ input.mx, input.my });
    const hover = options.enabled and gfx.point_in_rect(mouse, rect);
    if (hover) {
        if (input.framedown) {
            if (input_focus != id) {
                input_focus = id;
                if (is_wasm) wasm.gui_focus(input_focus);
            }
        }
        gfx.set_font_size(options.font_size);
        const index = gfx.get_text_closest_index(string, mouse[0] - rect.x - 2);
        if (is_wasm) {
            if (input.click_triple) {
                wasm.gui_input_text_select(id, 0, string.len);
            } else if (input.click_double) {
                wasm.gui_input_text_select_word(id, index);
                // Update the text selection state
                wasm.gui_input_text(buffer.ptr, buffer.len, &state, screen[0], screen[1], rect.w, rect.h);
            } else if (input.framedown) {
                if (input_focus != id) {
                    input_focus = id;
                    wasm.gui_focus(input_focus);
                }
                wasm.gui_input_text_select(id, index, index);
                state.selection_start = index;
                state.selection_end = index;
                input_select_start = index;
            }
        }
    }
    const has_focus = input_focus == id;

    gfx.set_color(.{ 1, 1, 1, if (has_focus) 1 else 0.5 });
    gfx.stroke_rect(rect) catch unreachable;

    gfx.set_font_size(options.font_size);
    const text_h = gfx.get_text_height();
    if (state.text_size == 0 and !has_focus) {
        gfx.set_color(.{ 1, 1, 1, 0.5 });
        gfx.draw_text(options.placeholder, rect.x + 2, rect.y + 0.5 * (rect.h - text_h));
    }

    gfx.set_color(.{ 1, 1, 1, 1 });
    gfx.draw_text(string, rect.x + 2, rect.y + 0.5 * (rect.h - text_h));

    if (has_focus) {
        const selection_prefix = it.peek(state.selection_start);
        const prefix_w = gfx.get_text_width(selection_prefix);
        const selection_end = it.peek(state.selection_end);
        if (selection_end.len > selection_prefix.len) {
            const selection_w = gfx.get_text_width(selection_end) - prefix_w;
            gfx.set_color(.{ 0.2, 0.6, 1, 0.4 });
            gfx.fill_rect(.{ .x = rect.x + 2 + prefix_w, .y = rect.y + 0.5 * (rect.h - text_h), .w = selection_w, .h = text_h });
        } else {
            gfx.set_color(@splat(1));
            gfx.fill_rect(.{ .x = rect.x + 1.5 + prefix_w, .y = rect.y + 0.5 * (rect.h - text_h), .w = 1, .h = text_h });
        }
    }

    if (hover) {
        input.set_cursor(.text);

        if (false) {
            // draw mouse cursor preview
            const index = gfx.get_text_closest_index(string, mouse[0] - rect.x - 2);
            const prefix = it.peek(index);
            const offset_x = gfx.get_text_width(prefix);
            gfx.set_color(.{ 1, 1, 1, 0.5 });
            gfx.fill_rect(.{ .x = rect.x + 1.5 + offset_x, .y = rect.y + 0.5 * (rect.h - text_h), .w = 1, .h = text_h });
        }
    }

    if (has_focus and !input.framedown and is_wasm) {
        if (input_select_start) |select_start| {
            if (input.down) {
                const index = gfx.get_text_closest_index(string, mouse[0] - rect.x - 2);
                const start = @min(index, select_start);
                const end = @max(index, select_start);
                wasm.gui_input_text_select(id, start, end);
            } else {
                input_select_start = null;
            }
        }
    }

    return string;
}

pub const ButtonOptions = struct {
    pub const Style = enum {
        normal,
        text_only,
        nodraw,
    };
    style: Style = .normal,
    cursor: input.Cursor = .pointer,
    enabled: bool = true,
};

pub fn button(caption: []const u8, rect: gfx.Rect, options: ButtonOptions) bool {
    const id: *const anyopaque = caption.ptr;

    const mouse = gfx.point_from_screen(.{ input.mx, input.my });
    const hover = options.enabled and gfx.point_in_rect(mouse, rect);
    if (hover) input.set_cursor(options.cursor);
    // if (hover and !gfx.point_in_rect(input.mx_prev, input.my_prev, rect)) audio.play_sound(assets.sound_hover);

    const has_focus = input_focus == id;

    gfx.save();
    defer gfx.restore();

    switch (options.style) {
        .normal => {
            var buf: [400]u8 = undefined;
            var stack_allocator = std.heap.FixedBufferAllocator.init(&buf);
            var path = gfx.Path.init(stack_allocator.allocator(), 44) catch unreachable;
            path.rect_rounded(rect.inset(0.5), 5);

            const font_size = 20;
            gfx.set_font_id(0);
            gfx.set_font_size(font_size);

            gfx.set_color(@splat(1));
            gfx.set_gradient_linear(
                .{ rect.x, rect.y },
                .{ rect.x, rect.y + rect.h },
                if (hover) &.{ gfx.rgb(0x5E5E5E), gfx.rgb(0x444444) } else &.{ gfx.rgb(0x4E4E4E), gfx.rgb(0x343434) },
                &.{ 0, 1 },
                false,
            );
            gfx.fill_path(&path);
            gfx.set_gradient_none();
            gfx.set_stroke_width(1);
            gfx.set_color(.{ 1, 1, 1, 0.2 });
            path.clear();
            var inner_rect = rect.inset(0.5).offset(0, 1);
            inner_rect.h -= 1;
            path.rect_rounded(inner_rect, 5);
            gfx.stroke_path(&path);
            gfx.set_color(gfx.rgb(0x121212));
            path.clear();
            path.rect_rounded(rect.inset(0.5), 5);
            gfx.stroke_path(&path);

            if (has_focus) {
                //     gfx.set_color(.{ 1, 1, 1, 0.8 });
                //     gfx.set_stroke_width(1);
                //     gfx.stroke_rect(background.inset(3.5)) catch unreachable;
            }

            const text_w = gfx.get_text_width(caption);
            const text_h = gfx.get_text_height();
            gfx.set_color(gfx.rgb(0xDEDEDE));
            gfx.draw_text(caption, rect.x + 0.5 * (rect.w - text_w), rect.y + 0.5 * (rect.h - text_h));
        },
        .text_only => {
            // if (!options.blink_text or @sin(40 * time.seconds) > 0) {
            //     if (options.enabled) {
            //         vg.fillColor(if (hover) colors.white else colors.gray_blue1);
            //     } else {
            //         vg.fillColor(color_disabled);
            //     }
            //     _ = vg.text(x + 0.5 * w, y + 0.5 * h, label);
            // }
        },
        .nodraw => {},
    }

    const click = hover and input.framedown;
    // if (click) audio.play_sound(assets.sound_click);
    return click;
}

pub const CheckboxOptions = struct {
    enabled: bool = true,
};

var checkbox_alpha: f32 = 0;

pub fn checkbox(label: []const u8, rect: gfx.Rect, state: *bool, options: CheckboxOptions) void {
    var buf: [400]u8 = undefined;
    var stack_allocator = std.heap.FixedBufferAllocator.init(&buf);

    const mouse = gfx.point_from_screen(.{ input.mx, input.my });
    const hover = options.enabled and gfx.point_in_rect(mouse, rect);
    if (hover) input.set_cursor(.pointer);

    const click = hover and input.framedown;
    if (click) state.* = !state.*;

    // const state_alpha: f32 = 0.5 + 0.5 * @sin(3.14 * time.seconds);
    const target_alpha: f32 = if (state.*) 1 else 0;
    checkbox_alpha = math.approach(checkbox_alpha, target_alpha, 10 * time.dt);
    const state_alpha = checkbox_alpha;
    var path = gfx.Path.init(stack_allocator.allocator(), 44) catch unreachable;
    const rect_base: gfx.Rect = .{ .x = rect.x, .y = rect.y + 0.5 * (rect.h - 34), .w = 64, .h = 34 };
    const cx = rect_base.x + math.mix(17, 64 - 17, state_alpha);
    const cy = rect_base.y + 17;
    // gfx.set_color(gfx.rgb(0xEAEAEA));
    // gfx.fill_rect(rect_base.inset(-10));
    // gfx.set_color(@splat(1));
    { // background
        path.rect_rounded(rect_base, 17);
        gfx.set_color(gfx.rgb(0xDFDFDF));
        gfx.fill_path(&path);
        gfx.set_color(@splat(1));
        gfx.set_gradient_box(rect_base.offset(0, 1), 17, 10, &.{ @splat(0), .{ 0, 0, 0, 0.1 } }, &.{ 0, 1 }, true);
        gfx.fill_path(&path);
    }
    { // slot
        const rect_slot = rect_base.inset(3);
        path.clear();
        path.rect_rounded(rect_slot, 14);
        gfx.set_gradient_linear(.{ rect_slot.x, rect_slot.y }, .{ rect_slot.x, rect_slot.y + rect_slot.h }, &.{ gfx.rgb(0xB6B9B1), gfx.rgb(0xE4E4E4) }, &.{ 0, 1 }, true);
        gfx.fill_path(&path);
        if (state_alpha > 0) {
            path.clear();
            var rect_green = rect_slot;
            rect_green.w = math.mix(2 * 14, rect_slot.w, state_alpha);
            path.rect_rounded(rect_green, 14);
            gfx.set_gradient_linear(.{ rect_slot.x, rect_slot.y }, .{ rect_slot.x, rect_slot.y + rect_slot.h }, &.{ gfx.rgb(0x60BC7D), gfx.rgb(0x7BE29B) }, &.{ 0, 1 }, true);
            gfx.fill_path(&path);
            path.clear();
            path.rect_rounded(rect_slot, 14);
        }
        gfx.set_gradient_box(rect_slot.offset(0, 1), 14, 10, &.{ @splat(0), .{ 0, 0, 0, 0.1 } }, &.{ 0, 1 }, true);
        gfx.fill_path(&path);
    }
    { // knob
        path.clear();
        path.circle(cx, cy, 12);
        gfx.set_color(@splat(1));
        gfx.set_gradient_linear(.{ cx, cy - 15.5 }, .{ cx, cy + 15.5 }, &.{ gfx.rgb(0x71746F), gfx.rgb(0xB3B3B3) }, &.{ 0, 1 }, false);
        gfx.set_stroke_width(5);
        gfx.stroke_path(&path);
        var colors0 = [3]gfx.Color{ gfx.rgb(0xF4F7F2), gfx.rgb(0xCFD0CC), @splat(1) };
        const colors0_active = [3]gfx.Color{ gfx.rgb(0xEDF8E8), gfx.rgb(0xCDD3C1), gfx.rgb(0xF0FBEB) };
        for (0..3) |i| colors0[i] = la.lerp(gfx.Color, colors0[i], colors0_active[i], state_alpha);
        gfx.set_gradient_radial(.{ cx, cy - 15 }, 0, 30, &colors0, &.{ 0, 0.5, 1 }, false);
        gfx.set_stroke_width(4);
        gfx.stroke_path(&path);
        var colors1 = [2]gfx.Color{ gfx.rgb(0xC9CAC6), gfx.rgb(0xD6DBD4) };
        const colors1_active = [2]gfx.Color{ gfx.rgb(0xB3C0AF), gfx.rgb(0xCFDAC9) };
        for (0..2) |i| colors1[i] = la.lerp(gfx.Color, colors1[i], colors1_active[i], state_alpha);
        gfx.set_gradient_linear(.{ cx, cy - 15 }, .{ cx, cy + 15 }, &colors1, &.{ 0, 1 }, false);
        gfx.fill_path(&path);
    }
    { // indicator light
        path.clear();
        path.circle(cx, cy, 5);
        gfx.set_color(.{ 1, 1, 1, state_alpha });
        gfx.set_gradient_radial(.{ cx, cy }, 0, 5, &.{ gfx.rgb(0xF5FFFB), gfx.rgb(0x96F9B8), gfx.rgba(0x4CFF8000) }, &.{ 0.09, 0.58, 1 }, false);
        gfx.fill_path(&path);
    }
    gfx.set_gradient_none();

    gfx.set_color(@splat(1));
    gfx.set_font_size(20);
    gfx.draw_text(label, rect.x + 16 + rect_base.w, rect.y + 0.5 * (rect.h - gfx.get_text_height()));
}

pub fn panel(rect: gfx.Rect) void {
    var buf: [400]u8 = undefined;
    var stack_allocator = std.heap.FixedBufferAllocator.init(&buf);
    var rect_path = gfx.Path.init(stack_allocator.allocator(), 44) catch unreachable;

    // shadow
    gfx.set_color(@splat(1));
    draw_box_shadow(rect, .{ 0, 20 }, 24, 0, .{ 0, 0, 0, 0.25 });
    draw_box_shadow(rect, .{ 0, 6 }, 4, -4, .{ 0, 0, 0, 0.25 });
    draw_box_shadow(rect, .{ 0, 15 }, 14, -16, .{ 0, 0, 0, 0.25 });
    gfx.set_gradient_none();

    // border and fill
    rect_path.clear();
    rect_path.rect_rounded(rect.inset(-0.25), 3);
    gfx.set_color(gfx.rgb(0xD9D9D9));
    // gfx.set_color(gfx.rgb(0xEAEAEA));
    gfx.fill_path(&rect_path);
    gfx.set_color(@splat(1));
    gfx.set_gradient_linear(.{ rect.x, rect.y }, .{ rect.x, rect.y + rect.h }, &.{ @splat(1), gfx.rgb(0xA3A3A3) }, &.{ 0, 1 }, false);
    gfx.set_stroke_width(0.5);
    gfx.stroke_path(&rect_path);
    gfx.set_gradient_none();
}

fn draw_box_shadow(rect: gfx.Rect, offset: la.vec2, blur_radius: f32, spread: f32, color: gfx.Color) void {
    gfx.set_gradient_box(
        rect.offset(offset[0], offset[1]).inset(-spread),
        blur_radius,
        2 * blur_radius,
        &.{ color, .{ color[0], color[1], color[2], 0 } },
        &.{ 0, 1 },
        true,
    );
    gfx.fill_rect(rect.offset(offset[0], offset[1]).inset(-spread - blur_radius));
}
