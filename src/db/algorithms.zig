const db  = @import("database.zig");
const std = @import("std");

fn dfs(root_pckg_id: u32, aloc: std.mem.Allocator, database: *db.Database, closure: *std.DynamicBitSet) !void {

    var stack = try std.ArrayList(u32).initCapacity(aloc, 1);
    defer stack.deinit(aloc);

    try stack.append(aloc, root_pckg_id);

    while(stack.items.len > 0) {

        const id = stack.pop() orelse continue;

        if(closure.isSet(id)) continue;
        closure.set(id);

        const package = database.pckgs.items[id];
        for(package.deps) |dep_id| {
            try stack.append(aloc, dep_id);
        }
    }
}

fn get_exclusive(root_pckg_id: u32 ,closure: *std.DynamicBitSet, exclusive: *std.ArrayList(u32), database: *db.Database, aloc: std.mem.Allocator) !void {

    if(exclusive.items.len > 0) exclusive.clearRetainingCapacity();

    var changed = true;
    while (changed) {

        changed = false;

        var iter = closure.iterator(.{});
        while(iter.next()) |id| {

            const id_u: u32 = @intCast(id);
            if(id_u == root_pckg_id) continue;

            const package = database.pckgs.items[id];

            if(package.reason == .explicit) {
                closure.unset(id_u);
                changed = true;
                continue;
            }

            var required_outside = false;
            for(package.required_by) |rev_dep| {
                if(!closure.isSet(@intCast(rev_dep))) {
                    required_outside = true;
                    break;
                }
            }

            if(required_outside) {
                closure.unset(id_u);
                changed = true;
            }

        }
    }

    var iter_final = closure.iterator(.{});
    while (iter_final.next()) |id| {
        try exclusive.append(aloc, @intCast(id));
    }
}

fn sum_exclusive_size(exclusive: *std.ArrayList(u32), database: *db.Database) u64 {

    var sum: u64 = 0;

    for(exclusive.items) |id| {

        const package = database.pckgs.items[id];
        sum += package.size;
    }

    return sum;
}

pub fn get_exclusive_pckgs(root_pckg_id: u32, database: *db.Database, aloc: std.mem.Allocator, out: *std.ArrayList(u32)) !void {

    var closure = try std.DynamicBitSet.initEmpty(aloc, database.pckgs.items.len);
    defer closure.deinit();

    try dfs(root_pckg_id, aloc, database, &closure);
    try get_exclusive(root_pckg_id, &closure, out, database, aloc);
}

pub fn exclusive_transitive_size(root_pckg_id: u32, database: *db.Database, aloc: std.mem.Allocator) !u64 {

    var closure = try std.DynamicBitSet.initEmpty(aloc, database.pckgs.items.len);
    defer closure.deinit();

    try dfs(root_pckg_id, aloc, database, &closure);

    var exclusive = try std.ArrayList(u32).initCapacity(aloc, 1);
    defer exclusive.deinit(aloc);

    try get_exclusive(root_pckg_id, &closure, &exclusive, database, aloc);

    return sum_exclusive_size(&exclusive, database);

}
