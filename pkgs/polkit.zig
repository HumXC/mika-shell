const c = @cImport({
    @cDefine("POLKIT_AGENT_I_KNOW_API_IS_SUBJECT_TO_CHANGE", "1");
    @cInclude("polkitagent/polkitagent.h");
    @cInclude("security/pam_appl.h");
    @cInclude("polkit.h");
    @cInclude("systemd/sd-login.h");
});
const Agent = extern struct {
    parent_instance: *anyopaque,
    pub fn init() *Agent {
        const agent = c.g_object_new(c.mika_shell_polkit_authentication_agent_get_type(), null);
        return @ptrCast(@alignCast(agent));
    }
    pub fn deinit(self: *Agent) void {
        c.g_object_unref(self);
    }
};
fn on_init() callconv(.c) void {
    std.debug.print("doing init\n", .{});
}
const std = @import("std");
const glib = @import("glib");
const Allocator = std.mem.Allocator;
pub fn getSessionId(allocator: Allocator) ![]const u8 {
    var session: [*c]const u8 = null;
    _ = c.sd_pid_get_session(c.getpid(), @ptrCast(&session));
    defer c.free(@ptrCast(@constCast(session)));
    return try allocator.dupe(u8, std.mem.span(session));
}
pub fn func() void {
    const allocator = std.heap.page_allocator;
    const sessionId = getSessionId(allocator) catch return;
    defer allocator.free(sessionId);
    std.debug.print("Session ID: {s}\n", .{sessionId});
    const agent = Agent.init();
    const subject = c.polkit_unix_session_new_for_process_sync(c.getpid(), null, null);
    _ = c.polkit_agent_listener_register(@ptrCast(agent), c.POLKIT_AGENT_REGISTER_FLAGS_NONE, subject, null, null, null);
    glib.timeoutMainLoop(3_000);
}
