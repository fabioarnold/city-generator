pub const Sizing = union(Tag) {
    fit: MinMax,
    grow: MinMax,
    percent: f32,
    fixed: f32,

    pub const Tag = enum {
        fit,
        grow,
        percent,
        fixed,
    };

    pub const MinMax = struct {
        min: f32 = 0,
        max: f32 = 0,
    };
};

pub const Alignment = enum {
    start,
    center,
    end,
};

pub const Element = struct {
    width: Sizing = .fit,
    height: Sizing = .fit,
    padding: [4]f32 = &.{ 0, 0, 0, 0 }, // left, top, right, bottom
    direction: enum { row, column } = .row,
    align_x: Alignment = .start,
    align_y: Alignment = .start,
    gap: f32 = 0,
    children: []Element = &.{},

    computed: Box = undefined,
};

pub const Box = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub fn compute_layout(root: *Element, parent_width: f32, parent_height: f32) void {
    compute_size(root, parent_width, parent_height);
    compute_position(root, 0, 0);
}

fn compute_size(element: *Element, parent_width: f32, parent_height: f32) void {
    fit_sizing(element, parent_width, parent_height);
    grow_sizing(element, parent_width, parent_height);
}

fn fit_sizing(element: *Element, parent_width: f32, parent_height: f32) void {
    var total_fixed_width: f32 = 0;
    var total_fixed_height: f32 = 0;
    var num_grow_children: usize = 0;

    for (element.children) |*child| {
        switch (child.width) {
            .fixed => |w| total_fixed_width += w + element.gap,
            .fit => {},
            .grow => num_grow_children += 1,
        }
        switch (child.height) {
            .fixed => |h| total_fixed_height += h + element.gap,
            .fit => {},
            .grow => num_grow_children += 1,
        }
    }
    if (element.children.len > 0) {
        if (element.direction == .row) {
            total_fixed_width -= element.gap;
        } else {
            total_fixed_height -= element.gap;
        }
    }

    // compute own size
    switch (element.width) {
        .fit => {
            if (element.direction == .row) {
                element.computed_width = total_fixed_width + element.padding[0] + element.padding[2];
            } else {
                element.computed_width = parent_width - element.padding[0] - element.padding[2];
            }
        },
        .fixed => |w| element.computed_width = w,
        .grow => {},
    }
    switch (element.height) {
        .fit => {
            if (element.direction == .column) {
                element.computed_height = total_fixed_height + element.padding[1] + element.padding[3];
            } else {
                element.computed_height = parent_height - element.padding[1] - element.padding[3];
            }
        },
        .fixed => |h| element.computed_height = h,
        .grow => {},
    }

    // compute children sizes
    for (element.children) |*child| {
        compute_size(child, element.computed_width - element.padding[0] - element.padding[2], element.computed_height - element.padding[1] - element.padding[3]);
    }
}

fn grow_sizing(element: *Element, parent_width: f32, parent_height: f32) void {
    var total_fixed_width: f32 = 0;
    var total_fixed_height: f32 = 0;
    var num_grow_children: usize = 0;

    for (element.children) |*child| {
        switch (child.width) {
            .fixed => |w| total_fixed_width += w + element.gap,
            .fit => total_fixed_width += child.computed_width + element.gap,
            .grow => num_grow_children += 1,
        }
        switch (child.height) {
            .fixed => |h| total_fixed_height += h + element.gap,
            .fit => total_fixed_height += child.computed_height + element.gap,
            .grow => num_grow_children += 1,
        }
    }
    if (element.children.len > 0) {
        if (element.direction == .row) {
            total_fixed_width -= element.gap;
        } else {
            total_fixed_height -= element.gap;
        }
    }

    const available_width = element.computed_width - element.padding[0] - element.padding[2] - total_fixed_width;
    const available_height = element.computed_height - element.padding[1] - element.padding[3] - total_fixed_height;

    for (element.children) |*child| {
        switch (child.width) {
            .grow => {
                if (num_grow_children > 0 and element.direction == .row) {
                    child.computed_width = available_width / @floatCast(num_grow_children);
                } else {
                    child.computed_width = child.computed_width;
                }
            },
            else => {},
        }
        switch (child.height) {
            .grow => {
                if (num_grow_children > 0 and element.direction == .column) {
                    child.computed_height = available_height / @floatCast(num_grow_children);
                } else {
                    child.computed_height = child.computed_height;
                }
            },
            else => {},
        }
    }
}

fn compute_position(element: *Element, parent_x: f32, parent_y: f32) void {
    element.computed.x = parent_x + element.padding[0];
    element.computed.y = parent_y + element.padding[1];

    var cursor_x: f32 = element.computed.x;
    var cursor_y: f32 = element.computed.y;

    for (element.children) |*child| {
        // align child
        switch (element.direction) {
            .row => {
                switch (element.align_y) {
                    .start => child.computed.y = cursor_y,
                    .center => child.computed.y = cursor_y + (element.computed.h - element.padding[1] - element.padding[3] - child.computed.h) / 2,
                    .end => child.computed.y = cursor_y + (element.computed.h - element.padding[1] - element.padding[3] - child.computed.h),
                }
                child.computed.x = cursor_x;
                cursor_x += child.computed.w + element.gap;
            },
            .column => {
                switch (element.align_x) {
                    .start => child.computed.x = cursor_x,
                    .center => child.computed.x = cursor_x + (element.computed.w - element.padding[0] - element.padding[2] - child.computed.w) / 2,
                    .end => child.computed.x = cursor_x + (element.computed.w - element.padding[0] - element.padding[2] - child.computed.w),
                }
                child.computed.y = cursor_y;
                cursor_y += child.computed.h + element.gap;
            },
        }

        compute_position(child, child.computed.x, child.computed.y);
    }
}
