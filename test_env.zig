const std = @import("std");

pub fn main() !void {
    const env = std.os.environ;
    std.debug.print("env type: {any}\n", .{@TypeOf(env)});
    std.debug.print("env ptr type: {any}\n", .{@TypeOf(env.ptr)});
}
