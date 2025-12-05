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

fn executeCommand(cmd_name: []const u8, args: ?[]const u8) !CommandResult {
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

    // Command not found
    try stdout.print("{s}: command not found\n", .{cmd_name});
    return .continue_loop;
}

pub fn main() !void {
    while (true) {
        try stdout.print("$ ", .{});

        const command = try stdin.takeDelimiter('\n');
        if (command) |cmd| {
            const parsed = parseCommand(cmd);
            const result = try executeCommand(parsed.name, parsed.args);

            if (result == .exit_shell) {
                break;
            }
        } else {
            break;
        }
    }
}
