const std = @import("std");
const root = @import("root.zig");
const print = std.debug.print;
const testing = std.testing;
const allocator = root.allocator;
const libbpf = root.libbpf;

test "iterator" {
    const obj_bytes = @embedFile("@iterator");
    const bytes = try allocator.dupe(u8, obj_bytes);
    defer allocator.free(bytes);

    _ = libbpf.libbpf_set_print(root.dbg_printf);

    const obj = libbpf.bpf_object__open_mem(bytes.ptr, bytes.len, null);
    if (obj == null) {
        print("failed to open bpf object: {}\n", .{std.os.errno(-1)});
        return error.OPEN;
    }
    defer libbpf.bpf_object__close(obj);

    var ret = libbpf.bpf_object__load(obj);
    if (ret != 0) {
        print("failed to load bpf object: {}\n", .{std.os.errno(-1)});
        return error.LOAD;
    }

    if (libbpf.bpf_object__next_program(obj, null)) |prog| {
        const link = libbpf.bpf_program__attach_iter(prog, null).?;
        const fd = libbpf.bpf_iter_create(libbpf.bpf_link__fd(link));
        var r = (std.fs.File{ .handle = fd }).reader();

        const expect = blk: {
            var n: u64 = 0;
            var id: u32 = 0;

            while (true) : (n += 1) {
                ret = libbpf.bpf_map_get_next_id(id, &id);
                if (ret != 0) break;
            }

            break :blk n;
        };

        var got: u64 = undefined;
        while (true) {
            got = r.readIntNative(u64) catch |e| switch (e) {
                error.EndOfStream => break,
                else => return e,
            };
        }
        try testing.expectEqual(expect, got);
    }
}