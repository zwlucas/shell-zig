const std = @import("std");

pub fn main() !void {
    const path = "/nix/store/74sind1d6vf2bfwd7yklg8chsvzqxmmq-coreutils-9.10/bin/ls";
    
    var argv_buf = [_:null]?[*:0]const u8{ "ls", null };
    const envp = std.os.environ.ptr;
    
    const err = std.posix.execveZ(path, &argv_buf, @ptrCast(envp));
    std.debug.print("execve failed: {any}\n", .{err});
}
