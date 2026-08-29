const std = @import("std");
const Io = std.Io;

const vaxis = @import("vaxis");

const pak   = @import("pak");
const db    = @import("db/database.zig");
const parse = @import("db/parse.zig");
const tui   = @import("tui/tui.zig");
const fuzz  = @import("util/fuzzy.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const aloc = arena.allocator();
    defer arena.deinit();

    const io = init.io;
    const map = init.environ_map;

    const database = try parse.get_pckgs_list(io, aloc);

    //for(database.pckgs.items, 0..) |pckg, i| {
    //    std.debug.print("[{d}] Package: {s} | Deps: ", .{i, pckg.name});
    //
    //    for(pckg.deps) |dep_id| {
    //        std.debug.print("{s} ", .{database.pckgs.items[dep_id].name});
    //    }
    //
    //    std.debug.print("\n", .{});
    //}

    var buff: [1024]u8 = undefined;
    var tty = try vaxis.tty.Tty.init(io, &buff);
    defer tty.deinit();

    var vx = try vaxis.Vaxis.init(io, aloc, map, .{});
    defer vx.deinit(aloc, tty.writer());

    const win = vx.window();
    var vis_rows: u32 = win.height -| 4;

    try tui.init_tui(&vx, &tty);

    var loop: vaxis.Loop(vaxis.Event) = .init(io, &tty, &vx);
    try loop.start();

    defer loop.stop();


    // For things such as scroll and max scroll
    var scroll: u32      = 0;
    var max_scroll: u32  = 0;
    var cursor: u32      = 0;
    var mode = tui.EditorMode.NORMAL;

    var search_buff = try std.ArrayList(u8).initCapacity(aloc, 255);
    var need_refilter: bool      = false;

    var pckgs_list = try fuzz.fuzzy_find(aloc, search_buff.items, database.pckgs.items);

    var count: u32    = @intCast(pckgs_list.len);

    max_scroll = @intCast(database.pckgs.items.len);

    var is_running: bool = true;
    while (is_running) {
        need_refilter = false;

        try tui.render_tui(&vx, &tty, pckgs_list, database.total_size, database.pckgs.capacity, 
        scroll, cursor, search_buff.items, mode);


        const event = try loop.nextEvent();
        switch (event) {
            .winsize => |ws| {
                try vx.resize(aloc, tty.writer(), ws);
                if(vis_rows == 0) vis_rows = vx.window().height -| 4;
            },
            .key_press => |key| {

                if(mode == .SEARCH) {

                    if(key.matches(vaxis.Key.escape, .{})) {
                        mode = .NORMAL;
                        search_buff.clearRetainingCapacity();
                        need_refilter = true;
                    }
                    if(key.matches(vaxis.Key.enter, .{})) {
                        mode = .NORMAL;
                    }
                    if(key.matches(vaxis.Key.backspace, .{})) {
                        _ = search_buff.pop();
                        need_refilter = true;
                    }
                    if((key.codepoint < 128 and std.ascii.isAlphabetic(@intCast(key.codepoint)) or key.matches('[', .{}) or key.matches(']', .{})
                        or key.matches('!', .{}))) {

                        try search_buff.append(aloc, @intCast(key.codepoint));
                        need_refilter = true;
                    }

                }

                if(mode == .NORMAL) {

                    if(key.matches('q', .{}) or key.matches('Q', .{})) {
                        is_running = false;
                        break;
                    }

                    if(key.matches('s', .{}) or key.matches('S', .{})) {
                        mode = .SEARCH;
                    }

                    if(key.matches(vaxis.Key.down, .{})) {
                        if(cursor < count - 1) cursor += 1;
                        if(cursor >= scroll + vis_rows) scroll = cursor - vis_rows + 1;
                    }
                    if(key.matches(vaxis.Key.up, .{})) {
                        cursor = cursor -| 1;
                        if(cursor < scroll) scroll = cursor;
                    }
                }
            },
            else => {},
        }

        if(need_refilter) {
            pckgs_list = try fuzz.fuzzy_find(aloc, search_buff.items, database.pckgs.items);
            count = @intCast(pckgs_list.len);

            // Just so the cursor does not go outside the list.
            cursor = 0;
        }
    }

    try tui.deinit_tui(&vx, &tty);
}

