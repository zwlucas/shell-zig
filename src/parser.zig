const std = @import("std");

pub const ParsedCommand = struct {
    name: []const u8,
    args: ?[]const u8,
};

pub fn parseCommand(input: []const u8) ParsedCommand {
    var i: usize = 0;
    var cmd_buf = std.ArrayList(u8){};
    defer cmd_buf.deinit(std.heap.page_allocator);

    while (i < input.len and input[i] == ' ') : (i += 1) {}

    if (i >= input.len) {
        return .{ .name = "", .args = null };
    }

    if (input[i] == '\'' or input[i] == '"') {
        const quote = input[i];
        i += 1;
        while (i < input.len and input[i] != quote) : (i += 1) {
            _ = cmd_buf.append(std.heap.page_allocator, input[i]) catch {};
        }
        if (i < input.len) i += 1;
    } else {
        while (i < input.len and input[i] != ' ') : (i += 1) {
            if (input[i] == '\\' and i + 1 < input.len) {
                i += 1;
                _ = cmd_buf.append(std.heap.page_allocator, input[i]) catch {};
            } else {
                _ = cmd_buf.append(std.heap.page_allocator, input[i]) catch {};
            }
        }
    }

    while (i < input.len and input[i] == ' ') : (i += 1) {}

    const cmd_name = cmd_buf.toOwnedSlice(std.heap.page_allocator) catch "";
    const args = if (i < input.len) input[i..] else null;

    return .{ .name = cmd_name, .args = args };
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
