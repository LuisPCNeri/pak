const std: type = @import("std");
const db: type  = @import("database.zig");

const pckg: type   = db.Package;
const reason: type = db.Reason;

const eql = std.mem.eql;

/// Iterates trhough the /var/lib/pacman/local directory and returns the number of packages there.
///
/// **Arguments**
/// - `io`: std.Io from std.process.Init.
///
/// **Returns**
/// The amount of packages installed or an error.
fn count_pckg_dirs(io: std.Io) !u32 {
    var count: u32 = 0;

    var dir = try std.Io.Dir.cwd().openDir(io, "/var/lib/pacman/local", .{ .iterate = true});
    defer dir.close(io);

    var iter = dir.iterate();

    while(try iter.next(io)) |entry| {
        if(entry.kind != .directory) continue;
        if(eql(u8, entry.name, "ALPM_DB_VERSION")) continue;

        count += 1;
    }

    return count;
}

/// Takes a string and removes the version constraint. To be used to resolve deps to their names only.
///
/// **Arguments**
/// - `dep`: The string to remove the version constraint from.
///
/// **Returns**
/// The string without the version constraint.
fn strip_version_constraint(dep: []const u8) []const u8 {
    for(dep, 0..) |c, i| {
        if(c == '>' or c == '<' or c == '=' or c == '!') return dep[0..i];
    }

    return dep;
}

/// Takes in a file and parses its contents into a pcgk struct.
/// Package dependencies will be stored as a raw []const u8 and not its id that will only be done in the 5 pass.
///
/// **Arguments**
/// - `io`: The initialized Io from the std.process.Init.
/// - `arena`: The arena allocator to stay until the process exits.
/// - `file`: The file to be parsed into a pckg struct.
/// - `pak`: A pointer to the pckg struct to be filled.
/// - `deps`: Array of an array of []const u8 to store all dependencies for all packages.
/// - `pckg_index`: Current index for the package being parsed.
/// - `dep_buf`: Temporary buffer to keep package dependencies until they are copied to deps.
/// - `opt_dep_buf`: Temporary buffer for OPTDEPENDS field.
/// - `provides_buf`: Temporary buffer for PROVIDES field.
/// - `temp_aloc`: Temporary alocator, should be the one used for deps, dep_buf, opt_dep_buf and provides_buf.
///
/// **Returns**
/// Nothing or an error.
fn parse_pckg(io: std.Io, arena: std.mem.Allocator ,file: *std.Io.File, pak: *pckg, deps: [][][]const u8, 
                pckg_index: u32, dep_buf: *std.ArrayList([]const u8), opt_dep_buf: *std.ArrayList([]const u8), provides_buf: *std.ArrayList([]const u8),
                temp_aloc: std.mem.Allocator) !void {

    var f_buffer: [8192]u8 = undefined;
    var reader = file.reader(io, &f_buffer);

    while(try reader.interface.takeDelimiter('\n')) |line| {

        if(eql(u8, line, "%NAME%")) {
            if(try reader.interface.takeDelimiter('\n')) |entry| {
                pak.name = try arena.dupe(u8, entry);
            }
        }

        if(eql(u8, line, "%VERSION%")) {
            if(try reader.interface.takeDelimiter('\n')) |entry| {
                pak.version = try arena.dupe(u8, entry);
            }
        }

        if(eql(u8, line, "%DESC%")) {
            if(try reader.interface.takeDelimiter('\n')) |entry| {
                pak.desc = try arena.dupe(u8, entry);
            }
        }

        if(eql(u8, line, "%SIZE%")) {
            if(try reader.interface.takeDelimiter('\n')) |entry| {
                pak.size = try std.fmt.parseInt(u64, entry, 10);
            }
        }

        if(eql(u8, line, "%DEPENDS%")) {
            while(try reader.interface.takeDelimiter('\n')) |entry| {

                // check string is not empty
                if(eql(u8, entry, "")) break;
                try dep_buf.append(temp_aloc, try arena.dupe(u8, strip_version_constraint(entry)));
            }
        }

        if(eql(u8, line, "%OPTDEPENDS%")) {

            while(try reader.interface.takeDelimiter('\n')) |entry| {

                if(eql(u8, entry, "")) break;
                try opt_dep_buf.append(temp_aloc, try arena.dupe(u8, entry));
            }
        }

        if(eql(u8, line, "%PROVIDES%")) {

            while(try reader.interface.takeDelimiter('\n')) |entry| {

                if(eql(u8, entry, "")) break;
                try provides_buf.append(temp_aloc,try arena.dupe(u8, entry));
            }
        }

        if(eql(u8, line, "%REASON%")) {
            if(try reader.interface.takeDelimiter('\n')) |entry| {
                pak.reason = @enumFromInt(try std.fmt.parseInt(u8, entry, 10));
            }
        }
    }

    deps[pckg_index] = try arena.dupe([]const u8, dep_buf.items);
    pak.opt_deps = try arena.dupe([]const u8, opt_dep_buf.items);
    pak.provides = try arena.dupe([]const u8, provides_buf.items);
}

