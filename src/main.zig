const std = @import("std");
const parser = @import("parser.zig");
const shell = @import("shell.zig");
const builtins = @import("builtins.zig");

const BUILTINS = [_][]const u8{ "echo", "exit" };

fn tryComplete(allocator: std.mem.Allocator, partial: []const u8) ?[]const u8 {
    var matches: usize = 0;
    var match: ?[]const u8 = null;
    var match_is_builtin = false;

    for (BUILTINS) |builtin| {
        if (std.mem.startsWith(u8, builtin, partial)) {
            matches += 1;
            if (matches == 1) {
                match = builtin;
                match_is_builtin = true;
            }
            if (matches > 1) {
                if (match != null and !match_is_builtin) {
                    allocator.free(match.?);
                }
                return null;
            }
        }
    }

    const path_env = std.posix.getenv("PATH") orelse {
        if (matches == 1 and match != null) {
            return allocator.dupe(u8, match.?) catch null;
        }
        return null;
    };

    var path_iter = std.mem.splitScalar(u8, path_env, ':');
    while (path_iter.next()) |dir_path| {
        if (dir_path.len == 0) continue;

        var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch continue;
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch continue) |entry| {
            if (entry.kind == .file or entry.kind == .sym_link) {
                if (std.mem.startsWith(u8, entry.name, partial)) {
                    const stat = dir.statFile(entry.name) catch continue;
                    if (stat.mode & 0o111 != 0) {
                        if (match != null and match_is_builtin and std.mem.eql(u8, match.?, entry.name)) {
                            continue;
                        }

                        matches += 1;
                        if (matches == 1) {
                            match = allocator.dupe(u8, entry.name) catch continue;
                            match_is_builtin = false;
                        } else {
                            if (match != null and !match_is_builtin) {
                                allocator.free(match.?);
                            }
                            return null;
                        }
                    }
                }
            }
        }
    }

    if (matches == 1 and match != null) {
        if (match_is_builtin) {
            return allocator.dupe(u8, match.?) catch null;
        } else {
            return match.?;
        }
    }
    return null;
}

fn enableRawMode(fd: std.posix.fd_t) !std.posix.termios {
    const original = try std.posix.tcgetattr(fd);
    var raw = original;

    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;

    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;

    try std.posix.tcsetattr(fd, .FLUSH, raw);
    return original;
}

fn disableRawMode(fd: std.posix.fd_t, original: std.posix.termios) !void {
    try std.posix.tcsetattr(fd, .FLUSH, original);
}

fn readCommand(allocator: std.mem.Allocator) !?[]const u8 {
    const stdin = std.fs.File.stdin();
    const stdout = std.fs.File.stdout();

    const stdin_fd = stdin.handle;

    const is_tty = std.posix.isatty(stdin_fd);
    const original_termios = if (is_tty) try enableRawMode(stdin_fd) else null;
    defer if (original_termios) |orig| disableRawMode(stdin_fd, orig) catch {};

    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    var byte: [1]u8 = undefined;

    while (true) {
        const bytes_read = try stdin.read(&byte);
        if (bytes_read == 0) return null;

        const c = byte[0];

        if (c == '\n' or c == '\r') {
            return try buffer.toOwnedSlice(allocator);
        } else if (c == '\t' and is_tty) {
            const partial = buffer.items;
            if (partial.len > 0 and std.mem.indexOf(u8, partial, " ") == null) {
                if (tryComplete(allocator, partial)) |completion| {
                    defer allocator.free(completion);
                    const remaining = completion[partial.len..];
                    try stdout.writeAll(remaining);
                    try stdout.writeAll(" ");
                    try buffer.appendSlice(allocator, remaining);
                    try buffer.append(allocator, ' ');
                } else {
                    try stdout.writeAll("\x07");
                }
            }
        } else if ((c == 127 or c == 8) and is_tty) {
            if (buffer.items.len > 0) {
                _ = buffer.pop();
                try stdout.writeAll("\x08 \x08");
            }
        } else if (c >= 32 and c < 127) {
            try buffer.append(allocator, c);
            if (is_tty) {
                try stdout.writeAll(&[_]u8{c});
            }
        } else if (c == '\t' and !is_tty) {
            try buffer.append(allocator, c);
        }
    }
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.fs.File.stdout();

    while (true) {
        try stdout.writeAll("$ ");

        const command = try readCommand(allocator);
        if (command) |cmd| {
            defer allocator.free(cmd);
            try stdout.writeAll("\n");

            const parsed = parser.parseCommand(cmd);

            var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
            const stdout_iface = &stdout_writer.interface;

            const result = try shell.executeCommand(allocator, stdout_iface, parsed.name, parsed.args, parsed.output_redirect, parsed.error_redirect, parsed.append_output, parsed.append_error);

            if (result == .exit_shell) break;
        } else {
            break;
        }
    }
}
