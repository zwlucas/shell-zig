const std = @import("std");
const path = @import("path.zig");

const BUILTINS = [_][]const u8{ "exit", "echo", "type", "pwd", "cd", "history" };

pub const CommandResult = enum { continue_loop, exit_shell };

pub inline fn isBuiltin(cmd_name: []const u8) bool {
    inline for (BUILTINS) |builtin| {
        if (std.mem.eql(u8, cmd_name, builtin)) return true;
    }
    return false;
}

pub inline fn executeExit() CommandResult {
    return .exit_shell;
}

pub fn executeEcho(stdout: anytype, args: ?[]const u8) !void {
    const a = args orelse {
        try stdout.print("\n", .{});
        return;
    };

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.heap.page_allocator);

    var i: usize = 0;
    var in_quote = false;
    var quote_char: u8 = 0;
    var last_space = false;

    while (i < a.len) : (i += 1) {
        const c = a[i];

        if (!in_quote and c == '\\' and i + 1 < a.len) {
            i += 1;
            try buf.append(std.heap.page_allocator, a[i]);
            last_space = false;
        } else if (!in_quote and (c == '\'' or c == '"')) {
            in_quote = true;
            quote_char = c;
            last_space = false;
        } else if (in_quote and c == quote_char) {
            in_quote = false;
            last_space = false;
        } else if (in_quote and quote_char == '"' and c == '\\' and i + 1 < a.len) {
            const next = a[i + 1];
            if (next == '"' or next == '\\') i += 1;
            try buf.append(std.heap.page_allocator, a[i]);
            last_space = false;
        } else if (!in_quote and c == ' ') {
            if (!last_space) {
                try buf.append(std.heap.page_allocator, ' ');
                last_space = true;
            }
        } else {
            try buf.append(std.heap.page_allocator, c);
            last_space = false;
        }
    }

    try stdout.print("{s}\n", .{buf.items});
}

pub fn executePwd(allocator: std.mem.Allocator, stdout: anytype) !void {
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    try stdout.print("{s}\n", .{cwd});
}

pub fn executeCd(allocator: std.mem.Allocator, stdout: anytype, args: ?[]const u8) !void {
    const a = args orelse {
        try stdout.print("cd: missing argument\n", .{});
        return;
    };

    if (a.len == 0) {
        try stdout.print("cd: missing argument\n", .{});
        return;
    }

    const arg = std.mem.trim(u8, a, " ");
    var path_buf: [512]u8 = undefined;
    const dir = blk: {
        if (std.mem.eql(u8, arg, "~")) {
            const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
                try stdout.print("cd: HOME not set\n", .{});
                return;
            };
            defer allocator.free(home);
            break :blk try std.fmt.bufPrint(&path_buf, "{s}", .{home});
        } else if (std.mem.startsWith(u8, arg, "~/")) {
            const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
                try stdout.print("cd: HOME not set\n", .{});
                return;
            };
            defer allocator.free(home);
            break :blk try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ home, arg[2..] });
        }
        break :blk arg;
    };

    std.posix.chdir(dir) catch {
        try stdout.print("cd: {s}: No such file or directory\n", .{arg});
    };
}

pub fn executeType(allocator: std.mem.Allocator, stdout: anytype, args: ?[]const u8) !void {
    const a = args orelse return;

    if (isBuiltin(a)) {
        try stdout.print("{s} is a shell builtin\n", .{a});
    } else if (try path.findInPath(allocator, a)) |cmd_path| {
        defer allocator.free(cmd_path);
        try stdout.print("{s} is {s}\n", .{ a, cmd_path });
    } else {
        try stdout.print("{s}: not found\n", .{a});
    }
}

pub fn executeHistory(stdout: anytype, history_list: []const []const u8, args: ?[]const u8) !void {
    var limit = history_list.len;

    if (args) |a| {
        const trimmed = std.mem.trim(u8, a, " ");
        if (trimmed.len > 0) {
            if (std.mem.startsWith(u8, trimmed, "-r ")) {
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

fn readHistoryFile(allocator: std.mem.Allocator, file_path: []const u8, history_list: *std.ArrayList([]const u8)) !void {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    if (file_size == 0) return;

    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);

    const bytes_read = try file.readAll(buffer);
    var line_iter = std.mem.splitScalar(u8, buffer[0..bytes_read], '\n');

    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (trimmed.len > 0) {
            const line_copy = try allocator.dupe(u8, trimmed);
            try history_list.append(allocator, line_copy);
        }
    }
}

fn writeHistoryFile(file_path: []const u8, history_list: []const []const u8) !void {
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    for (history_list) |cmd| {
        try file.writeAll(cmd);
        try file.writeAll("\n");
    }
}

pub fn executeHistoryRead(allocator: std.mem.Allocator, stdout: anytype, file_path: []const u8, history_list: *std.ArrayList([]const u8)) !void {
    readHistoryFile(allocator, file_path, history_list) catch {
        try stdout.print("history: cannot open {s}: error\n", .{file_path});
    };
}

pub fn executeHistoryWrite(stdout: anytype, file_path: []const u8, history_list: []const []const u8) !void {
    writeHistoryFile(file_path, history_list) catch {
        try stdout.print("history: cannot write to {s}: error\n", .{file_path});
    };
}

pub fn executeHistoryAppend(stdout: anytype, file_path: []const u8, history_list: []const []const u8, last_written_index: *usize) !void {
    const file = std.fs.cwd().openFile(file_path, .{ .mode = .write_only }) catch |err| {
        if (err == error.FileNotFound) {
            writeHistoryFile(file_path, history_list) catch {
                try stdout.print("history: cannot write to {s}: error\n", .{file_path});
                return;
            };
            last_written_index.* = history_list.len;
            return;
        }
        try stdout.print("history: cannot open {s}: error\n", .{file_path});
        return;
    };
    defer file.close();

    try file.seekFromEnd(0);

    for (history_list[last_written_index.*..]) |cmd| {
        try file.writeAll(cmd);
        try file.writeAll("\n");
    }

    last_written_index.* = history_list.len;
}
