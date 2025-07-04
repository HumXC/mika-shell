const libdbus = @import("libdbus.zig");
const std = @import("std");
const glib = @import("glib");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;
const Error = libdbus.Error;
const Type = libdbus.Types;
const Message = libdbus.Message;
const Bus = @import("bus.zig").Bus;
const Errors = @import("bus.zig").Errors;
/// 啊这
pub fn Result(T: type) type {
    return struct {
        response: *libdbus.Message,
        iter: *libdbus.MessageIter,
        values: ?T,
        pub fn deinit(self: @This()) void {
            self.response.deinit();
            self.iter.deinit();
        }
    };
}
pub fn GetResult(T: type) type {
    return struct {
        result: Result(std.meta.Tuple(&.{Type.Variant.Type})),
        value: T,
        pub fn deinit(self: @This()) void {
            self.result.deinit();
        }
    };
}
pub const GetAllResult = struct {
    result: Result(Type.getTupleTypes(.{Type.Dict(Type.String, Type.Variant)})),
    allocator: Allocator,
    map: *std.StringHashMap(Type.Variant.Type),
    pub fn get(self: GetAllResult, key: []const u8, ValueType: type) ?ValueType.Type {
        const val = self.map.get(key);
        if (val == null) return null;
        return val.?.get(ValueType) catch return null;
    }
    pub fn deinit(self: GetAllResult) void {
        self.result.deinit();
        self.map.deinit();
        self.allocator.destroy(self.map);
    }
};
/// 调用一个 dbus 方法, 并返回结果
///
/// argsType 和 resultType: 是方法的参数类型,接受一个 Tuple 描述方法调用的参数的类型
///
/// args 是实际传入的参数,根据 argsType 决定传入的参数类型:
/// ```
/// {dbus.String, dbus.Int32, dbus.Array(dbus.String)}
/// ```
/// 根据上方的类型, args 应当与 argsType 匹配:
/// ```
/// .{ "hello", 123, &.{ "world", "foo" } }
/// ```
///
/// example:
/// ```
/// const result = try baseCall(
///     allocator,
///     conn,
///     err,
///     "org.freedesktop.DBus",
///     "/",
///     "org.freedesktop.DBus",
///     "ListNames",
///    .{},
///     null,
///    .{dbus.Array(dbus.String)},
/// );
/// defer result.deinit();
/// ```
/// 在 result 中可以获取返回值, resulr.value 会根据传入的 resulrType 进行类型转换.
/// 在上面的调用中,result.value的类型是 `[][]const u8`
pub fn baseCall(
    allocator: Allocator,
    conn: *libdbus.Connection,
    err: Error,
    name: []const u8,
    path: []const u8,
    iface: []const u8,
    method: []const u8,
    comptime argsType: anytype,
    args: ?Type.getTupleTypes(argsType),
    comptime resultType: anytype,
) !Result(Type.getTupleTypes(resultType)) {
    const args_info = @typeInfo(@TypeOf(argsType));
    if (args_info != .@"struct" or !args_info.@"struct".is_tuple) {
        @compileError("expected a tuple, found " ++ @typeName(@TypeOf(argsType)));
    }
    const request = libdbus.Message.newMethodCall(name, path, iface, method);
    defer request.deinit();
    const iter = libdbus.MessageIter.init(allocator);
    errdefer iter.deinit();
    iter.fromAppend(request);
    if (args != null) {
        inline for (args.?, 0..) |arg, i| {
            try iter.append(argsType[i], arg);
        }
    }
    const response = try conn.sendWithReplyAndBlock(request, -1, err);
    const hasResult = iter.fromResult(response);
    return .{
        .response = response,
        .iter = iter,
        .values = if (hasResult) try iter.getAll(resultType) else null,
    };
}

