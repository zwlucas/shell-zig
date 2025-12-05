const std = @import("std");
const parser = @import("parser.zig");
const builtins = @import("builtins.zig");
const path = @import("path.zig");
const executor = @import("executor.zig");

pub fn executeCommand(
    allocator: std.mem.Allocator,
    stdout: anytype,
    cmd_name: []const u8,
    args: ?[]const u8,
) !builtins.CommandResult {
    if (std.mem.eql(u8, cmd_name, "exit")) return builtins.executeExit();

    if (std.mem.eql(u8, cmd_name, "echo")) {
        try builtins.executeEcho(stdout, args);
        return .continue_loop;
    }

    if (std.mem.eql(u8, cmd_name, "pwd")) {
        try builtins.executePwd(allocator, stdout);
        return .continue_loop;
    }

    if (std.mem.eql(u8, cmd_name, "cd")) {
        try builtins.executeCd(stdout, args);
        return .continue_loop;
    }

    if (std.mem.eql(u8, cmd_name, "type")) {
        try builtins.executeType(allocator, stdout, args);
        return .continue_loop;
    }

    if (try path.findInPath(allocator, cmd_name)) |program_path| {
        defer allocator.free(program_path);

        const argv = try parser.parseArgs(allocator, cmd_name, args);
        defer allocator.free(argv);

        try executor.runExternalProgram(allocator, program_path, argv);
        return .continue_loop;
    }

    try stdout.print("{s}: command not found\n", .{cmd_name});
    return .continue_loop;
}
