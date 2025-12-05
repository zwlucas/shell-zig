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

pub fn runExternalProgramWithRedirect(allocator: std.mem.Allocator, program_path: []const u8, argv: []const []const u8, output_file: ?[]const u8, error_file: ?[]const u8, append_file: ?[]const u8) !void {
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
        }

        _ = std.posix.execveZ(program_path_z, argv_z, std.c.environ) catch {
            std.posix.exit(1);
        };
        unreachable;
    } else {
        _ = std.posix.waitpid(pid, 0);
    }
}
