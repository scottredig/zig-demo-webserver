const std = @import("std");
const demo_webserver = @import("demo_webserver");

pub fn build(b: *std.Build) void {

    const write_files = b.addWriteFiles();
    _ = write_files.addCopyDirectory(b.path("src"), "", .{});

    const run_demo_server = demo_webserver.runDemoServer(b, write_files, .{
        .additional_headers = &.{
            .{ .name = "foo", .value = "hello world" },
            .{ .name = "bar", .value = "such and such" },
        },
    });
    const serve = b.step("serve", "serve website locally");
    serve.dependOn(run_demo_server);
}
