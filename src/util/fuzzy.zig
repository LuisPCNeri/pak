const std: type = @import("std");

const db: type   = @import("../db/database.zig");
const pckg: type = db.Package;

fn filter_orphans_only(temp_aloc: std.mem.Allocator, pckgs: []const pckg) ![]pckg {

    var matches = try std.ArrayList(pckg).initCapacity(temp_aloc, pckgs.len);
    errdefer matches.deinit(temp_aloc);

    for(pckgs) |package| {
        if(package.reason == .dependency and package.required_by.len == 0 and package.opt_req_by.len == 0) try matches.append(temp_aloc, package);
    }

    return matches.items;
}

fn filter_deps_only(temp_aloc: std.mem.Allocator, pckgs: []const pckg) ![]pckg {

    var matches = try std.ArrayList(pckg).initCapacity(temp_aloc, pckgs.len);
    errdefer matches.deinit(temp_aloc);

    for(pckgs) |package| {
        if(package.reason == .dependency and package.required_by.len > 0) try matches.append(temp_aloc, package);
    }

    return matches.items;
}

fn has_substring(needle: []const u8, haystack: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

pub fn fuzzy_find(temp_aloc: std.mem.Allocator, term: []const u8, pckgs: []const pckg) ![]pckg {

    if(term.len == 0 or std.mem.eql(u8, term, "\n") or std.mem.eql(u8, term, " ")) {
        return try temp_aloc.dupe(pckg, pckgs);
    }

    var matches = try std.ArrayList(pckg).initCapacity(temp_aloc, pckgs.len);
    errdefer matches.deinit(temp_aloc);

    if(std.mem.eql(u8, term, "[!]")) {
        return try filter_orphans_only(temp_aloc, pckgs);
    }

    if(std.mem.eql(u8, term, "[S]")) {
        return try filter_deps_only(temp_aloc, pckgs);
    }

    for(pckgs) |package| {
        if( package.name.len < term.len ) continue;
        if( has_substring(term, package.name) ) try matches.append(temp_aloc, package);
    }

    return matches.items;
}

pub fn sort_by_pckg_size(list: []db.Package) void {

    std.mem.sort(db.Package, list, {}, struct {
        fn greaterThan(_: void, a: db.Package, b: db.Package) bool {
            return a.size > b.size;
        }
    }.greaterThan);
}

pub fn sort_by_pckg_name(list: []db.Package) void {

    std.mem.sort(pckg, list, {}, struct {
        fn lessThan(_: void, a: db.Package, b: db.Package) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lessThan);
}
