const vaxis = @import("vaxis");
const std = @import("std");

const db     = @import("../db/database.zig");
const search = @import("../util/fuzzy.zig");

const pckg_list_pane = @import("../panes/package_list.zig");
const info_pane = @import("../panes/info.zig");
const graph_pane = @import("../panes/dep_tree.zig");

pub const EditorMode = enum(u8) {
    NORMAL = 0,
    SEARCH = 1,
};

pub const Panes = enum(u8) {
    LIST_PANE  = 0,
    // Info pane is skipped as it has no scrollable items.
    GRAPH_PANE = 1,
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
    if(end_y <= start_y or (x < 0) or (end_y < 0) ) return;

    const cell = vaxis.Cell{
        .char = .{.grapheme = "│", .width = 1 },
        .style = .{.dim = true},
    };

    var win: vaxis.Window = vx.window();

    var y: u16 = @intCast(start_y);
    while(y < end_y) : (y += 1) {
        const col: u16 = @intCast(x);
        win.writeCell(col, y, cell);
    }
}

fn render_header(vx: *vaxis.Vaxis, total_pckgs_amount: u64, total_size: u64, frame_aloc: std.mem.Allocator) !void {

    var win = vx.window();

    const header_win = win.child(.{
        .x_off = 2, .y_off = 1,
        .width = win.width -| 2, .height = 1,
    });

    const title = vaxis.Segment{
        .text = "pak | ",
        .style = .{.bold = true},
    };

    const total_pckg_amount_str = try std.fmt.allocPrint(frame_aloc, "{d} packages | ", .{total_pckgs_amount} );
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

    const total_size_str = try std.fmt.allocPrint(frame_aloc,"Total Size: {d:.2} {s}", .{data_size, size_suffix});
    const total_size_seg = vaxis.Segment{
        .text = total_size_str,
        .style = .{.bold = true},
    };

    _ = header_win.print(&.{title, pckg_amount_seg, total_size_seg}, .{});
}

fn render_footer(vx: *vaxis.Vaxis, search_term: []const u8, mode: EditorMode) !void {

    var win = vx.window();

    const footer_win = win.child(.{
        .x_off = 2, .y_off = win.height -| 1,
        .width = win.width -| 2, .height = 1,
    });

    const instruction = vaxis.Segment{
        .text = "[q]uit ",
        .style = .{.dim = true},
    };

    var search_seg = vaxis.Segment{
        .text = "[f]ind ",
        .style     = .{.dim = true},
    };

    const name_sort_seg = vaxis.Segment{
        .text = "[n]ame sort ",
        .style     = .{.dim = true},
    };

    const size_sort_seg = vaxis.Segment{
        .text = "[s]ize sort ",
        .style     = .{.dim = true},
    };

    const vert_move_seg = vaxis.Segment{
        .text = "[↑/↓] Scroll ",
        .style     = .{ .dim = true},
    };

    const horizontal_mov_Seg = vaxis.Segment{
        .text = "[←/→] Switch Pane ",
        .style     = .{ .dim = true },
    };

    const node_op_seg = vaxis.Segment{
        .text = "[SPACE] Open/close Graph Node ",
        .style     = .{ .dim = true },
    };

    if(search_term.len > 0 or mode == .SEARCH) {
        var search_slice_buf: [255]u8 = undefined;
        const search_slice = try std.fmt.bufPrint(&search_slice_buf, "[f]ind: {s} | ", .{search_term});

        search_seg.text = search_slice;
        search_seg.style = .{.bold = true};
    }

    _ = footer_win.print(&.{instruction, vert_move_seg, horizontal_mov_Seg, search_seg, name_sort_seg, size_sort_seg, node_op_seg}, .{});
}

pub fn render_tui(vx: *vaxis.Vaxis, tty: *vaxis.Tty, data: []const db.Package, total_size: u64, total_pckgs_amount: u64, scroll: u32, cursor: u32,
                  search_term: []const u8, mode: EditorMode, database: *db.Database, tree: *std.ArrayList(graph_pane.TreeNode), cur_pane: Panes,
                  graph_cursor: u32, graph_scroll: u32) !void {

    var win = vx.window();
    win.clear();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const bar1_x: u32  = (win.width / 4) + 2;           // 25% mark
    const bar2_x: u32  = (win.width * 6) / 10;    // 60% mark
    const pane1_w: u32 = bar1_x -| 2;
    const pane2_w: u32 = bar2_x -| bar1_x -| 2;


    draw_vertical_bar(vx, @intCast(bar1_x), 3, vx.window().height -| 1);
    draw_vertical_bar(vx, @intCast(bar2_x), 3, vx.window().height -| 1);

    if(cursor >= 0 and cursor < data.len and data.len > 0) {
        try pckg_list_pane.draw_packages_pane(vx, &arena, data, scroll, cursor, pane1_w, cur_pane == .LIST_PANE);

        const package: db.Package = database.pckgs.items[data[cursor].id];
        try info_pane.draw_pckg_info_pane(vx, arena.allocator(), package, database, bar1_x + 1, pane2_w);

        try graph_pane.render_graph_pane(vx, arena.allocator(), tree.items, database, bar2_x + 2, 3,
                                        graph_cursor, graph_scroll, cur_pane == .GRAPH_PANE);
    }

    try render_header(vx, total_pckgs_amount, total_size, arena.allocator());
    try render_footer(vx, search_term, mode);

    try vx.render(tty.writer());
}
