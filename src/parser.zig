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
    try args_list.ensureTotalCapacity(allocator, 16);
    errdefer args_list.deinit(allocator);

    try args_list.append(allocator, cmd_name);

    if (args_str) |args| {
        var i: usize = 0;
        while (i < args.len) {
            if (args[i] == '\'' or args[i] == '"') {
                const quote = args[i];
                i += 1;
                const start = i;
                while (i < args.len and args[i] != quote) : (i += 1) {}
                if (i <= args.len) {
                    try args_list.append(allocator, args[start..i]);
                    i += 1;
                }
            } else if (args[i] != ' ') {
                const start = i;
                while (i < args.len and args[i] != ' ' and args[i] != '\'' and args[i] != '"') : (i += 1) {}
                try args_list.append(allocator, args[start..i]);
            } else {
                i += 1;
            }
        }
    }

    return args_list.toOwnedSlice(allocator);
}
