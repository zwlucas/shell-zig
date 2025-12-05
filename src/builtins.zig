const std = @import("std");
const path = @import("path.zig");

const BUILTINS = [_][]const u8{ "exit", "echo", "type", "pwd", "cd", "history" };

pub const CommandResult = enum {
    continue_loop,
    exit_shell,
};

pub fn isBuiltin(cmd_name: []const u8) bool {
    for (BUILTINS) |builtin| {
        if (std.mem.eql(u8, cmd_name, builtin)) return true;
    }
    return false;
}

pub fn executeExit() CommandResult {
    return .exit_shell;
}

pub fn executeEcho(stdout: anytype, args: ?[]const u8) !void {
    if (args) |a| {
        var i: usize = 0;
        var in_quote = false;
        var quote_char: u8 = 0;
        var unquoted = std.ArrayList(u8){};
        defer unquoted.deinit(std.heap.page_allocator);
        var last_was_space = false;

        while (i < a.len) : (i += 1) {
            if (!in_quote and a[i] == '\\' and i + 1 < a.len) {
                i += 1;
                _ = unquoted.append(std.heap.page_allocator, a[i]) catch {};
                last_was_space = false;
            } else if (!in_quote and (a[i] == '\'' or a[i] == '"')) {
                in_quote = true;
                quote_char = a[i];
                last_was_space = false;
            } else if (in_quote and a[i] == quote_char) {
                in_quote = false;
                last_was_space = false;
            } else if (in_quote and quote_char == '"' and a[i] == '\\' and i + 1 < a.len) {
                const next = a[i + 1];
                if (next == '"' or next == '\\') {
                    i += 1;
                    _ = unquoted.append(std.heap.page_allocator, a[i]) catch {};
                } else {
                    _ = unquoted.append(std.heap.page_allocator, a[i]) catch {};
                }
                last_was_space = false;
            } else if (!in_quote and a[i] == ' ') {
                if (!last_was_space) {
                    _ = unquoted.append(std.heap.page_allocator, ' ') catch {};
                    last_was_space = true;
                }
            } else {
                _ = unquoted.append(std.heap.page_allocator, a[i]) catch {};
                last_was_space = false;
            }
        }

        try stdout.print("{s}\n", .{unquoted.items});
    } else {
        try stdout.print("\n", .{});
    }
}

pub fn executePwd(allocator: std.mem.Allocator, stdout: anytype) !void {
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    try stdout.print("{s}\n", .{cwd});
}

pub fn executeCd(allocator: std.mem.Allocator, stdout: anytype, args: ?[]const u8) !void {
    if (args == null or args.?.len == 0) {
        try stdout.print("cd: missing argument\n", .{});
        return;
    }

    const arg = std.mem.trim(u8, args.?, " ");
    var path_buf: [512]u8 = undefined;
    var dir: []const u8 = arg;

    if (std.mem.eql(u8, arg, "~")) {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
            try stdout.print("cd: HOME not set\n", .{});
            return;
        };
        defer allocator.free(home);
        dir = try std.fmt.bufPrint(&path_buf, "{s}", .{home});
    } else if (std.mem.startsWith(u8, arg, "~/")) {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
            try stdout.print("cd: HOME not set\n", .{});
            return;
        };
        defer allocator.free(home);
        dir = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ home, arg[2..] });
    }

    std.posix.chdir(dir) catch {
        try stdout.print("cd: {s}: No such file or directory\n", .{arg});
    };
}

pub fn executeType(allocator: std.mem.Allocator, stdout: anytype, args: ?[]const u8) !void {
    if (args) |a| {
        if (isBuiltin(a)) {
            try stdout.print("{s} is a shell builtin\n", .{a});
        } else if (try path.findInPath(allocator, a)) |cmd_path| {
            defer allocator.free(cmd_path);
            try stdout.print("{s} is {s}\n", .{ a, cmd_path });
        } else {
            try stdout.print("{s}: not found\n", .{a});
        }
    }
}

pub fn executeHistory(stdout: anytype, history_list: []const []const u8, args: ?[]const u8) !void {
    var limit: usize = history_list.len;

    if (args) |a| {
        const trimmed = std.mem.trim(u8, a, " ");
        if (trimmed.len > 0) {
            // Check if it's a -r flag for reading from file
            if (std.mem.startsWith(u8, trimmed, "-r ")) {
                const file_path = std.mem.trim(u8, trimmed[3..], " ");
                if (file_path.len == 0) {
                    try stdout.print("history: -r requires a file path\n", .{});
                }
                return;
            }

            limit = std.fmt.parseInt(usize, trimmed, 10) catch {
                try stdout.print("history: invalid argument\n", .{});
                return;
            };
        }
    }

    const start = if (limit < history_list.len) history_list.len - limit else 0;
    for (history_list[start..], start + 1..) |cmd, idx| {
        try stdout.print("    {d}  {s}\n", .{ idx, cmd });
    }
}

pub fn executeHistoryRead(allocator: std.mem.Allocator, stdout: anytype, file_path: []const u8, history_list: *std.ArrayList([]const u8)) !void {
    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        try stdout.print("history: cannot open {s}: error\n", .{file_path});
        return;
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);

    const bytes_read = try file.readAll(buffer);
    if (bytes_read == 0) return;

    // Parse lines from file
    var line_iter = std.mem.splitScalar(u8, buffer[0..bytes_read], '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (trimmed.len > 0) {
            const line_copy = try allocator.dupe(u8, trimmed);
            try history_list.append(allocator, line_copy);
        }
    }
}
