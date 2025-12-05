const std = @import("std");
const builtins = @import("builtins.zig");

pub fn runExternalProgram(allocator: std.mem.Allocator, program_path: []const u8, argv: []const []const u8) !void {
    const argv_z = try allocator.allocSentinel(?[*:0]const u8, argv.len, null);
    defer allocator.free(argv_z);

    for (argv, 0..) |arg, i| {
        argv_z[i] = (try allocator.dupeZ(u8, arg)).ptr;
    }
    defer {
        for (argv_z[0..argv.len]) |arg_ptr| {
            if (arg_ptr) |ptr| allocator.free(std.mem.span(ptr));
        }
    }

    const program_path_z = try allocator.dupeZ(u8, program_path);
    defer allocator.free(program_path_z);

    const pid = try std.posix.fork();

    if (pid == 0) {
        _ = std.posix.execveZ(program_path_z, argv_z, std.c.environ) catch {
            std.posix.exit(1);
        };
        unreachable;
    } else {
        _ = std.posix.waitpid(pid, 0);
    }
}

pub fn runExternalProgramWithRedirect(allocator: std.mem.Allocator, program_path: []const u8, argv: []const []const u8, output_file: ?[]const u8, error_file: ?[]const u8, append_file: ?[]const u8, append_error_file: ?[]const u8) !void {
    const argv_z = try allocator.allocSentinel(?[*:0]const u8, argv.len, null);
    defer allocator.free(argv_z);

    for (argv, 0..) |arg, i| {
        argv_z[i] = (try allocator.dupeZ(u8, arg)).ptr;
    }
    defer {
        for (argv_z[0..argv.len]) |arg_ptr| {
            if (arg_ptr) |ptr| allocator.free(std.mem.span(ptr));
        }
    }

    const program_path_z = try allocator.dupeZ(u8, program_path);
    defer allocator.free(program_path_z);

    const pid = try std.posix.fork();

    if (pid == 0) {
        if (output_file) |file| {
            const cwd = std.fs.cwd();
            const fd = cwd.createFile(file, .{}) catch {
                std.posix.exit(1);
            };
            defer fd.close();
            try std.posix.dup2(fd.handle, 1);
        } else if (append_file) |file| {
            const cwd = std.fs.cwd();
            const fd = cwd.openFile(file, .{ .mode = .write_only }) catch |err| blk: {
                if (err == error.FileNotFound) {
                    break :blk cwd.createFile(file, .{}) catch {
                        std.posix.exit(1);
                    };
                }
                std.posix.exit(1);
            };
            defer fd.close();
            fd.seekFromEnd(0) catch {
                std.posix.exit(1);
            };
            try std.posix.dup2(fd.handle, 1);
        }

        if (error_file) |file| {
            const cwd = std.fs.cwd();
            const fd = cwd.createFile(file, .{}) catch {
                std.posix.exit(1);
            };
            defer fd.close();
            try std.posix.dup2(fd.handle, 2);
        } else if (append_error_file) |file| {
            const cwd = std.fs.cwd();
            const fd = cwd.openFile(file, .{ .mode = .write_only }) catch |err| blk: {
                if (err == error.FileNotFound) {
                    break :blk cwd.createFile(file, .{}) catch {
                        std.posix.exit(1);
                    };
                }
                std.posix.exit(1);
            };
            defer fd.close();
            fd.seekFromEnd(0) catch {
                std.posix.exit(1);
            };
            try std.posix.dup2(fd.handle, 2);
        }

        _ = std.posix.execveZ(program_path_z, argv_z, std.c.environ) catch {
            std.posix.exit(1);
        };
        unreachable;
    } else {
        _ = std.posix.waitpid(pid, 0);
    }
}

