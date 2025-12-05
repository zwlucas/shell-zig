const std = @import("std");

pub fn findInPath(allocator: std.mem.Allocator, cmd_name: []const u8) !?[]const u8 {
    const path_env = std.process.getEnvVarOwned(allocator, "PATH") catch return null;
    defer allocator.free(path_env);

    var it = std.mem.splitScalar(u8, path_env, ':');
    while (it.next()) |dir| {
        const full_path = std.fs.path.join(allocator, &[_][]const u8{ dir, cmd_name }) catch continue;
        defer allocator.free(full_path);

        const file = std.fs.openFileAbsolute(full_path, .{}) catch continue;
        const stat = file.stat() catch {
            file.close();
            continue;
        };
        file.close();

        if ((stat.mode & 0o111) == 0) continue;

        return try allocator.dupe(u8, full_path);
    }

    return null;
}
