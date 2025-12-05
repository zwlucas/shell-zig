const std = @import("std");

pub const ParsedCommand = struct {
    name: []const u8,
    args: ?[]const u8,
};

pub fn parseCommand(input: []const u8) ParsedCommand {
    const space_pos = std.mem.indexOfScalar(u8, input, ' ');
    if (space_pos) |pos| {
        return .{ .name = input[0..pos], .args = input[pos + 1 ..] };
    }
    return .{ .name = input, .args = null };
}

pub fn parseArgs(allocator: std.mem.Allocator, cmd_name: []const u8, args_str: ?[]const u8) ![]const []const u8 {
    var args_list = std.ArrayList([]const u8){};
    try args_list.ensureTotalCapacity(allocator, 8);
    errdefer args_list.deinit(allocator);

    try args_list.append(allocator, cmd_name);

    if (args_str) |args| {
        var it = std.mem.tokenizeScalar(u8, args, ' ');
        while (it.next()) |arg| {
            try args_list.append(allocator, arg);
        }
    }

    return args_list.toOwnedSlice(allocator);
}
