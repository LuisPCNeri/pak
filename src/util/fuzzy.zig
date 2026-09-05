const std: type = @import("std");

const db: type   = @import("../db/database.zig");
const pckg: type = db.Package;

fn filter_orphans_only(temp_aloc: std.mem.Allocator, pckgs: []const pckg, match_list: *std.ArrayList(pckg)) !void {

    if(match_list.items.len > 0) match_list.clearRetainingCapacity();

    for(pckgs) |package| {
        if(package.reason == .dependency and package.required_by.len == 0 and package.opt_req_by.len == 0) try match_list.append(temp_aloc, package);
    }

}

fn filter_deps_only(temp_aloc: std.mem.Allocator, pckgs: []const pckg, match_list: *std.ArrayList(pckg)) !void {

    if(match_list.items.len > 0) match_list.clearRetainingCapacity();

    for(pckgs) |package| {
        if(package.reason == .dependency and package.required_by.len > 0) try match_list.append(temp_aloc, package);
    }

}

fn has_substring(needle: []const u8, haystack: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

/// Replaces the current match_list with a new one by clearing it and rebuilding it.
///
/// **Arguments**
/// - temp_aloc:  An allocator to be used for this operation.
/// - term:       The substring to search for.
/// - pckgs:      List of all packages to be matched against the substring.
/// - match_list: Pointer to an array list of db.Package which will be cleared and the new list will be built on.
pub fn fuzzy_find(temp_aloc: std.mem.Allocator, term: []const u8, pckgs: []const pckg, match_list: *std.ArrayList(pckg)) !void {

    if(match_list.items.len > 0) match_list.clearRetainingCapacity();

    if(term.len == 0 or std.mem.eql(u8, term, "\n") or std.mem.eql(u8, term, " ")) {
        try match_list.appendSlice(temp_aloc, pckgs);
        return;
    }

    if(std.mem.eql(u8, term, "[!]")) {
        try filter_orphans_only(temp_aloc, pckgs, match_list);
        return;
    }

    if(std.mem.eql(u8, term, "[S]")) {
        try filter_deps_only(temp_aloc, pckgs, match_list);
        return;
    }

    for(pckgs) |package| {
        if( package.name.len < term.len ) continue;
        if( has_substring(term, package.name) ) try match_list.append(temp_aloc, package);
    }
}

/// Sorts the package list in place by package name.
///
/// **Arguments**
/// - list: The package list to sort.
pub fn sort_by_pckg_size(list: []db.Package) void {

    std.mem.sort(db.Package, list, {}, struct {
        fn greaterThan(_: void, a: db.Package, b: db.Package) bool {
            return a.size > b.size;
        }
    }.greaterThan);
}

/// Sorts the package list in place by package size.
///
/// **Arguments**
/// - list: The package list to sort.
pub fn sort_by_pckg_name(list: []db.Package) void {

    std.mem.sort(pckg, list, {}, struct {
        fn lessThan(_: void, a: db.Package, b: db.Package) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lessThan);
}
