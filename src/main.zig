const std = @import("std");
const parser = @import("parser.zig");
const shell = @import("shell.zig");
const builtins = @import("builtins.zig");

const BUILTINS = [_][]const u8{ "echo", "exit" };

fn tryComplete(partial: []const u8) ?[]const u8 {
    var matches: usize = 0;
    var match: []const u8 = "";

    for (BUILTINS) |builtin| {
        if (std.mem.startsWith(u8, builtin, partial)) {
            matches += 1;
            match = builtin;
            if (matches > 1) return null;
        }
    }

    if (matches == 1) return match;
    return null;
}

fn enableRawMode(fd: std.posix.fd_t) !std.posix.termios {
    const original = try std.posix.tcgetattr(fd);
    var raw = original;

    // Disable canonical mode and echo
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;

    // Set minimum bytes and timeout for read
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

    // Only use raw mode if stdin is a terminal
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
                if (tryComplete(partial)) |completion| {
                    const remaining = completion[partial.len..];
                    try stdout.writeAll(remaining);
                    try stdout.writeAll(" ");
                    try buffer.appendSlice(allocator, remaining);
                    try buffer.append(allocator, ' ');
                } else {
                    // No completion found, ring the bell
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
            // When not a TTY, tab is part of the input (for testing)
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
