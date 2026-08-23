const std = @import("std");
const Io = std.Io;

const pak = @import("pak");
const db = @import("db/database.zig");
const parse = @import("db/parse.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const aloc = arena.allocator();
    defer arena.deinit();

    const io = init.io;

    const pckgs_list = try parse.get_pckgs_list(io, aloc);
    for(pckgs_list.items, 0..) |pckg, i| {
        std.debug.print("[{d}] Package: {s} | Deps: ", .{i, pckg.name});

        for(pckg.deps) |dep_id| {
            std.debug.print("{s} ", .{pckgs_list.items[dep_id].name});
        }

        std.debug.print("\n", .{});
    }
}

