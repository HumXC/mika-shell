const dbus = @import("dbus");
const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
fn getSessionID(allocator: Allocator, bus: *dbus.Bus) ![]const u8 {
    const pid = std.os.linux.getpid();
    const sessionResult = try bus.call(
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
        "GetSessionByPID",
        .{dbus.UInt32},
        .{@intCast(pid)},
    );
    defer sessionResult.deinit();
    const session = sessionResult.next(dbus.ObjectPath);
    const idResult = try bus.call(
        "org.freedesktop.login1",
        session,
        "org.freedesktop.DBus.Properties",
        "Get",
        .{ dbus.String, dbus.String },
        .{ "org.freedesktop.login1.Session", "Id" },
    );
    defer idResult.deinit();
    const id = idResult.next(dbus.AnyVariant).as(dbus.String);
    return try allocator.dupe(u8, id);
}
fn registerAgent(bus: *dbus.Bus, locale: []const u8, path: []const u8) !void {
    if (bus.type != .System) {
        return error.DBusNotSystemBus;
    }
    const allocator = bus.allocator;
    const id = try getSessionID(allocator, bus);
    defer allocator.free(id);
    const method = "RegisterAuthenticationAgent";
    const ArgsType = .{
        dbus.Struct(.{
            dbus.String,
            dbus.Dict(dbus.String, dbus.AnyVariant),
        }),
        dbus.String,
        dbus.String,
    };
    const result = bus.call(
        "org.freedesktop.PolicyKit1",
        "/org/freedesktop/PolicyKit1/Authority",
        "org.freedesktop.PolicyKit1.Authority",
        method,
        ArgsType,
        .{
            .{
                "unix-session",
                &.{.{ .key = "session-id", .value = dbus.Variant(dbus.String).init(&id) }},
            },
            locale,
            path,
        },
    ) catch {
        return error.FailedToRegisterAgent;
    };

    defer result.deinit();
}
fn unregisterAgent(allocator: Allocator, conn: *dbus.Connection, path: []const u8) !void {
    const err = dbus.Error.init();
    defer err.deinit();
    const id = try getSessionID(allocator, conn);
    defer allocator.free(id);
    const method = "UnregisterAuthenticationAgent";
    const ArgsType = .{
        dbus.Struct(.{
            dbus.String,
            dbus.Dict(dbus.String, dbus.Variant),
        }),
        dbus.String,
    };
    const result = dbus.baseCall(
        allocator,
        conn,
        err,
        "org.freedesktop.PolicyKit1",
        "/org/freedesktop/PolicyKit1/Authority",
        "org.freedesktop.PolicyKit1.Authority",
        method,
        ArgsType,
        .{
            .{
                "unix-session",
                &.{.{ .key = "session-id", .value = dbus.Variant(dbus.String).init(id) }},
            },
            path,
        },
        .{},
    ) catch {
        return error.FailedToRegisterAgent;
    };
    defer result.deinit();
}
const c = @cImport({
    @cDefine("POLKIT_AGENT_I_KNOW_API_IS_SUBJECT_TO_CHANGE", "1");
    @cInclude("polkitagent/polkitagent.h");
    @cInclude("security/pam_appl.h");
});
const Agent = struct {
    const Self = @This();
    bus: *dbus.Bus,
    fn beginAuthentication(_: *Self, _: []const u8, _: Allocator, in: *dbus.MessageIter, _: *dbus.MessageIter, _: *dbus.RequstError) !void {
        std.debug.print("BeginAuthentication called\n", .{});
        const actionId = in.next(dbus.String).?;
        const message = in.next(dbus.String).?;
        const iconName = in.next(dbus.String).?;
        const details = in.next(dbus.Dict(dbus.String, dbus.String)).?;
        const cookie = in.next(dbus.String).?;
        const identities = in.next(DirectionDBus).?;
        std.debug.print("action_id: {s}\n", .{actionId});
        std.debug.print("message: {s}\n", .{message});
        std.debug.print("icon_name: {s}\n", .{iconName});
        for (details) |detail| {
            std.debug.print("detail: {s}={s}\n", .{ detail.key, detail.value });
        }
        std.debug.print("cookie: {s}\n", .{cookie});
        const eql = std.mem.eql;
        for (identities) |identity| {
            const kind = identity[0];
            const details_ = identity[1];
            std.debug.print("identity: {s}\n", .{kind});
            if (eql(u8, kind, "unix-user")) {
                const uid = details_[0].value.as(dbus.UInt32);
                std.debug.print("uid: {d}\n", .{uid});
            }
            if (eql(u8, kind, "unix-group")) {
                const gid = details_[0].value.as(dbus.UInt32);
                std.debug.print("gid: {d}\n", .{gid});
            }
        }
        // err.set("org.freedesktop.PolicyKit1.Error.Cancelled", "Authentication cancelled by user");
        const identity = c.polkit_identity_from_string("unix-user:1000", null);
        const cook = try std.heap.page_allocator.dupeZ(u8, cookie[2..]);
        const session = c.polkit_agent_session_new(identity, cook);
        std.debug.print("Creating session{any}\n", .{session});
        _ = c.g_signal_connect_data(session, "request", @ptrCast(&struct {
            fn f(s: *c.PolkitAgentSession, _: [*c]const u8, _: ?*anyopaque, _: ?*anyopaque) callconv(.C) void {
                std.debug.print("request signal received{any}\n", .{s});

                const password = "imhumxc";
                c.polkit_agent_session_response(s, password.ptr);
            }
        }.f), null, null, 0);
        _ = c.g_signal_connect_data(session, "completed", @ptrCast(&struct {
            fn f(s: *c.PolkitAgentSession, ok: c_int, _: ?*anyopaque, _: ?*anyopaque) callconv(.C) void {
                std.debug.print("completed signal received {s},{any}\n", .{ s, ok });
            }
        }.f), null, null, 0);
        c.polkit_agent_session_initiate(session);
    }
    fn cancelAuthentication(self: *Self, _: []const u8, _: Allocator, in: *dbus.MessageIter, _: *dbus.MessageIter, _: *dbus.RequstError) !void {
        _ = self;
        _ = in;
        std.debug.print("CancelAuthentication called\n", .{});
    }
};
const IdentityDBus = dbus.Struct(.{
    dbus.String,
    dbus.Dict(
        dbus.String,
        dbus.AnyVariant,
    ),
});
const DirectionDBus = dbus.Array(IdentityDBus);
const Interface = dbus.Interface(Agent){
    .name = "org.freedesktop.PolicyKit1.AuthenticationAgent",
    .method = &.{
        .{
            .name = "BeginAuthentication",
            .func = Agent.beginAuthentication,
            .args = &.{
                .{ .direction = .in, .name = "action_id", .type = dbus.String },
                .{ .direction = .in, .name = "message", .type = dbus.String },
                .{ .direction = .in, .name = "icon_name", .type = dbus.String },
                .{ .direction = .in, .name = "details", .type = dbus.Dict(dbus.String, dbus.String) },
                .{ .direction = .in, .name = "cookie", .type = dbus.String },
                .{ .direction = .in, .name = "identities", .type = DirectionDBus },
            },
        },
        .{
            .name = "CancelAuthentication",
            .func = Agent.cancelAuthentication,
            .args = &.{
                .{ .direction = .in, .name = "cookie", .type = dbus.String },
            },
        },
    },
};
const glib = @import("glib");
// test {
//     const pol = @import("polkit");
//     pol.func();
// }
// test {
//     const allocator = testing.allocator;
//     var err: dbus.Error = undefined;
//     err.init();
//     defer err.deinit();
//     const bus = try dbus.Bus.init(allocator, .System);
//     defer bus.deinit();
//     const path = "/com/example/example_agent";
//     var agent = Agent{ .bus = bus };
//     try bus.publish(Agent, path, Interface, &agent, null);
//     registerAgent(bus, "zh_CN.UTF-8", path) catch {
//         std.debug.print("Failed to register agent: {s}\n", .{bus.err.message()});
//     };

//     const watch = try dbus.withGLibLoop(bus);
//     defer watch.deinit();

//     glib.timeoutMainLoop(3_000);
// }
