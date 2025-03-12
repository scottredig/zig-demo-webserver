const live_webserver = @This();
const std = @import("std");

pub const DemoServerOptions = struct {
    port: u16 = 8080,
};

pub fn runDemoServer(b: *std.Build, build_step: *std.Build.Step, options: DemoServerOptions) *std.Build.Step {
    const optimize: std.builtin.OptimizeMode = .ReleaseSafe;
    const dep = b.dependencyFromBuildZig(@This(), .{
        .optimize = optimize,
    });
    const run_server = b.addRunArtifact(dep.artifact("server"));
    run_server.addArg(b.fmt("{d}", .{options.port}));
    // Would prefer to get a LazyPath from build_step, but don't see a way to do that.
    run_server.addArg(b.getInstallPath(.prefix, ""));
    run_server.step.dependOn(build_step);

    return &run_server.step;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mime = b.dependency("mime", .{
        .target = target,
        .optimize = optimize,
    });

    const server = b.addExecutable(.{
        .name = "server",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    server.root_module.addImport("mime", mime.module("mime"));

    b.installArtifact(server);
}
