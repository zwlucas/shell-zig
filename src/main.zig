const std = @import("std");
const parser = @import("parser.zig");
const shell = @import("shell.zig");

var stdin_buffer: [4096]u8 = undefined;
var stdin_reader = std.fs.File.stdin().readerStreaming(&stdin_buffer);
const stdin = &stdin_reader.interface;

var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
const stdout = &stdout_writer.interface;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    while (true) {
        try stdout.print("$ ", .{});

        const command = try stdin.takeDelimiter('\n');
        if (command) |cmd| {
            const parsed = parser.parseCommand(cmd);
            const result = try shell.executeCommand(allocator, stdout, parsed.name, parsed.args, parsed.output_redirect, parsed.error_redirect, parsed.append_output);

            if (result == .exit_shell) break;
        } else {
            break;
        }
    }
}
