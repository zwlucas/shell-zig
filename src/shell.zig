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
    output_redirect: ?[]const u8,
    error_redirect: ?[]const u8,
) !builtins.CommandResult {
    if (std.mem.eql(u8, cmd_name, "exit")) return builtins.executeExit();

    if (std.mem.eql(u8, cmd_name, "echo")) {
        if (error_redirect) |file| {
            const fd = try std.fs.cwd().createFile(file, .{});
            fd.close();
        }

        if (output_redirect != null) {
            const file = output_redirect.?;
            const fd = try std.fs.cwd().createFile(file, .{});
            defer fd.close();

            if (args) |a| {
                var i: usize = 0;
                var in_quote = false;
                var quote_char: u8 = 0;
                var unquoted = std.ArrayList(u8){};
                defer unquoted.deinit(allocator);
                var last_was_space = false;

                while (i < a.len) : (i += 1) {
                    if (!in_quote and a[i] == '\\' and i + 1 < a.len) {
                        i += 1;
                        _ = unquoted.append(allocator, a[i]) catch {};
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
                            _ = unquoted.append(allocator, a[i]) catch {};
                        } else {
                            _ = unquoted.append(allocator, a[i]) catch {};
                        }
                        last_was_space = false;
                    } else if (!in_quote and a[i] == ' ') {
                        if (!last_was_space) {
                            _ = unquoted.append(allocator, ' ') catch {};
                            last_was_space = true;
                        }
                    } else {
                        _ = unquoted.append(allocator, a[i]) catch {};
                        last_was_space = false;
                    }
                }

                try fd.writeAll(unquoted.items);
                try fd.writeAll("\n");
            } else {
                try fd.writeAll("\n");
            }
        } else {
            try builtins.executeEcho(stdout, args);
        }
        return .continue_loop;
    }

    if (std.mem.eql(u8, cmd_name, "pwd")) {
        try builtins.executePwd(allocator, stdout);
        return .continue_loop;
    }

    if (std.mem.eql(u8, cmd_name, "cd")) {
        try builtins.executeCd(allocator, stdout, args);
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

        if (output_redirect != null or error_redirect != null) {
            try executor.runExternalProgramWithRedirect(allocator, program_path, argv, output_redirect, error_redirect);
        } else {
            try executor.runExternalProgram(allocator, program_path, argv);
        }
        return .continue_loop;
    }

    try stdout.print("{s}: command not found\n", .{cmd_name});
    return .continue_loop;
}
