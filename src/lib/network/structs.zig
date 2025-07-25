const defines = @import("defines.zig");
const dbus = @import("dbus");
const std = @import("std");
const Allocator = std.mem.Allocator;
const DBusHelper = @import("helper.zig").DBusHelper;
const isVaildPath = @import("helper.zig").isValidPath;
pub const Device = struct {
    dbus_path: []const u8,
    interface: []const u8,
    driver: []const u8,
    driver_version: []const u8,
    hw_address: []const u8,
    path: []const u8,
    type: defines.DeviceType,
    pub fn deinit(self: Device, allocator: Allocator) void {
        allocator.free(self.dbus_path);
        allocator.free(self.interface);
        allocator.free(self.driver);
        allocator.free(self.driver_version);
        allocator.free(self.hw_address);
        allocator.free(self.path);
    }
    pub fn init(allocator: Allocator, bus: *dbus.Bus, path: []const u8) !Device {
        const device = try bus.proxy("org.freedesktop.NetworkManager", path, "org.freedesktop.NetworkManager.Device");
        defer device.deinit();

        var d: Device = undefined;
        d.dbus_path = try allocator.dupe(u8, path);
        d.interface = try device.getAlloc(allocator, "Interface", dbus.String);
        errdefer allocator.free(d.interface);
        d.driver = try device.getAlloc(allocator, "Driver", dbus.String);
        errdefer allocator.free(d.driver);
        d.driver_version = try device.getAlloc(allocator, "DriverVersion", dbus.String);
        errdefer allocator.free(d.driver_version);
        d.hw_address = try device.getAlloc(allocator, "HwAddress", dbus.String);
        errdefer allocator.free(d.hw_address);
        d.path = try device.getAlloc(allocator, "Path", dbus.String);
        errdefer allocator.free(d.path);
        d.type = @enumFromInt(try device.getBasic("DeviceType", dbus.UInt32));
        return d;
    }
};
pub const Connection = struct {
    const Wireless = struct {
        const Security = struct {
            @"key-mgmt": enum {
                none,
                ieee8021x,
                @"wpa-psk",
                @"wpa-eap",
                @"wpa-eap-suite-b-192",
                sae,
                owe,
            },
            psk: ?[]const u8,
        };
        band: ?enum {
            @"5GHz",
            @"2.4GHz",
        },
        bssid: ?[]const u8,
        hidden: bool,
        mode: enum {
            infrastructure,
            adhoc,
            ap,
            mesh,
        },
        powersave: enum {
            default,
            ignore,
            disable,
            enable,
        },
        ssid: ?[]const u8,
        security: ?Security,
    };
    dbus_path: []const u8,
    filename: []const u8,
    id: []const u8,
    type: defines.ConnectionType,
    zone: ?[]const u8,
    autoconnect: bool,
    autoconnect_ports: enum { true, false, default },
    metered: enum { yes, no, default },
    autoconnect_priority: i32,
    controller: ?[]const u8,
    interface_name: ?[]const u8,
    wireless: ?Wireless,
    pub fn init(allocator: Allocator, bus: *dbus.Bus, path: []const u8) !Connection {
        const conn = try DBusHelper.init(bus, path, "org.freedesktop.NetworkManager.Settings.Connection");
        defer conn.deinit();
        var c: Connection = undefined;
        c.dbus_path = try allocator.dupe(u8, path);
        errdefer allocator.free(c.dbus_path);
        c.zone = null;
        c.autoconnect = true;
        c.autoconnect_ports = .default;
        c.metered = .default;
        c.autoconnect_priority = 0;
        c.controller = null;
        c.wireless = null;
        c.interface_name = null;

        c.filename = try conn.getAlloc(allocator, "Filename", dbus.String);
        errdefer allocator.free(c.filename);
        const result = try conn.call("GetSettings", .{}, .{});
        defer result.deinit();
        const settings = result.next(dbus.Dict(
            dbus.String,
            dbus.Dict(
                dbus.String,
                dbus.AnyVariant,
            ),
        ));
        const eql = std.mem.eql;
        for (settings) |sett| {
            if (eql(u8, sett.key, "connection")) {
                for (sett.value) |con| {
                    const key = con.key;
                    if (eql(u8, key, "id")) {
                        c.id = try allocator.dupe(u8, con.value.as(dbus.String));
                    } else if (eql(u8, key, "type")) {
                        c.type = defines.ConnectionType.parse(con.value.as(dbus.String));
                    } else if (eql(u8, key, "zone")) {
                        c.zone = try allocator.dupe(u8, con.value.as(dbus.String));
                    } else if (eql(u8, key, "interface-name")) {
                        c.interface_name = try allocator.dupe(u8, con.value.as(dbus.String));
                    } else if (eql(u8, key, "autoconnect")) {
                        c.autoconnect = con.value.as(dbus.Boolean);
                    } else if (eql(u8, key, "autoconnect-ports")) {
                        const v = con.value.as(dbus.Int32);
                        if (v == -1) {
                            c.autoconnect_ports = .default;
                        } else if (v == 0) {
                            c.autoconnect_ports = .false;
                        } else if (v == 1) {
                            c.autoconnect_ports = .true;
                        } else @panic("unsupported autoconnect-ports value");
                    } else if (eql(u8, key, "metered")) {
                        // true/yes/on、false/no/off、default/unknown
                        const v = con.value.as(dbus.String);
                        if (eql(u8, v, "true") or eql(u8, v, "yes") or eql(u8, v, "on")) {
                            c.metered = .yes;
                        } else if (eql(u8, v, "false") or eql(u8, v, "no") or eql(u8, v, "off")) {
                            c.metered = .no;
                        } else if (eql(u8, v, "default") or eql(u8, v, "unknown")) {
                            c.metered = .default;
                        } else @panic("unsupported metered value");
                    } else if (eql(u8, key, "autoconnect-priority")) {
                        const v = con.value.as(dbus.Int32);
                        c.autoconnect_priority = v;
                    } else if (eql(u8, key, "controller")) {
                        c.controller = try allocator.dupe(u8, con.value.as(dbus.String));
                    }
                }
            } else if (eql(u8, sett.key, "802-11-wireless")) {
                var wireless: Wireless = undefined;
                wireless.bssid = null;
                wireless.ssid = null;
                wireless.hidden = false;
                wireless.mode = .infrastructure;
                wireless.powersave = .default;
                for (sett.value) |wirl| {
                    const key = wirl.key;
                    if (eql(u8, key, "band")) {
                        // TODO: what about Wi-Fi 6E?
                        const band = wirl.value.as(dbus.String);
                        if (eql(u8, band, "bg")) {
                            wireless.band = .@"2.4GHz";
                        } else if (eql(u8, band, "a")) {
                            wireless.band = .@"5GHz";
                        } else @panic("unsupported band value");
                    } else if (eql(u8, key, "bssid")) {
                        const bssid = wirl.value.as(dbus.Array(dbus.Byte));
                        wireless.bssid = try allocator.dupe(u8, bssid);
                    } else if (eql(u8, key, "hidden")) {
                        wireless.hidden = wirl.value.as(dbus.Boolean);
                    } else if (eql(u8, key, "mode")) {
                        const mode = wirl.value.as(dbus.String);
                        if (eql(u8, mode, "infrastructure")) {
                            wireless.mode = .infrastructure;
                        } else if (eql(u8, mode, "adhoc")) {
                            wireless.mode = .adhoc;
                        } else if (eql(u8, mode, "ap")) {
                            wireless.mode = .ap;
                        } else if (eql(u8, mode, "mesh")) {
                            wireless.mode = .mesh;
                        } else @panic("unsupported mode value");
                    } else if (eql(u8, key, "powersave")) {
                        const powersave = wirl.value.as(dbus.Int32);
                        wireless.powersave = switch (powersave) {
                            0 => .default,
                            1 => .ignore,
                            2 => .disable,
                            3 => .enable,
                            else => @panic("unsupported powersave value"),
                        };
                    } else if (eql(u8, key, "ssid")) {
                        const ssid = wirl.value.as(dbus.Array(dbus.Byte));
                        wireless.ssid = try allocator.dupe(u8, ssid);
                    }
                }
                c.wireless = wireless;
            } else if (eql(u8, sett.key, "802-11-wireless-security")) {
                var s: Wireless.Security = .{
                    .@"key-mgmt" = .none,
                    .psk = null, // need permission
                };
                for (sett.value) |sec| {
                    const key = sec.key;
                    if (eql(u8, key, "key-mgmt")) {
                        const key_mgmt = sec.value.as(dbus.String);
                        if (eql(u8, key_mgmt, "none")) {
                            s.@"key-mgmt" = .none;
                        } else if (eql(u8, key_mgmt, "ieee8021x")) {
                            s.@"key-mgmt" = .ieee8021x;
                        } else if (eql(u8, key_mgmt, "wpa-psk")) {
                            s.@"key-mgmt" = .@"wpa-psk";
                        } else if (eql(u8, key_mgmt, "wpa-eap")) {
                            s.@"key-mgmt" = .@"wpa-eap";
                        } else if (eql(u8, key_mgmt, "wpa-eap-suite-b-192")) {
                            s.@"key-mgmt" = .@"wpa-eap-suite-b-192";
                        } else if (eql(u8, key_mgmt, "sae")) {
                            s.@"key-mgmt" = .sae;
                        } else if (eql(u8, key_mgmt, "owe")) {
                            s.@"key-mgmt" = .owe;
                        } else @panic("unsupported security protocol");
                    }
                }
                c.wireless.?.security = s;
            }
        }

        return c;
    }
    pub fn deinit(self: Connection, allocator: Allocator) void {
        allocator.free(self.dbus_path);
        allocator.free(self.filename);
        allocator.free(self.id);
        if (self.zone) |zone| allocator.free(zone);
        if (self.interface_name) |interface_name| allocator.free(interface_name);
        if (self.controller) |controller| allocator.free(controller);
        if (self.wireless) |wireless| {
            if (wireless.bssid) |bssid| allocator.free(bssid);
            if (wireless.ssid) |ssid| allocator.free(ssid);
            if (wireless.security) |security| {
                if (security.psk) |psk| allocator.free(psk);
            }
        }
    }
};
pub const ActiveConnection = struct {
    dbus_path: []const u8,
    connection: Connection,
    default4: bool,
    default6: bool,
    devices: []Device,
    state: defines.ActiveConnectionState,
    state_flags: defines.ActiveConnectionStateFlags,
    specific_object: []const u8,
    ip4_config: ?IPConfig,
    ip6_config: ?IPConfig,
    type: defines.ConnectionType,
    pub fn init(allocator: Allocator, bus: *dbus.Bus, path: []const u8) !ActiveConnection {
        const active = try DBusHelper.init(bus, path, "org.freedesktop.NetworkManager.Connection.Active");
        defer active.deinit();
        var ac: ActiveConnection = undefined;
        ac.dbus_path = try allocator.dupe(u8, path);
        errdefer allocator.free(ac.dbus_path);
        ac.default4 = false;
        ac.default6 = false;
        ac.devices = try allocator.alloc(Device, 0);
        ac.state = .unknown;
        ac.state_flags = .{};
        ac.specific_object = "/";
        ac.ip4_config = null;
        ac.ip6_config = null;
        var conn: []const u8 = undefined;
        defer allocator.free(conn);
        conn = try active.getAlloc(allocator, "Connection", dbus.ObjectPath);
        ac.connection = try Connection.init(allocator, bus, conn);
        errdefer ac.connection.deinit(allocator);

        const devices = try active.get("Devices", dbus.Array(dbus.ObjectPath));
        defer devices.deinit();
        var ds = std.ArrayList(Device).init(allocator);
        defer ds.deinit();
        for (devices.value) |devicePath| {
            const d = try Device.init(allocator, bus, devicePath);
            errdefer d.deinit(allocator);
            try ds.append(d);
        }
        ac.devices = try ds.toOwnedSlice();

        const typ = try active.getAlloc(allocator, "Type", dbus.String);
        defer allocator.free(typ);
        ac.type = defines.ConnectionType.parse(typ);

        ac.default4 = try active.getBasic("Default", dbus.Boolean);
        ac.default6 = try active.getBasic("Default6", dbus.Boolean);
        ac.state = @enumFromInt(try active.getBasic("State", dbus.UInt32));
        ac.state_flags = defines.ActiveConnectionStateFlags.fromRaw(try active.getBasic("StateFlags", dbus.UInt32));
        ac.specific_object = try active.getAlloc(allocator, "SpecificObject", dbus.ObjectPath);

        const ip4_config = try active.getAlloc(allocator, "Ip4Config", dbus.ObjectPath);
        defer allocator.free(ip4_config);
        if (isVaildPath(ip4_config)) {
            ac.ip4_config = try IPConfig.init(allocator, bus, ip4_config);
        }
        const ip6_config = try active.getAlloc(allocator, "Ip6Config", dbus.ObjectPath);
        defer allocator.free(ip6_config);
        if (isVaildPath(ip6_config)) {
            ac.ip6_config = try IPConfig.init(allocator, bus, ip6_config);
        }
        return ac;
    }
    pub fn deinit(self: ActiveConnection, allocator: Allocator) void {
        for (self.devices) |device| device.deinit(allocator);
        allocator.free(self.devices);
        self.connection.deinit(allocator);
        allocator.free(self.dbus_path);
        allocator.free(self.specific_object);
        if (self.ip4_config) |ip4_config| ip4_config.deinit(allocator);
        if (self.ip6_config) |ip6_config| ip6_config.deinit(allocator);
    }
};
pub const AccessPoint = struct {
    bandwidth: u32,
    frequency: u32,
    hw_address: []const u8,
    max_bitrate: u32,
    last_seen: i32,
    mode: defines.@"80211Mode",
    rsn: []defines.@"80211ApSecurityFlags",
    wpa: []defines.@"80211ApSecurityFlags",
    ssid: []const u8,
    strength: u8,
    pub fn init(allocator: Allocator, bus: *dbus.Bus, path: []const u8) !AccessPoint {
        const ap = try DBusHelper.init(bus, path, "org.freedesktop.NetworkManager.AccessPoint");
        defer ap.deinit();
        var a: AccessPoint = undefined;
        a.bandwidth = 0;
        a.frequency = 0;
        a.hw_address = "";
        a.max_bitrate = 0;
        a.last_seen = 0;
        a.mode = .unknown;
        a.rsn = &.{};
        a.wpa = &.{};
        a.ssid = "";
        a.strength = 0;

        a.bandwidth = try ap.getBasic("Bandwidth", dbus.UInt32);
        a.frequency = try ap.getBasic("Frequency", dbus.UInt32);
        a.hw_address = try ap.getAlloc(allocator, "HwAddress", dbus.String);
        errdefer allocator.free(a.hw_address);
        a.max_bitrate = try ap.getBasic("MaxBitrate", dbus.UInt32);
        a.last_seen = try ap.getBasic("LastSeen", dbus.Int32);
        a.mode = @enumFromInt(try ap.getBasic("Mode", dbus.UInt32));

        const rsn_flags = try ap.getBasic("RsnFlags", dbus.UInt32);
        a.rsn = try defines.@"80211ApSecurityFlags".parse(allocator, rsn_flags);
        errdefer allocator.free(a.rsn);

        const wpa_flags = try ap.getBasic("WpaFlags", dbus.UInt32);
        a.wpa = try defines.@"80211ApSecurityFlags".parse(allocator, wpa_flags);
        errdefer allocator.free(a.wpa);

        a.ssid = try ap.getAlloc(allocator, "Ssid", dbus.Array(dbus.Byte));
        errdefer allocator.free(a.ssid);
        a.strength = try ap.getBasic("Strength", dbus.Byte);
        return a;
    }
    pub fn deinit(self: AccessPoint, allocator: Allocator) void {
        allocator.free(self.hw_address);
        allocator.free(self.ssid);
        allocator.free(self.rsn);
        allocator.free(self.wpa);
    }
};
const IP = struct {
    address: []const u8,
    prefix: u32,
};
const IPConfig = struct {
    addresses: []IP,
    gateway: []const u8,
    pub fn init(allocator: Allocator, bus: *dbus.Bus, path: []const u8) !IPConfig {
        var iface = "org.freedesktop.NetworkManager.IP4Config";
        if (std.mem.startsWith(u8, path, "/org/freedesktop/NetworkManager/IP6Config")) {
            iface = "org.freedesktop.NetworkManager.IP6Config";
        }
        const ipcfg = try DBusHelper.init(bus, path, iface);
        defer ipcfg.deinit();
        const addressData = try ipcfg.get("AddressData", dbus.Array(dbus.Vardict));
        defer addressData.deinit();
        var addresses = try allocator.alloc(IP, addressData.value.len);
        for (addressData.value, 0..) |data, i| {
            const ip = data[0].value.as(dbus.String);
            const prefix = data[1].value.as(dbus.UInt32);
            addresses[i] = .{
                .address = try allocator.dupe(u8, ip),
                .prefix = prefix,
            };
        }
        errdefer allocator.free(addresses);
        errdefer for (addresses) |ip| allocator.free(ip.address);

        const gateway = try ipcfg.getAlloc(allocator, "Gateway", dbus.String);
        return .{
            .addresses = addresses,
            .gateway = gateway,
        };
    }
    pub fn deinit(self: IPConfig, allocator: Allocator) void {
        for (self.addresses) |ip| allocator.free(ip.address);
        allocator.free(self.addresses);
        allocator.free(self.gateway);
    }
};
