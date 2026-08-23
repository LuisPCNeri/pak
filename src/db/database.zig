
pub const Reason: type = enum(u8) {
    explicit   = 0,
    dependency = 1,
};

pub const Package: type = struct {
    id:          u32,
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
