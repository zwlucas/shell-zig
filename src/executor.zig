const std = @import("std");

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

pub fn runExternalPipeline(allocator: std.mem.Allocator, program1_path: []const u8, argv1: []const []const u8, program2_path: []const u8, argv2: []const []const u8) !void {
    const argv1_z = try allocator.allocSentinel(?[*:0]const u8, argv1.len, null);
    defer allocator.free(argv1_z);
    for (argv1, 0..) |arg, i| {
        argv1_z[i] = (try allocator.dupeZ(u8, arg)).ptr;
    }
    defer {
        for (argv1_z[0..argv1.len]) |arg_ptr| {
            if (arg_ptr) |ptr| allocator.free(std.mem.span(ptr));
        }
    }

    const argv2_z = try allocator.allocSentinel(?[*:0]const u8, argv2.len, null);
    defer allocator.free(argv2_z);
    for (argv2, 0..) |arg, i| {
        argv2_z[i] = (try allocator.dupeZ(u8, arg)).ptr;
    }
    defer {
        for (argv2_z[0..argv2.len]) |arg_ptr| {
            if (arg_ptr) |ptr| allocator.free(std.mem.span(ptr));
        }
    }

    const program1_path_z = try allocator.dupeZ(u8, program1_path);
    defer allocator.free(program1_path_z);
    const program2_path_z = try allocator.dupeZ(u8, program2_path);
    defer allocator.free(program2_path_z);

    const fds = try std.posix.pipe();

    const pid1 = try std.posix.fork();
    if (pid1 == 0) {
        std.posix.close(fds[0]);
        try std.posix.dup2(fds[1], 1);
        std.posix.close(fds[1]);
        _ = std.posix.execveZ(program1_path_z, argv1_z, std.c.environ) catch {
            std.posix.exit(1);
        };
        unreachable;
    }

    const pid2 = try std.posix.fork();
    if (pid2 == 0) {
        std.posix.close(fds[1]);
        try std.posix.dup2(fds[0], 0);
        std.posix.close(fds[0]);
        _ = std.posix.execveZ(program2_path_z, argv2_z, std.c.environ) catch {
            std.posix.exit(1);
        };
        unreachable;
    }

    std.posix.close(fds[0]);
    std.posix.close(fds[1]);

    _ = std.posix.waitpid(pid1, 0);
    _ = std.posix.waitpid(pid2, 0);
}
