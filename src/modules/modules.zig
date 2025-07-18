const std = @import("std");
/// 放心地在 Modules 回调中使用 try xxx(n), xxx是参数类型, n是参数的位置
///
/// 如果参数不符合预期,则会返回 error.InvalidArgs, 可以直接将此错误返回给前端
pub const Args = struct {
    items: []std.json.Value,
    fn verifyIndex(self: Args, index: usize) !void {
        if (index >= self.items.len) return error.InvalidArgs;
    }
    pub fn value(self: Args, index: usize) !std.json.Value {
        try self.verifyIndex(index);
        return self.items[index];
    }
    pub fn @"bool"(self: Args, index: usize) !bool {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .bool => |b| return b,
            else => return error.InvalidArgs,
        }
    }
    pub fn integer(self: Args, index: usize) !i64 {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .integer => |i| return i,
            else => return error.InvalidArgs,
        }
    }
    pub fn uInteger(self: Args, index: usize) !u64 {
        const i = try self.integer(index);
        if (i < 0) return error.InvalidArgs;
        return @intCast(i);
    }
    pub fn float(self: Args, index: usize) !f64 {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .float => |f| return f,
            else => return error.InvalidArgs,
        }
    }
    pub fn string(self: Args, index: usize) ![]const u8 {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .string => |s| return s,
            else => return error.InvalidArgs,
        }
    }
    pub fn array(self: Args, index: usize) !std.json.Array {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .array => |a| return a,
            else => return error.InvalidArgs,
        }
    }
    pub fn object(self: Args, index: usize) !std.json.ObjectMap {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .object => |o| return o,
            else => return error.InvalidArgs,
        }
    }
};

pub const Result = struct {
    allocator: std.mem.Allocator,
    buffer: ?std.ArrayList(u8) = null,
    err: ?[]const u8 = null,
    pub fn init(allocator: std.mem.Allocator) Result {
        return .{
            .allocator = allocator,
        };
    }
    pub fn deinit(self: *Result) void {
        if (self.buffer) |b| b.deinit();
        if (self.err) |e| self.allocator.free(e);
    }
    pub fn commit(self: *Result, value: anytype) void {
        if (self.buffer != null) @panic("commit twice");
        self.buffer = std.ArrayList(u8).init(self.allocator);
        std.json.stringify(value, .{}, self.buffer.?.writer()) catch @panic("OOM");
    }
    /// 总是返回一个 error.HasError, 切勿捕获该错误, 应该直接返回给 Webview 处理
    pub fn errors(self: *Result, comptime fmt: []const u8, args: anytype) anyerror {
        self.err = std.fmt.allocPrint(self.allocator, fmt, args) catch @panic("OOM");
        return error.HasError;
    }
    pub fn toJSCValue(self: *Result, ctx: *webkit.JSCContext) *webkit.JSCValue {
        if (self.err != null) @panic("error message is not null, cannot convert to JSCValue");
        if (self.buffer == null) return ctx.newUndefined();
        const str = self.allocator.dupeZ(u8, self.buffer.?.items) catch @panic("OOM");
        defer self.allocator.free(str);
        return ctx.newFromJson(str);
    }
};

pub fn Callable(comptime T: type) type {
    return *const fn (self: T, args: Args, result: *Result) anyerror!void;
}
pub fn Entry(comptime T: type) type {
    return struct {
        self: T,
        call: Callable(T),
    };
}
const AnyEntry = Entry(*anyopaque);
pub const Modules = struct {
    allocator: std.mem.Allocator,
    table: std.StringHashMap(AnyEntry),
    pub fn init(allocator: std.mem.Allocator) *Modules {
        const m = allocator.create(Modules) catch unreachable;
        m.* = .{
            .table = std.StringHashMap(AnyEntry).init(allocator),
            .allocator = allocator,
        };
        return m;
    }
    pub fn deinit(self: *Modules) void {
        self.table.deinit();
        self.allocator.destroy(self);
    }
    pub fn call(self: *Modules, name: []const u8, args: Args, result: *Result) !void {
        const entry = self.table.get(name) orelse {
            return error.FunctionNotFound;
        };
        return entry.call(entry.self, args, result);
    }
    pub fn register(
        self: *Modules,
        module: anytype,
        name: []const u8,
        comptime function: Callable(@TypeOf(module)),
    ) void {
        const wrap: Callable(*anyopaque) = comptime blk: {
            const wrapper = struct {
                fn wrap(self_: *anyopaque, args: Args, result: *Result) !void {
                    return function(@ptrCast(@alignCast(self_)), args, result);
                }
            };
            break :blk &wrapper.wrap;
        };
        const entry = AnyEntry{
            .self = module,
            .call = wrap,
        };
        if (self.table.contains(name)) {
            @panic("function already registered");
        }
        self.table.put(name, entry) catch unreachable;
    }
};
const TestModule = struct {
    pub fn show(_: *TestModule, _: Args, result: *Result) !void {
        result.commit("Hello, world!");
    }
    pub fn throw(_: *TestModule, _: Args, _: *Result) !void {
        return error.TestError;
    }
    pub fn testArgs(_: *TestModule, args: Args, _: *Result) !void {
        _ = try args.integer(0);
        _ = try args.bool(1);
        _ = try args.string(2);
        _ = try args.array(3);
        _ = try args.object(4);
    }
};
const webkit = @import("webkit");

test "register and call" {
    const allocator = std.testing.allocator;
    var m = Modules.init(allocator);
    defer m.deinit();
    var testModule = TestModule{};
    const t = &testModule;
    m.register(t, "show", TestModule.show);
    m.register(t, "throw", TestModule.throw);
    m.register(t, "testArgs", TestModule.testArgs);
    const jsonStr =
        \\{
        \\    "args": [
        \\        2,
        \\        true,
        \\        "hello",
        \\        [3,4,5],
        \\        {"foo":"bar"}
        \\    ]
        \\}
    ;
    const v = try std.json.parseFromSlice(std.json.Value, allocator, jsonStr, .{});
    defer v.deinit();
    const value = Args{ .items = v.value.object.get("args").?.array.items };
    var result = Result.init(allocator);
    defer result.deinit();
    try m.call("show", value, &result);
    try std.testing.expectEqualStrings("\"Hello, world!\"", result.buffer.?.items);
    const ctx = webkit.JSCContext.new();
    const jsvalue = result.toJSCValue(ctx);
    try std.testing.expectEqualStrings("\"Hello, world!\"", jsvalue.toJson(0));
    try std.testing.expectError(error.TestError, m.call("throw", value, &result));

    try m.call("testArgs", value, &result);
}