fn runBuiltinInChild(
    allocator: std.mem.Allocator,
    cmd_name: []const u8,
    args: ?[]const u8,
    stdin_fd: std.posix.fd_t,
    stdout_fd: std.posix.fd_t,
) noreturn {
    // Redirect stdin/stdout to provided fds (already valid)
    if (stdin_fd != 0) std.posix.dup2(stdin_fd, 0) catch {};
    if (stdout_fd != 1) std.posix.dup2(stdout_fd, 1) catch {};

    var out_file = std.fs.File{ .handle = 1 };
    var out_writer = out_file.writerStreaming(&.{});
    const w = &out_writer.interface;

    if (std.mem.eql(u8, cmd_name, "echo")) {
        builtins.executeEcho(w, args) catch {};
    } else if (std.mem.eql(u8, cmd_name, "type")) {
        builtins.executeType(allocator, w, args) catch {};
    } else if (std.mem.eql(u8, cmd_name, "pwd")) {
        builtins.executePwd(allocator, w) catch {};
    } else if (std.mem.eql(u8, cmd_name, "cd")) {
        builtins.executeCd(allocator, w, args) catch {};
    } else if (std.mem.eql(u8, cmd_name, "exit")) {
        // exit inside pipeline child just exits child
    }

    std.posix.exit(0);
}

pub fn runPipeline(
    allocator: std.mem.Allocator,
    left_path: ?[]const u8,
    left_builtin: bool,
    left_name: []const u8,
    left_args: ?[]const u8,
    left_argv: ?[]const []const u8,
    right_path: ?[]const u8,
    right_builtin: bool,
    right_name: []const u8,
    right_args: ?[]const u8,
    right_argv: ?[]const []const u8,
) !void {
    const fds = try std.posix.pipe();

    const pid1 = try std.posix.fork();
    if (pid1 == 0) {
        std.posix.close(fds[0]);
        try std.posix.dup2(fds[1], 1);
        std.posix.close(fds[1]);

        if (left_builtin) {
            runBuiltinInChild(allocator, left_name, left_args, 0, 1);
        } else {
            const argv1_z = try allocator.allocSentinel(?[*:0]const u8, left_argv.?.len, @as(?[*:0]const u8, null));
            defer allocator.free(argv1_z);
            for (left_argv.?, 0..) |arg, i| {
                argv1_z[i] = (try allocator.dupeZ(u8, arg)).ptr;
            }
            defer {
                for (argv1_z[0..left_argv.?.len]) |arg_ptr| {
                    if (arg_ptr) |ptr| allocator.free(std.mem.span(ptr));
                }
            }
            const program1_path_z = try allocator.dupeZ(u8, left_path.?);
            defer allocator.free(program1_path_z);
            _ = std.posix.execveZ(program1_path_z, argv1_z, std.c.environ) catch {
                std.posix.exit(1);
            };
            unreachable;
        }
    }

    const pid2 = try std.posix.fork();
    if (pid2 == 0) {
        std.posix.close(fds[1]);
        try std.posix.dup2(fds[0], 0);
        std.posix.close(fds[0]);

        if (right_builtin) {
            runBuiltinInChild(allocator, right_name, right_args, 0, 1);
        } else {
            const argv2_z = try allocator.allocSentinel(?[*:0]const u8, right_argv.?.len, @as(?[*:0]const u8, null));
            defer allocator.free(argv2_z);
            for (right_argv.?, 0..) |arg, i| {
                argv2_z[i] = (try allocator.dupeZ(u8, arg)).ptr;
            }
            defer {
                for (argv2_z[0..right_argv.?.len]) |arg_ptr| {
                    if (arg_ptr) |ptr| allocator.free(std.mem.span(ptr));
                }
            }
            const program2_path_z = try allocator.dupeZ(u8, right_path.?);
            defer allocator.free(program2_path_z);
            _ = std.posix.execveZ(program2_path_z, argv2_z, std.c.environ) catch {
                std.posix.exit(1);
            };
            unreachable;
        }
    }

    std.posix.close(fds[0]);
    std.posix.close(fds[1]);

    _ = std.posix.waitpid(pid1, 0);
    _ = std.posix.waitpid(pid2, 0);
}
