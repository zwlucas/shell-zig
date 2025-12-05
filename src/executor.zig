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
    stages: []const Stage,
) !void {
    if (stages.len == 0) return;
    if (stages.len == 1) {
        const s = stages[0];
        if (s.is_builtin) {
            runBuiltinInChild(allocator, s.name, s.args, 0, 1);
        } else {
            const argv_z = try allocator.allocSentinel(?[*:0]const u8, s.argv.?.len, @as(?[*:0]const u8, null));
            defer allocator.free(argv_z);
            for (s.argv.?, 0..) |arg, i| argv_z[i] = (try allocator.dupeZ(u8, arg)).ptr;
            defer {
                for (argv_z[0..s.argv.?.len]) |arg_ptr| if (arg_ptr) |ptr| allocator.free(std.mem.span(ptr));
            }
            const path_z = try allocator.dupeZ(u8, s.path.?);
            defer allocator.free(path_z);
            _ = std.posix.execveZ(path_z, argv_z, std.c.environ) catch std.posix.exit(1);
        }
    }

    const pipes = try allocator.alloc([2]std.posix.fd_t, stages.len - 1);
    defer allocator.free(pipes);
    for (pipes) |*p| p.* = try std.posix.pipe();

    var pids = try allocator.alloc(std.posix.pid_t, stages.len);
    defer allocator.free(pids);

    for (stages, 0..) |s, idx| {
        const pid = try std.posix.fork();
        if (pid == 0) {
            if (idx > 0) {
                try std.posix.dup2(pipes[idx - 1][0], 0);
            }
            if (idx + 1 < stages.len) {
                try std.posix.dup2(pipes[idx][1], 1);
            }

            for (pipes) |p| {
                std.posix.close(p[0]);
                std.posix.close(p[1]);
            }

            if (s.is_builtin) {
                runBuiltinInChild(allocator, s.name, s.args, 0, 1);
            } else {
                const argv_z = try allocator.allocSentinel(?[*:0]const u8, s.argv.?.len, @as(?[*:0]const u8, null));
                defer allocator.free(argv_z);
                for (s.argv.?, 0..) |arg, i| argv_z[i] = (try allocator.dupeZ(u8, arg)).ptr;
                defer {
                    for (argv_z[0..s.argv.?.len]) |arg_ptr| if (arg_ptr) |ptr| allocator.free(std.mem.span(ptr));
                }
                const path_z = try allocator.dupeZ(u8, s.path.?);
                defer allocator.free(path_z);
                _ = std.posix.execveZ(path_z, argv_z, std.c.environ) catch std.posix.exit(1);
            }
            unreachable;
        }
        pids[idx] = pid;
    }

    for (pipes) |p| {
        std.posix.close(p[0]);
        std.posix.close(p[1]);
    }

    for (pids) |pid| {
        _ = std.posix.waitpid(pid, 0);
    }
}

pub const Stage = struct {
    is_builtin: bool,
    name: []const u8,
    args: ?[]const u8,
    path: ?[]const u8,
    argv: ?[]const []const u8,
};
