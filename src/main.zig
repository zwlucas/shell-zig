const std = @import("std");

var stdin_buffer: [4096]u8 = undefined;
var stdin_reader = std.fs.File.stdin().readerStreaming(&stdin_buffer);
const stdin = &stdin_reader.interface;

var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
const stdout = &stdout_writer.interface;

const CommandResult = enum {
    continue_loop,
    exit_shell,
};

fn parseCommand(input: []const u8) struct { name: []const u8, args: ?[]const u8 } {
    const space_pos = std.mem.indexOfScalar(u8, input, ' ');
    if (space_pos) |pos| {
        return .{
            .name = input[0..pos],
            .args = input[pos + 1 ..],
        };
    }
    return .{
        .name = input,
        .args = null,
    };
}

fn isBuiltin(cmd_name: []const u8) bool {
    const builtins = [_][]const u8{ "exit", "echo", "type" };
    for (builtins) |builtin| {
        if (std.mem.eql(u8, cmd_name, builtin)) {
            return true;
        }
    }
    return false;
}

fn findInPath(allocator: std.mem.Allocator, cmd_name: []const u8) !?[]const u8 {
    const path_env = std.process.getEnvVarOwned(allocator, "PATH") catch return null;
    defer allocator.free(path_env);

    var it = std.mem.splitScalar(u8, path_env, ':');
    while (it.next()) |dir| {
        const full_path = std.fs.path.join(allocator, &[_][]const u8{ dir, cmd_name }) catch continue;
        defer allocator.free(full_path);

        const file = std.fs.openFileAbsolute(full_path, .{}) catch continue;
        const stat = file.stat() catch {
            file.close();
            continue;
        };
        file.close();

        const mode = stat.mode;
        const has_exec = (mode & 0o111) != 0;
        if (!has_exec) continue;

        return try allocator.dupe(u8, full_path);
    }

    return null;
}

fn executeCommand(allocator: std.mem.Allocator, cmd_name: []const u8, args: ?[]const u8) !CommandResult {
    if (std.mem.eql(u8, cmd_name, "exit")) {
        return .exit_shell;
    }

    if (std.mem.eql(u8, cmd_name, "echo")) {
        if (args) |a| {
            try stdout.print("{s}\n", .{a});
        } else {
            try stdout.print("\n", .{});
        }
        return .continue_loop;
    }

    if (std.mem.eql(u8, cmd_name, "type")) {
        if (args) |a| {
            if (isBuiltin(a)) {
                try stdout.print("{s} is a shell builtin\n", .{a});
            } else if (try findInPath(allocator, a)) |path| {
                defer allocator.free(path);
                try stdout.print("{s} is {s}\n", .{ a, path });
            } else {
                try stdout.print("{s}: not found\n", .{a});
            }
        }
        return .continue_loop;
    }

    try stdout.print("{s}: command not found\n", .{cmd_name});
    return .continue_loop;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    while (true) {
        try stdout.print("$ ", .{});

        const command = try stdin.takeDelimiter('\n');
        if (command) |cmd| {
            const parsed = parseCommand(cmd);
            const result = try executeCommand(allocator, parsed.name, parsed.args);

            if (result == .exit_shell) {
                break;
            }
        } else {
            break;
        }
    }
}
