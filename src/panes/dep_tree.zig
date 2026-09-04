const std   = @import("std");
const db    = @import("../db/database.zig");
const vaxis: type = @import("vaxis");

pub const TreeNode = struct {

    pckg_id:     u32,
    depth:       u32,
    is_expanded: bool,
    is_shared:   bool,
    is_cycle:    bool,
    is_optional: bool,

};

fn is_ancestor(tree: []TreeNode, current_index: usize, pckg_id: u32) bool {
    const depth = tree[current_index].depth;
    var i = current_index;

    while( i > 0 ) : (i -= 1) {

        if(tree[i].depth < depth) {
            if(tree[i].pckg_id == pckg_id) return true;
        }
    }

    return false;
}

fn is_last_sibling(tree: []TreeNode, idx: usize) bool {
    const depth = tree[idx].depth;

    if(idx + 1 >= tree.len) return true;
    return tree[idx + 1].depth < depth;
}

fn ancestor_is_last(tree: []TreeNode, idx: usize, target_depth: u8) bool {
    var i = idx;

    while( i > 0) : (i -= 1) {
        if(tree[i].depth == target_depth) return is_last_sibling(tree, i);
    }

    return false;
}

pub fn create_tree_from_root(frame_aloc: std.mem.Allocator ,root: db.Package, database: *db.Database) !std.ArrayList(TreeNode) {

    const root_node = TreeNode{
        .pckg_id      = root.id,
        .depth        = 0,
        .is_expanded = true,
        .is_shared   = root.required_by.len > 1,
        .is_cycle    = false,
        .is_optional = false,
    };

    var tree = try std.ArrayList(TreeNode).initCapacity(frame_aloc, 1);
    try tree.append(frame_aloc, root_node);

    for(root.deps) |dep_id| {

        const dep = database.pckgs.items[dep_id];
        const node = TreeNode{
            .pckg_id      = dep.id,
            .depth        = root_node.depth + 1,
            .is_expanded = false,
            .is_shared   = dep.required_by.len > 1,
            .is_cycle    = false,
            .is_optional = false,
        };

        try tree.append(frame_aloc, node);
    }

    for(root.opt_deps_ids) |dep_id| {

        const dep = database.pckgs.items[dep_id];
        const node = TreeNode{
            .pckg_id      = dep.id,
            .depth        = root_node.depth + 1,
            .is_expanded = false,
            .is_shared   = dep.required_by.len > 1,
            .is_cycle    = false,
            .is_optional = true,

        };

        try tree.append(frame_aloc, node);
    }

    return tree;
}

pub fn expand_node(frame_aloc: std.mem.Allocator, idx: u32, tree: *std.ArrayList(TreeNode), database: *db.Database) !void {

    const node = tree.items[idx];
    tree.items[idx].is_expanded = true;

    const children     = database.pckgs.items[node.pckg_id].deps;
    const opt_children = database.pckgs.items[node.pckg_id].opt_deps_ids;

    for(children, (idx + 1)..) |dep_id, in_pos| {
        try tree.insert(frame_aloc, in_pos, .{
            .pckg_id      = dep_id,
            .depth        = node.depth + 1,
            .is_expanded = false,
            .is_shared   = database.pckgs.items[dep_id].required_by.len > 1,
            .is_cycle    = is_ancestor(tree.items, idx, dep_id),
            .is_optional = false,
        });
    }

    for(opt_children, (idx + 1)..) |dep_id, in_pos| {
        try tree.insert(frame_aloc, in_pos, .{
            .pckg_id      = dep_id,
            .depth        = node.depth + 1,
            .is_expanded = false,
            .is_shared   = database.pckgs.items[dep_id].required_by.len > 1,
            .is_cycle    = is_ancestor(tree.items, idx, dep_id),
            .is_optional = true,
        });
    }
}

pub fn collapse_node(idx: u32, tree: *std.ArrayList(TreeNode)) !void {

    const node = tree.items[idx];
    tree.items[idx].is_expanded = false;

    while(idx + 1 < tree.items.len and tree.items[idx + 1].depth > node.depth) {
        _ = tree.orderedRemove(idx + 1);
    }
}

pub fn render_graph_pane(vx: *vaxis.Vaxis, frame_aloc: std.mem.Allocator, nodes: []TreeNode, database: *db.Database, pane_x: u32, pane_y: u32,
                         cursor: u32, scroll: u32, is_active: bool) !void {

    var win = vx.window();
    const vis = win.height -| 4;
    const vis_u: usize = @intCast(vis);

    for(0..vis_u) |i| {

        if(scroll + i >= nodes.len) break;

        const node = nodes[scroll + i];

        const pckg     = database.pckgs.items[node.pckg_id];
        const is_selected = (scroll + i) == cursor;

        var col: usize = 0;
        var d: u8      = 0;

        while(d < node.depth) : (d += 1) {
            if(d == node.depth - 1) {

                const connector = if(is_last_sibling(nodes, scroll + i)) "└─" else "├─";
                _ = win.print(&.{.{.text = connector}},
                .{.col_offset = @intCast(pane_x + col), .row_offset = @intCast(pane_y + i)});

            } else {

                const pipe = if(ancestor_is_last(nodes, scroll + i, d + 1)) "  " else "│ ";
                _ = win.print(&.{.{.text = pipe}},
                .{.col_offset = @intCast(pane_x + col), .row_offset = @intCast(pane_y + i)});

            }

            col += 2;
        }

        const prefix = if(node.is_expanded) "▾ " else "▸ ";
        const shared = if(node.is_shared) " [shared]" else "";
        const cycle  = if(node.is_cycle)  " (↺)" else "";

        const line = try std.fmt.allocPrint(frame_aloc, "{s}{s}{s}{s}", .{prefix, pckg.name, shared, cycle});

        var seg = vaxis.Segment{
            .text = line,
            .style = .{ .dim = node.is_optional },
        };

        if(is_selected and is_active) {
            seg.style = .{ .dim = false, .bg = .{.index = 6}, .fg = .{.index = 0} };
        }

        _ = win.print(&.{seg}, .{.col_offset = @intCast(pane_x + col), .row_offset = @intCast(pane_y + i)});
    }
}
