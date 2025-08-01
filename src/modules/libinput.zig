const std = @import("std");
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;
const events = @import("../events.zig");
const libinput = @import("../lib/libinput.zig");
pub const Libinput = struct {
    const Self = @This();
    allocator: Allocator,
    app: *App,
    input: *libinput.Libinput,
    count: std.AutoHashMap(events.Events, usize),
    pub fn init(ctx: Context) !*Self {
        const self = try ctx.allocator.create(Self);
        errdefer ctx.allocator.destroy(self);
        const allocator = ctx.allocator;
        self.allocator = allocator;
        self.app = ctx.app;
        self.input = undefined;
        self.count = std.AutoHashMap(events.Events, usize).init(allocator);
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.count.deinit();
        allocator.destroy(self);
    }
    pub fn eventStart(self: *Self) !void {
        const input = try libinput.Libinput.init(self.allocator);
        self.input = input;
        input.userData = self;
        input.onEvent = @ptrCast(&onEvent);
    }
    pub fn eventStop(self: *Self) !void {
        self.input.deinit();
    }
    fn convertEvent(e: events.Events) libinput.EventType {
        return switch (e) {
            .libinput_keyboard_key => .keyboardKey,
            .libinput_pointer_motion => .pointerMotion,
            .libinput_pointer_button => .pointerButton,
            else => @panic("Unsupported event type"),
        };
    }
    pub fn eventOnChange(self: *Self, state: events.ChangeState, event: events.Events) void {
        const result = self.count.getOrPut(event) catch unreachable;
        if (!result.found_existing) {
            result.value_ptr.* = 0;
            self.input.addListener(convertEvent(event));
        }
        switch (state) {
            .add => result.value_ptr.* += 1,
            .remove => result.value_ptr.* -= 1,
        }
        if (result.value_ptr.* == 0) {
            self.input.removeListener(convertEvent(event));
            _ = self.count.remove(event);
        }
    }
    fn onEvent(self: *Self, e: libinput.Event) void {
        switch (e) {
            .keyboardKey => |key| self.app.emitEvent(.libinput_keyboard_key, key),
            .pointerMotion => |motion| self.app.emitEvent(.libinput_pointer_motion, motion),
            .pointerButton => |button| self.app.emitEvent(.libinput_pointer_button, button),
            else => @panic("Unsupported event type"),
        }
    }
    pub fn register() Registry(Self) {
        return .{
            .events = &.{
                .libinput_pointer_motion,
                .libinput_pointer_button,
                .libinput_keyboard_key,
            },
        };
    }
    fn parseEventType(t: []const u8) !libinput.EventType {
        const eql = std.mem.eql;
        for (std.enums.values(libinput.EventType)) |e| {
            if (eql(u8, @tagName(e), t)) {
                return e;
            }
        }
        return error.InvalidEventType;
    }
};
