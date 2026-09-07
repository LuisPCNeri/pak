const std   = @import("std");
const vaxis = @import("vaxis");
const ets   = @import("../db/algorithms.zig");
const db    = @import("../db/database.zig");

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

pub fn render_rsim_overlay(vx: *vaxis.Vaxis, pckg_id: u32, database: *db.Database, aloc: std.mem.Allocator) !void {

    const package = database.pckgs.items[pckg_id];

    var win = vx.window();
    const overlay = win.child(.{
        .border = .{ .style = .{ .fg = .{ .index = 255 } }, .where = .all },
        .height = win.height / 2,
        .width  = win.width / 2,
        .x_off   = (win.width / 2) - (win.width / 4),
        .y_off   = (win.height / 2) - (win.height / 4),
    });

    overlay.fill(.{ .style = .{ .bg = .{ .index = 234 } } });


    var lines = try std.ArrayList([]const u8).initCapacity(aloc, 1);
    defer lines.deinit(aloc);

    try lines.append(aloc, try std.fmt.allocPrint(aloc, "Removal Sim for: {s}", .{package.name}));

    const size = try ets.exclusive_transitive_size(pckg_id, database, aloc);
    var size_f: f64 = @floatFromInt(size);

    const size_suffixes = [_][]const u8{"KiB", "MiB", "GiB"};
    var suffix: []const u8 = "B";

    var i: u8 = 0;
    while(size_f > 1024 and i < 3) : (i += 1) {
        size_f /= 1024;
        suffix  = size_suffixes[i];
    }

    try lines.append(aloc, try std.fmt.allocPrint(aloc, "Total Removed Size: {d:.2} {s}", .{size_f, suffix}));

    var ids = try std.ArrayList(u32).initCapacity(aloc, 1);
    defer ids.deinit(aloc);

    try ets.get_exclusive_pckgs(pckg_id, database, aloc, &ids);

    const prefix         = try std.fmt.allocPrint(aloc, "Packages ({d}): ", .{ids.items.len});
    const rem_deps = try reverse_resolve_ids(aloc, ids.items, database, prefix);

    try lines.append(aloc, rem_deps);

    var row: u32 = 1;
    for(lines.items) |line| {

        if(row == 3) {
            row -= 1;

            var col: u16 = 0;
            while (col < overlay.width -| 2) : (col += 1) {

                const cell = overlay.child(.{
                    .x_off = 1 + col,
                    .y_off = @intCast(row),
                    .width = 1,
                    .height = 1,
                });
                _ = cell.printSegment(.{ .text = "─", .style = .{ .bg = .{ .index = 234 } } }, .{});
            }

            row += 2;
        }

        const row_u16: u16 = @intCast(row);
        const w = overlay.child(.{
            .height = overlay.height -| row_u16 -| 1, .width = overlay.width -| 4,
            .x_off   = 2, .y_off  = @intCast(row),
        });

        _ = w.printSegment(.{.text = line, .style = .{ .bg = .{ .index = 234 } }}, .{.wrap = .word});
        row += 2;
    }

}
