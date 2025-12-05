const std = @import("std");
const path = @import("path.zig");

const BUILTINS = [_][]const u8{ "exit", "echo", "type", "pwd", "cd" };

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
            if (!in_quote and (a[i] == '\'' or a[i] == '"')) {
                in_quote = true;
                quote_char = a[i];
                last_was_space = false;
            } else if (in_quote and a[i] == quote_char) {
                in_quote = false;
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
