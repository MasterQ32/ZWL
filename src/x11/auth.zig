const std = @import("std");
const builtin = @import("builtin");

pub fn getCookie(path: ?[]const u8) ![16]u8 {
    const xauth_file = blk: {
        if (path) |p| {
            break :blk try std.fs.openFileAbsolute(p, .{ .read = true, .write = false });
        } else if (builtin.os.tag == .windows) {
            const xauthority = std.os.getenvW(std.unicode.utf8ToUtf16LeStringLiteral("XAUTHORITY")) orelse return error.XAuthorityNotSpecified;
            break :blk try std.fs.openFileAbsoluteW(xauthority, .{ .read = true, .write = false });
        } else {
            if (std.os.getenv("XAUTHORITY")) |xafn| {
                break :blk try std.fs.openFileAbsolute(xafn, .{ .read = true, .write = false });
            }
            const home = std.os.getenv("HOME") orelse return error.HomeDirectoryNotFound;
            var fnbuf: [256]u8 = undefined;
            const fname = try std.fmt.bufPrint(fnbuf[0..], "{}/.Xauthority", .{home});
            break :blk try std.fs.openFileAbsolute(fname, .{ .read = true, .write = false });
        }
    };
    defer xauth_file.close();
    var rbuf = std.io.bufferedReader(xauth_file.reader());
    var reader = rbuf.reader();

    while (true) {
        const family = reader.readIntBig(u16) catch |err| switch (err) {
            error.EndOfStream => return error.MitMagicCookieNotInXauthority,
            else => return err,
        };

        const addr_len = try reader.readIntBig(u16);
        try reader.skipBytes(addr_len, .{ .buf_size = 64 });
        const num_len = try reader.readIntBig(u16);
        try reader.skipBytes(num_len, .{ .buf_size = 64 });
        const name_len = try reader.readIntBig(u16);

        if (name_len != 18) {
            try reader.skipBytes(name_len, .{ .buf_size = 64 });
            const data_len = try reader.readIntBig(u16);
            try reader.skipBytes(data_len, .{ .buf_size = 64 });
            continue;
        }

        var nbuf: [18]u8 = undefined;
        _ = try reader.readAll(nbuf[0..]);
        if (!std.mem.eql(u8, nbuf[0..], "MIT-MAGIC-COOKIE-1")) {
            const data_len = try reader.readIntBig(u16);
            try reader.skipBytes(data_len, .{ .buf_size = 64 });
            continue;
        }

        const data_len = try reader.readIntBig(u16);
        if (data_len != 16) return error.CorruptXauthorityFile;

        var xauth_data: [16]u8 = undefined;
        _ = try reader.read(xauth_data[0..]);
        return xauth_data;
    }
}
