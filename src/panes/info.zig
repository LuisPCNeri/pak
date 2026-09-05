const vaxis = @import("vaxis");
const std = @import("std");
const db = @import("../db/database.zig");

fn reverse_resolve_ids(temp_aloc: std.mem.Allocator ,ids: []u32, data: *db.Database, prefix: []const u8) ![]const u8 {

    var buf = try std.ArrayList(u8).initCapacity(temp_aloc, 1);

    try buf.appendSlice(temp_aloc, prefix);
    for(ids, 0..) |id, i| {

        if(data.pckgs.items[id].id >= 0) {
            try buf.appendSlice(temp_aloc, data.pckgs.items[id].name);
            if(i < ids.len - 1) try buf.append(temp_aloc, ' ');
        }
    }

    const result: []const u8 = buf.items;
    return result;
}

pub fn draw_pckg_info_pane(vx: *vaxis.Vaxis, temp_aloc: std.mem.Allocator, pckg: db.Package, database: *db.Database, x: u32, w: u32) !void {

    if( w < 10 ) return;

    var win = vx.window();

    const base_pckg_info: []const u8 = try std.fmt.allocPrint(temp_aloc, "Name: {s}\nVersion: {s}\nDescription: {s}\nSize: {d} {s}",
                                                                .{pckg.name, pckg.version, pckg.desc, if (pckg.size > 1024) pckg.size / 1024 else pckg.size,
                                                                        if (pckg.size > 1024) "KiB" else "Bytes"});

    const pckg_deps       = try reverse_resolve_ids(temp_aloc, pckg.deps, database, "Dependencies: ");
    const pckg_opt_deps   = try reverse_resolve_ids(temp_aloc, pckg.opt_deps_ids, database, "Opt Depends: ");
    const pckg_req_by     = try reverse_resolve_ids(temp_aloc, pckg.required_by, database, "Required By: ");
    const pckg_opt_req_by = try reverse_resolve_ids(temp_aloc, pckg.opt_req_by, database, "Opt Req By: ");

    const pckg_info = try std.fmt.allocPrint(temp_aloc, "{s}\n\n{s}\n\n{s}\n\n{s}\n\n{s}",
                                            .{base_pckg_info, pckg_deps, pckg_opt_deps, pckg_req_by, pckg_opt_req_by});

    const x_i17: i17 = @intCast(x);
    const pckg_info_win = win.child(.{
        .x_off = x_i17 + 2, .y_off = 3,
        .width = @intCast(w), .height = win.height -| 4,
    });

    const pckg_info_seg = vaxis.Segment{
        .text = pckg_info,
    };

    _ = pckg_info_win.print(&.{pckg_info_seg}, .{.wrap = .word});
}
