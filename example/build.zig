const std = @import("std");
const demo_webserver = @import("demo_webserver");

pub fn build(b: *std.Build) void {
    b.installFile("src/index.html", "index.html");
    b.installFile("src/second_page.html", "second_page.html");

    demo_webserver.addDemoServer(b, b.getInstallStep(), .{});
}
