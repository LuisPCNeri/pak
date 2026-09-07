const std   = @import("std");
const db    = @import("../db/database.zig");
const vaxis: type = @import("vaxis");
const graph = @import("../db/graph.zig");

pub fn render_graph_pane(vx: *vaxis.Vaxis, frame_aloc: std.mem.Allocator, nodes: []graph.TreeNode, database: *db.Database, pane_x: u32, pane_y: u32,
                         cursor: u32, scroll: u32, is_active: bool) !void {

    if(vx.window().width -| pane_x < 10) return;

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

                const connector = if(graph.is_last_sibling(nodes, scroll + i)) "└─" else "├─";
                _ = win.print(&.{.{.text = connector}},
                .{.col_offset = @intCast(pane_x + col), .row_offset = @intCast(pane_y + i)});

            } else {

                const pipe = if(graph.ancestor_is_last(nodes, scroll + i, d + 1)) "  " else "│ ";
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
            seg.style = .{ .dim = false, .bold = true, .bg = .{.index = 6}, .fg = .{.index = 0} };
        }

        _ = win.print(&.{seg}, .{.col_offset = @intCast(pane_x + col), .row_offset = @intCast(pane_y + i)});
    }
}
