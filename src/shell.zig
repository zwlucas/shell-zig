const std = @import("std");
const parser = @import("parser.zig");
const builtins = @import("builtins.zig");
const path = @import("path.zig");
const executor = @import("executor.zig");

fn freeArgv(allocator: std.mem.Allocator, argv: []const []const u8) void {
    // argv[0] is cmd_name (not allocated), argv[1..] are allocated by parseArgs
    for (argv[1..]) |arg| allocator.free(arg);
    allocator.free(argv);
}

pub fn executeCommand(
    allocator: std.mem.Allocator,
    stdout: anytype,
    cmd_name: []const u8,
    args: ?[]const u8,
    output_redirect: ?[]const u8,
    error_redirect: ?[]const u8,
    append_output: ?[]const u8,
    append_error: ?[]const u8,
    history_list: []const []const u8,
) !builtins.CommandResult {
    if (std.mem.eql(u8, cmd_name, "exit")) return builtins.executeExit();

    if (std.mem.eql(u8, cmd_name, "history")) {
        try builtins.executeHistory(stdout, history_list, args);
        return .continue_loop;
    }

    if (std.mem.eql(u8, cmd_name, "echo")) {
        if (error_redirect) |file| {
            const fd = try std.fs.cwd().createFile(file, .{});
            fd.close();
        }

        if (append_error) |file| {
            _ = std.fs.cwd().openFile(file, .{ .mode = .write_only }) catch |err| {
                if (err == error.FileNotFound) {
                    const new_fd = try std.fs.cwd().createFile(file, .{});
                    new_fd.close();
                } else {
                    return err;
                }
            };
        }

        if (output_redirect != null or append_output != null) {
            const file = if (output_redirect) |f| f else append_output.?;
            const is_append = append_output != null;

            const fd = if (is_append) blk: {
                break :blk std.fs.cwd().openFile(file, .{ .mode = .write_only }) catch |err| {
                    if (err == error.FileNotFound) {
                        break :blk try std.fs.cwd().createFile(file, .{});
                    }
                    return err;
                };
            } else try std.fs.cwd().createFile(file, .{});
            defer fd.close();

            if (is_append) {
                try fd.seekFromEnd(0);
            }

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
        defer {
            for (argv[1..]) |arg| allocator.free(arg);
            allocator.free(argv);
        }

        if (output_redirect != null or error_redirect != null or append_output != null or append_error != null) {
            try executor.runExternalProgramWithRedirect(allocator, program_path, argv, output_redirect, error_redirect, append_output, append_error);
        } else {
            try executor.runExternalProgram(allocator, program_path, argv);
        }
        return .continue_loop;
    }

    try stdout.print("{s}: command not found\n", .{cmd_name});
    return .continue_loop;
}

pub fn executePipeline(
    allocator: std.mem.Allocator,
    stdout: anytype,
    commands: []const []const u8,
) !builtins.CommandResult {
    var stages = std.ArrayList(executor.Stage){};
    defer stages.deinit(allocator);

    var owned_paths = std.ArrayList(?[]const u8){};
    defer {
        for (owned_paths.items) |p| if (p) |path_buf| allocator.free(path_buf);
        owned_paths.deinit(allocator);
    }

    var owned_argvs = std.ArrayList(?[]const []const u8){};
    defer {
        for (owned_argvs.items) |argv_opt| if (argv_opt) |argv| freeArgv(allocator, argv);
        owned_argvs.deinit(allocator);
    }

    for (commands) |cmd_part| {
        const parsed = parser.parseCommand(cmd_part);
        if (parsed.name.len == 0) {
            try stdout.print("{s}: command not found\n", .{cmd_part});
            return .continue_loop;
        }

        const is_builtin = builtins.isBuiltin(parsed.name);
        var cmd_path: ?[]const u8 = null;
        if (!is_builtin) {
            cmd_path = try path.findInPath(allocator, parsed.name);
        }
        if (!is_builtin and cmd_path == null) {
            try stdout.print("{s}: command not found\n", .{parsed.name});
            return .continue_loop;
        }

        try owned_paths.append(allocator, cmd_path);

        var argv: ?[]const []const u8 = null;
        if (!is_builtin) {
            argv = try parser.parseArgs(allocator, parsed.name, parsed.args);
        }
        try owned_argvs.append(allocator, argv);

        try stages.append(allocator, .{
            .is_builtin = is_builtin,
            .name = parsed.name,
            .args = parsed.args,
            .path = cmd_path,
            .argv = argv,
        });
    }

    try executor.runPipeline(allocator, stages.items);
    return .continue_loop;
}
