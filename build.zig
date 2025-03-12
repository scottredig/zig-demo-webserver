const live_webserver = @This();
const std = @import("std");

pub const DemoServerOptions = struct {
    step_name: []const u8 = "serve",
    step_description: []const u8 = "serve website locally",
    port: u16 = 8080,
};

// pub fn addDemoServer(b: *std.Build, root_directory: std.Build.LazyPath, options: DemoServerOptions) void {
pub fn addDemoServer(b: *std.Build, build_step: *std.Build.Step, options: DemoServerOptions) void {
    const optimize: std.builtin.OptimizeMode = .ReleaseSafe;
    const dep = b.dependencyFromBuildZig(@This(), .{
        .optimize = optimize,
    });
    const run_server = b.addRunArtifact(dep.artifact("server"));
    run_server.addArg(b.fmt("{d}", .{options.port}));
    // run_server.addDirectoryArg(root_directory);
    run_server.addArg(b.getInstallPath(.prefix, ""));
    run_server.step.dependOn(build_step);

    const named_step = b.step(options.step_name, options.step_description);
    named_step.dependOn(&run_server.step);
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
