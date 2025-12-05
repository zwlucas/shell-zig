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
        var arg_buf = std.ArrayList(u8){};
        defer arg_buf.deinit(allocator);

        while (i < args.len) {
            if (args[i] == '\'') {
                i += 1;
                while (i < args.len and args[i] != '\'') : (i += 1) {
                    try arg_buf.append(allocator, args[i]);
                }
                if (i < args.len) i += 1;
            } else if (args[i] == '"') {
                i += 1;
                while (i < args.len and args[i] != '"') : (i += 1) {
                    if (args[i] == '\\' and i + 1 < args.len) {
                        const next = args[i + 1];
                        if (next == '"' or next == '\\') {
                            i += 1;
                            try arg_buf.append(allocator, args[i]);
                        } else {
                            try arg_buf.append(allocator, args[i]);
                        }
                    } else {
                        try arg_buf.append(allocator, args[i]);
                    }
                }
                if (i < args.len) i += 1;
            } else if (args[i] == '\\' and i + 1 < args.len) {
                i += 1;
                try arg_buf.append(allocator, args[i]);
                i += 1;
            } else if (args[i] == ' ') {
                if (arg_buf.items.len > 0) {
                    try args_list.append(allocator, try arg_buf.toOwnedSlice(allocator));
                }
                i += 1;
            } else {
                try arg_buf.append(allocator, args[i]);
                i += 1;
            }
        }

        if (arg_buf.items.len > 0) {
            try args_list.append(allocator, try arg_buf.toOwnedSlice(allocator));
        }
    }

    return args_list.toOwnedSlice(allocator);
}
