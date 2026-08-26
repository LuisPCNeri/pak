const std = @import("std");
const Io = std.Io;

const vaxis = @import("vaxis");

const pak = @import("pak");
const db = @import("db/database.zig");
const parse = @import("db/parse.zig");
const tui = @import("tui/tui.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const aloc = arena.allocator();
    defer arena.deinit();

    const io = init.io;
    const map = init.environ_map;

    var database = try parse.get_pckgs_list(io, aloc);
    for(database.pckgs.items, 0..) |pckg, i| {
        std.debug.print("[{d}] Package: {s} | Deps: ", .{i, pckg.name});

        for(pckg.deps) |dep_id| {
            std.debug.print("{s} ", .{database.pckgs.items[dep_id].name});
        }

        std.debug.print("\n", .{});
    }


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
    var scroll: u32     = 0;
    var max_scroll: u32 = 0;
    var cursor: u32     = 0;

    const count: u32    = @intCast(database.pckgs.items.len);

    max_scroll = @intCast(database.pckgs.items.len);

    var is_running: bool = true;
    while (is_running) {

        try tui.render_tui(&vx, &tty, &database, scroll, cursor);


        const event = try loop.nextEvent();
        switch (event) {
            .winsize => |ws| {
                try vx.resize(aloc, tty.writer(), ws);
                if(vis_rows == 0) vis_rows = vx.window().height -| 4;
            },
            .key_press => |key| {
                if(key.matches('q', .{})) {
                    is_running = false;
                    break;
                }
                if(key.matches(vaxis.Key.down, .{})) {
                    if(cursor < count - 1) cursor += 1;
                    if(cursor >= scroll + vis_rows) scroll = cursor - vis_rows + 1;
                }
                if(key.matches(vaxis.Key.up, .{})) {
                    cursor = cursor -| 1;
                    if(cursor < scroll) scroll = cursor;
                }
            },
            else => {},
        }
    }

    try tui.deinit_tui(&vx, &tty);
}