/// Sorts the pckgs_lsit in place
///
/// **Arguments**
/// - `list`: A pointer to the list of installed packages.
///
/// **Returns**
/// Nothing or an error.
fn sort_pckgs_list(list: *std.ArrayList(pckg)) !void {

    std.mem.sort(pckg, list.items, {}, struct {
        fn lessThan(_: void, a: pckg, b: pckg) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lessThan);

}

/// Resolves the package dependencies from raw_deps into the dependencies' ids and inserts them to pckg.deps
///
/// **Arguments**
/// - `pckg_list`: Pointer to list of installed packages.
/// - `raw_deps`: Array of an array of []const u8 slices that are the names of a packages dependencies.
/// - `name_index`: Pointer to a StringHashMap(u32) that maps the name of all packages to their id, MAPS TO THEIR SORTED IDS.
/// - `provides_index`: Same as name_index but for the provides field in the struct.
/// - `temp_aloc`: Temporary allocator for the temp arrays and arraylists here in the parser.
/// - `arena`: Arena allocator that lives for as long as the process.
///
/// **Returns**
/// Nothing or an error.
fn resolve_pckg_deps(pckg_list: *std.ArrayList(pckg), raw_deps: [][][]const u8 , names_index: *std.StringHashMap(u32),
                        provides_index: *std.StringHashMap(u32), temp_aloc: std.mem.Allocator, arena: std.mem.Allocator) !void {

    var deps_buf = try std.ArrayList(u32).initCapacity(temp_aloc, pckg_list.items.len);

    for(pckg_list.items) |*pak| {
        deps_buf.clearRetainingCapacity();

        for(raw_deps[pak.parse_idx]) |dep_name| {

            const dep_id = names_index.get(dep_name)
                orelse provides_index.get(dep_name)
                orelse continue;

            try deps_buf.append(temp_aloc, dep_id);
        }

        pak.deps = try arena.dupe(u32, deps_buf.items);
    }

    var req_by_buf = try temp_aloc.alloc(std.ArrayList(u32), pckg_list.items.len);
    for(req_by_buf) |*buf| buf.* = try std.ArrayList(u32).initCapacity(temp_aloc, pckg_list.items.len);

    for(pckg_list.items) |*pak| {
        for(pak.deps) |dep_id| {
            try req_by_buf[dep_id].append(temp_aloc, pak.id);
        }
    }

    for(pckg_list.items) |*pak| {
        pak.required_by = try arena.dupe(u32, req_by_buf[pak.id].items);
    }

}

/// Iterates through the /var/lib/pacman/local directory and populates an array list with all the installed packages.
///
/// **Arguments**
/// - `io`: std.Io initialized in main with std.process.Init
/// - `aloc`: The arena allocator used until the process exits.
///
/// **Returns**
/// An arraylist with all the installed packages or an error.
pub fn get_pckgs_list(io: std.Io, aloc: std.mem.Allocator) !db.Database {

    const pckg_count = try count_pckg_dirs(io);

    var database = try db.Database.init_database(aloc, pckg_count);

    var temp_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const temp_aloc = temp_arena.allocator();

    const raw_deps = try temp_aloc.alloc([][]const u8, pckg_count);

    var dep_buf      = try std.ArrayList([]const u8).initCapacity(temp_aloc, pckg_count);
    var opt_dep_buf  = try std.ArrayList([]const u8).initCapacity(temp_aloc, pckg_count);
    var provides_buf = try std.ArrayList([]const u8).initCapacity(temp_aloc, pckg_count);


    var dir = try std.Io.Dir.cwd().openDir(io, "/var/lib/pacman/local", .{ .iterate = true});
    defer dir.close(io);

    var iter = dir.iterate();
    var pckg_idx: u32 = 0;

    while(try iter.next(io)) |entry| {
        if(entry.kind != .directory) continue;
        if(eql(u8, entry.name, "ALPM_DB_VERSION")) continue;

        var pckg_dir = try dir.openDir(io, entry.name, .{});
        var pckg_file = try pckg_dir.openFile(io, "desc", .{});

        var pak = std.mem.zeroes(pckg);
        try parse_pckg(io, aloc, &pckg_file, &pak, raw_deps, pckg_idx, 
                    &dep_buf, &opt_dep_buf,&provides_buf, temp_aloc);

        pak.parse_idx = pckg_idx;
        try database.pckgs.append(aloc, pak);

        database.total_size += pak.size;

        dep_buf.clearRetainingCapacity();
        opt_dep_buf.clearRetainingCapacity();
        provides_buf.clearRetainingCapacity();

        pckg_file.close(io);
        pckg_dir.close(io);

        pckg_idx += 1;
    }

    try sort_pckgs_list(&database.pckgs);
    for(database.pckgs.items, 0..) |*pak, i| {
        pak.id = @intCast(i);
    }

    for(database.pckgs.items) |pak| {
        try database.names_index.put(pak.name, pak.id);

        for(pak.provides) |virt| {
            try database.provides_index.put(virt, pak.id);
        }
    }

    try resolve_pckg_deps(&database.pckgs, raw_deps, &database.names_index, 
    &database.provides_index, temp_aloc, aloc);

    return database;
}
