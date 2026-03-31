const std = @import("std");

pub fn main() !void {
    const path = "ls";
    const argv = [_:null]?[*:0]const u8{ "ls", null };
    const envp = [_:null]?[*:0]const u8{ null };
    const err = std.posix.execveZ(path, &argv, &envp);
    std.debug.print("error: {any}\n", .{err});
}
