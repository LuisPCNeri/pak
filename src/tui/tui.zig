const vaxis = @import("vaxis");
const std = @import("std");

const db     = @import("../db/database.zig");
const search = @import("../util/fuzzy.zig");

pub const EditorMode = enum(u8) {
    NORMAL = 0,
    SEARCH = 1,
};

pub fn init_tui(vx: *vaxis.Vaxis, tty: *vaxis.Tty) !void {

    try vx.enterAltScreen(tty.writer());
    try vx.setMouseMode(tty.writer(), false);
}

pub fn deinit_tui(vx: *vaxis.Vaxis, tty: *vaxis.Tty) !void {

    try vx.setMouseMode(tty.writer(), true);
    try vx.exitAltScreen(tty.writer());
}

fn draw_vertical_bar(vx: *vaxis.Vaxis, x: i17, start_y: usize, end_y: usize) void {
    if(end_y <= start_y) return;

    const bar_seg = vaxis.Segment{
        .text = "|",
        .style = .{.dim = true},
    };

    for(start_y..end_y) |y| {

        const y_off: i17 = @intCast(y);
        const bar_win = vx.window().child(.{
            .x_off = x, .y_off = y_off,
            .width = 1, .height = 1,
        });

        _ = bar_win.print(&.{bar_seg}, .{});

    }
}

fn draw_packages_pane(vx: *vaxis.Vaxis, arena: *std.heap.ArenaAllocator, pckgs: []const db.Package, scroll: u32, cursor: u32) !void {

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

        if(is_selected) {
            seg.style = .{.bold = true, .bg = .{ .index = 6}, .fg = .{ .index = 0}};
        }


        const n: i17 = @intCast(i);
        const pckg_win = vx.window().child(.{
            .x_off = 2, .y_off = 3 + n,
            .width = 40, .height = 1,
        });

        if(pckg_win.y_off == vx.window().height -| 1) break;

        _ = pckg_win.print(&.{seg}, .{});
    }
}

pub fn render_tui(vx: *vaxis.Vaxis, tty: *vaxis.Tty, data: []const db.Package, total_size: u64, total_pckgs_amount: u64, scroll: u32, cursor: u32,
                  search_term: []const u8, mode: EditorMode) !void {

    var win = vx.window();
    win.clear();

    const header_win = win.child(.{
        .x_off = 2, .y_off = 1,
        .width = win.width -| 2, .height = 1,
    });

    const footer_win = win.child(.{
        .x_off = 2, .y_off = win.height -| 1,
        .width = win.width -| 2, .height = 1,
    });

    const title = vaxis.Segment{
        .text = "pak | ",
        .style = .{.bold = true},
    };

    var buf: [128]u8 = undefined;

    const total_pckg_amount_str = try std.fmt.bufPrint(&buf, "{d} packages | ", .{total_pckgs_amount} );
    const pckg_amount_seg = vaxis.Segment{
        .text = total_pckg_amount_str,
        .style = .{.bold = true},
    };

    var data_size: f64 = @floatFromInt(total_size);
    data_size /= 1024.0;
    data_size /= 1024.0;

    var size_suffix: []const u8 = "MiB";
    if(data_size > 1024) {
        data_size /= 1024.0;
        size_suffix = "GiB";
    }

    const total_size_str = try std.fmt.bufPrint(buf[total_pckg_amount_str.len..],"Total Size: {d:.2} {s}", .{data_size, size_suffix});
    const total_size_seg = vaxis.Segment{
        .text = total_size_str,
        .style = .{.bold = true},
    };

    const instruction = vaxis.Segment{
        .text = "[q]uit ",
        .style = .{.dim = true},
    };

    var search_seg = vaxis.Segment{
        .text = "[s]earch",
        .style = .{.dim = true},
    };

    if(search_term.len > 0 or mode == .SEARCH) {
        var search_slice_buf: [255]u8 = undefined;
        const search_slice = try std.fmt.bufPrint(&search_slice_buf, "search: {s} |", .{search_term});

        search_seg.text = search_slice;
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    try draw_packages_pane(vx, &arena, data, scroll, cursor);
    draw_vertical_bar(vx, 45, 3, vx.window().height -| 1);

    _ = header_win.print(&.{title, pckg_amount_seg, total_size_seg}, .{});
    _ = footer_win.print(&.{instruction, search_seg}, .{});

    try vx.render(tty.writer());
}
