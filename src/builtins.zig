const std = @import("std");
const path = @import("path.zig");

const BUILTINS = [_][]const u8{ "exit", "echo", "type" };

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
        try stdout.print("{s}\n", .{a});
    } else {
        try stdout.print("\n", .{});
    }
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
