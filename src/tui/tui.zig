const vaxis = @import("vaxis");

const std = @import("std");

const db = @import("../db/database.zig");

pub fn init_tui(vx: *vaxis.Vaxis, tty: *vaxis.Tty) !void {

    try vx.enterAltScreen(tty.writer());
    try vx.setMouseMode(tty.writer(), false);
}

pub fn deinit_tui(vx: *vaxis.Vaxis, tty: *vaxis.Tty) !void {

    try vx.setMouseMode(tty.writer(), true);
    try vx.exitAltScreen(tty.writer());
}

pub fn render_tui(vx: *vaxis.Vaxis, tty: *vaxis.Tty, data: *db.Database) !void {

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

    const total_pckg_amount_str = try std.fmt.bufPrint(&buf, "{d} packages | ", .{data.pckgs.capacity} );
    const pckg_amount_seg = vaxis.Segment{
        .text = total_pckg_amount_str,
        .style = .{.bold = true},
    };

    var data_size: f64 = @floatFromInt(data.total_size);
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
        .text = "[q]uit",
        .style = .{.dim = true},
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const frame_aloc = arena.allocator();

    for(data.pckgs.items, 0..) |pckg, i| {

        var pckg_suffix: []const u8 = "[E]";
        if(pckg.reason == .dependency and pckg.required_by.len > 0)  pckg_suffix = "[S]";
        if(pckg.reason == .dependency and pckg.required_by.len == 0) pckg_suffix = "[!]";

        const pckg_str = try std.fmt.allocPrint(frame_aloc, "{s} {s}", .{pckg.name, pckg_suffix});

        const seg = vaxis.Segment{
            .text = pckg_str,
        };

        const n: i17 = @intCast(i);
        const pckg_win = win.child(.{
            .x_off = 2, .y_off = 2 + header_win.height + n,
            .width = 40, .height = 1,
        });

        if(pckg_win.y_off == footer_win.y_off) break;

        _ = pckg_win.print(&.{seg}, .{});
    }

    _ = header_win.print(&.{title, pckg_amount_seg, total_size_seg}, .{});
    _ = footer_win.print(&.{instruction}, .{});

    try vx.render(tty.writer());
}
