const cli = @import("cli.zig");
pub fn main() !void {
    return cli.run();
}

test {
    _ = @import("./lib/tray.zig");
}
