
const std = @import("std");

pub const Reason: type = enum(u8) {
    explicit   = 0,
    dependency = 1,
};

pub const Package: type = struct {
    id:          u32,
    parse_idx:   u32,
    name:        []const u8,
    desc:        []const u8,
    version:     []const u8,
    size:        u64,
    deps:         []u32,
    required_by: []u32,
    provides:    [][]const u8,
    opt_deps:    [][]const u8,
    files_start: u32,
    files_count: u32,
    reason:      Reason = .explicit,
};

pub const Database: type = struct {

    arena:          std.mem.Allocator,
    pckgs:          std.ArrayList(Package),
    names_index:     std.StringHashMap(u32),
    provides_index: std.StringHashMap(u32),
    orphans:        std.ArrayList(u32),
    total_size:     u64,

    pub fn init_database(arena: std.mem.Allocator, pckg_count: u32) !Database {

        const name_index = std.StringHashMap(u32).init(arena);
        const provides_index = std.StringHashMap(u32).init(arena);

        const pckgs = try std.ArrayList(Package).initCapacity(arena, pckg_count);
        const orphans = try std.ArrayList(u32).initCapacity(arena, pckg_count);

        const db: Database = .{ .arena = arena,
            .pckgs = pckgs,
            .names_index = name_index,
            .provides_index = provides_index,
            .orphans = orphans,
            .total_size = 0,
        };

        return db;
    }
};
