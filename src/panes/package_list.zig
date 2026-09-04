const vaxis = @import("vaxis");
const std = @import("std");
const db = @import("../db/database.zig");

pub fn draw_packages_pane(vx: *vaxis.Vaxis, arena: *std.heap.ArenaAllocator, pckgs: []const db.Package, scroll: u32, cursor: u32, w: u32, is_active: bool) !void {

    const frame_aloc = arena.allocator();

    const vis: i17   = vx.window().height -| 4;
    const count: u32 = @intCast(pckgs.len);

    if(vis < 0) return;
    const vis_usize: usize = @intCast(vis);

    for(0..vis_usize) |i| {

        if(scroll + i >= count) break;
        const pckg = pckgs[scroll + i];

        const is_selected: bool = (scroll + i) == cursor;

        var pckg_suffix: []const u8 = "[E]";
        if(pckg.reason == .dependency and pckg.required_by.len > 0)  pckg_suffix = "[S]";
        if(pckg.reason == .dependency and pckg.required_by.len == 0 and pckg.opt_req_by.len == 0) pckg_suffix = "[!]";


        var row_text = try frame_aloc.alloc(u8, 40);
        @memset(row_text, ' ');

        const name_len = @min(pckg.name.len, 40);
        @memcpy(row_text[1..name_len + 1], pckg.name[0..name_len]);

        if(pckg.name.len + pckg_suffix.len <= 40 - 1) {
            const right_start = 40 - pckg_suffix.len;
            @memcpy(row_text[(right_start - 1)..(row_text.len - 1)], pckg_suffix);
        }

        var seg = vaxis.Segment{
            .text = row_text,
        };

        if(is_selected and is_active) {
            seg.style = .{.bold = true, .bg = .{ .index = 6}, .fg = .{ .index = 0}};
        }
        if(is_selected and !is_active) {
            seg.style = .{.bold = true, .bg = .{ .index = 215}, .fg = .{ .index = 0}};
        }


        const n: i17 = @intCast(i);
        const pckg_win = vx.window().child(.{
            .x_off = 2, .y_off = 3 + n,
            .width = @intCast(w), .height = 1,
        });

        if(pckg_win.y_off == vx.window().height -| 1) break;

        _ = pckg_win.print(&.{seg}, .{});
    }
}
