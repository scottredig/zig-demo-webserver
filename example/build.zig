const std = @import("std");
const demo_webserver = @import("demo_webserver");

pub fn build(b: *std.Build) void {
    b.installFile("src/index.html", "index.html");
    b.installFile("src/second_page.html", "second_page.html");

    // Depend on the install step to run before running the webserver, implicitly
    // uses b.getInstallPath.  See the root build.zig for additional options.
    const run_demo_server = demo_webserver.runDemoServer(b, b.getInstallStep(), .{});
    const serve = b.step("serve", "serve website locally");
    serve.dependOn(run_demo_server);
}