pub const Object = struct {
    const Self = @This();
    name: [:0]const u8,
    path: [:0]const u8,
    iface: [:0]const u8,
    uniqueName: [:0]const u8,
    bus: *Bus,
    allocator: Allocator,
    err: Error,
    listeners: std.ArrayList(common.Listener),
    pub fn deinit(self: *Self) void {
        for (self.listeners.items) |listener| {
            self.disconnect(listener.signal, listener.handler, listener.data) catch {
                self.err.reset();
            };
        }
        self.err.deinit();
        self.listeners.deinit();
        self.allocator.free(self.name);
        self.allocator.free(self.path);
        self.allocator.free(self.iface);
        self.allocator.free(self.uniqueName);

        for (self.bus.objects.items, 0..) |obj, i| {
            if (obj == self) {
                _ = self.bus.objects.swapRemove(i);
                break;
            }
        }
        self.allocator.destroy(self);
    }
    fn callWithSelf(self: *Self, name: []const u8, path: []const u8, iface: []const u8, method: []const u8, comptime argsType: anytype, args: ?Type.getTupleTypes(argsType), comptime resultType: anytype) !Result(Type.getTupleTypes(resultType)) {
        return baseCall(
            self.allocator,
            self.bus.conn,
            self.err,
            name,
            path,
            iface,
            method,
            argsType,
            args,
            resultType,
        );
    }
    /// 调用一个 dbus 方法, 并返回结果
    ///
    /// argsType 和 resultType: 是方法的参数类型,接受一个 Tuple 描述方法调用的参数的类型
    ///
    /// args 是实际传入的参数,根据 argsType 决定传入的参数类型:
    /// ```
    /// {dbus.String, dbus.Int32, dbus.Array(dbus.String)}
    /// ```
    /// 根据上方的类型, args 应当与 argsType 匹配:
    /// ```
    /// .{ "hello", 123, &.{ "world", "foo" } }
    /// ```
    /// `const result = object.call(xxx);`
    /// 从 result.values 中获取返回值, resulr.value 会根据传入的 resulrType 进行类型转换.
    /// 使用完成后,必须调用 result.deinit() 释放资源
    pub fn call(self: *Object, name: []const u8, comptime argsType: anytype, args: ?Type.getTupleTypes(argsType), comptime resultType: anytype) !Result(Type.getTupleTypes(resultType)) {
        return self.callWithSelf(
            self.name,
            self.path,
            self.iface,
            name,
            argsType,
            args,
            resultType,
        );
    }
    /// 发送但不接收回复
    pub fn callN(self: *Object, name: []const u8, comptime argsType: anytype, args: ?Type.getTupleTypes(argsType)) !void {
        const request = libdbus.Message.newMethodCall(self.name, self.path, self.iface, name);
        defer request.deinit();
        const iter = libdbus.MessageIter.init(self.allocator);
        defer iter.deinit();
        iter.fromAppend(request);
        if (args != null) {
            inline for (args.?, 0..) |arg, i| {
                try iter.append(argsType[i], arg);
            }
        }
        if (!self.bus.conn.send(request, null)) {
            return error.SendFailed;
        }
    }
    /// 获取属性值
    pub fn get(self: *Object, name: []const u8, ResultTyep: type) !GetResult(ResultTyep.Type) {
        const resp = try self.callWithSelf(
            self.name,
            self.path,
            "org.freedesktop.DBus.Properties",
            "Get",
            .{ Type.String, Type.String },
            .{ self.iface, name },
            .{Type.Variant},
        );
        return .{ .result = resp, .value = try resp.values.?[0].get(ResultTyep) };
    }
    /// 设置属性值
    pub fn set(self: *Object, name: []const u8, Value: type, value: Value.Type) !void {
        const resp = try self.callWithSelf(
            self.name,
            self.path,
            "org.freedesktop.DBus.Properties",
            "Set",
            .{ Type.String, Type.String, Type.Variant },
            .{ self.iface, name, Type.Variant.init(Value, value) },
            .{},
        );
        defer resp.deinit();
    }
    /// 获取所有属性值
    pub fn getAll(self: *Object) !GetAllResult {
        const resp = try self.callWithSelf(
            self.name,
            self.path,
            "org.freedesktop.DBus.Properties",
            "GetAll",
            .{Type.String},
            .{self.iface},
            .{Type.Dict(Type.String, Type.Variant)},
        );
        const HashMap = std.StringHashMap(Type.Variant.Type);
        const map = try self.allocator.create(HashMap);
        map.* = HashMap.init(self.allocator);
        const dict = resp.values.?[0];
        for (dict) |entry| {
            try map.put(entry.key, entry.value);
        }
        return GetAllResult{
            .allocator = self.allocator,
            .map = map,
            .result = resp,
        };
    }
    /// 调用 Ping 方法
    pub fn ping(self: *Object) bool {
        const r = self.callWithSelf(self.name, self.path, "org.freedesktop.DBus.Peer", "Ping", .{}, null, .{}) catch {
            self.err.reset();
            return false;
        };
        defer r.deinit();
        return true;
    }
    /// 监听信号
    ///
    /// 在回调中无需处理 Event 中的 iter, iter 会在回调退出后自动释放
    pub fn connect(self: *Object, signal: []const u8, handler: *const fn (common.Event, ?*anyopaque) void, data: ?*anyopaque) !void {
        if (self.listeners.items.len == 0) {
            if (!try self.bus.addFilter(.{ .type = .signal }, signalHandler, self)) {
                self.bus.err.reset();
                return error.AddFilterFailed;
            }
        }
        for (self.listeners.items) |listener| {
            if (std.mem.eql(u8, listener.signal, signal)) {
                return;
            }
        }

        try self.bus.addMatch(.{ .type = .signal, .sender = self.uniqueName, .interface = self.iface, .member = signal, .path = self.path });

        self.listeners.append(.{
            .signal = signal,
            .handler = @ptrCast(handler),
            .data = data,
        }) catch @panic("OOM");
    }
    pub fn disconnect(self: *Object, signal: []const u8, handler: *const fn (common.Event, ?*anyopaque) void, data: ?*anyopaque) !void {
        for (self.listeners.items, 0..) |listener, i| {
            if (std.mem.eql(u8, listener.signal, signal) and listener.handler == handler and listener.data == data) {
                _ = self.listeners.swapRemove(i);
                if (self.listeners.items.len == 0) {
                    self.bus.removeFilter(.{ .type = .signal }, signalHandler, self);
                }
                for (self.listeners.items) |l| {
                    if (std.mem.eql(u8, l.signal, signal)) {
                        return;
                    }
                }
                self.bus.err.reset();
                self.bus.removeMatch(.{ .type = .signal, .sender = self.uniqueName, .interface = self.iface, .member = signal, .path = self.path }) catch {
                    self.bus.err.reset();
                    return error.RemoveMatchFailed;
                };
                return;
            }
        }
        return error.SignalOrHandlerNotFound;
    }
};
fn signalHandler(data: ?*anyopaque, msg: *Message) void {
    const obj: *Object = @ptrCast(@alignCast(data));
    const sender = msg.getSender();
    const iface_ = msg.getInterface();
    const path_ = msg.getPath();
    const member_ = msg.getMember();
    if (iface_ == null) return;
    if (path_ == null) return;
    if (member_ == null) return;
    const iface = iface_.?;
    const path = path_.?;
    const member = member_.?;
    const destination = msg.getDestination();
    var event = common.Event{
        .sender = sender,
        .iface = iface,
        .path = path,
        .member = member,
        .serial = msg.getSerial(),
        .destination = destination,
        .iter = libdbus.MessageIter.init(obj.allocator),
    };
    defer event.iter.deinit();
    for (obj.listeners.items) |listener| {
        if (std.mem.eql(u8, listener.signal, member)) {
            event.iter.reset();
            _ = event.iter.fromResult(msg);
            listener.handler(event, listener.data);
        }
    }
}
const testing = std.testing;
const print = std.debug.print;
const withGLibLoop = @import("bus.zig").withGLibLoop;

test "ping" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    try testing.expect(proxy.ping());
}

test "call" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    const resp = try proxy.call("GetArrayString", .{}, null, .{Type.Array(Type.String)});
    defer resp.deinit();
    const val = resp.values.?[0];
    try testing.expectEqualStrings("foo", val[0]);
    try testing.expectEqualStrings("bar", val[1]);
    try testing.expectEqualStrings("baz", val[2]);
}

test "get" {
    const allocator = testing.allocator;
    const bus = try Bus.init(allocator, .Session);
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    const resp = try proxy.get("Byte", Type.Byte);
    defer resp.deinit();
    try testing.expectEqual(123, resp.value);
}

test "get-all" {
    const allocator = testing.allocator;
    const bus = try Bus.init(allocator, .Session);
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    const resp = try proxy.getAll();
    defer resp.deinit();
    try testing.expectEqual(123, resp.get("Byte", Type.Byte).?);
    try testing.expectEqual(-32768, resp.get("Int16", Type.Int16).?);
}

test "set" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    try proxy.set("Boolean", Type.Boolean, true);
    try proxy.set("Boolean", Type.Boolean, false);
}
fn test_on_signal1(event: common.Event, err_: ?*anyopaque) void {
    const err: *anyerror = @ptrCast(@alignCast(err_.?));
    const value = event.iter.getAll(.{ Type.String, Type.Int32 }) catch unreachable;
    err.* = error.OK;
    testing.expectEqualStrings("TestSignal", value[0]) catch |er| {
        err.* = er;
        return;
    };
    testing.expectEqual(78787, value[1]) catch |er| {
        err.* = er;
        return;
    };
}
test "signal" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    var err: ?anyerror = null;
    try proxy.connect("Signal1", test_on_signal1, &err);
    glib.timeoutMainLoop(200);
    try testing.expect(err != null);
    try testing.expect(err.? == error.OK);
}
// 用于测试 NameOwnerChanged 信号是否正常工作, 需要手动测试
// test "signal-owner-changed" {
//     const allocator = testing.allocator;
//     const bus = Bus.init(allocator, .Session) catch unreachable;
//     defer bus.deinit();
//     var proxy = try bus.proxy("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher");
//     defer proxy.deinit();
//     glib.timeoutMainLoop(300);
// }
test "signal-disconnect" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    try proxy.connect("Signal1", test_on_signal1, null);
    try proxy.disconnect("Signal1", test_on_signal1, null);
    try testing.expectError(error.SignalOrHandlerNotFound, proxy.disconnect("Signal1", test_on_signal1, null));
}
test "get-error" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    try proxy.callN("GetError", .{}, null);
}
