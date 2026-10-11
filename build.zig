const live_webserver = @This();
const std = @import("std");

pub const DemoServerOptions = struct {
    port: u16 = 8080,
    additional_headers: []const std.http.Header = &.{},
};

pub fn runDemoServer(b: *std.Build, files: *std.Build.Step.WriteFile, options: DemoServerOptions) *std.Build.Step {
    const optimize: std.builtin.OptimizeMode = .ReleaseSafe;
    const dep = b.dependencyFromBuildZig(@This(), .{
        .optimize = optimize,
    });
    const run_server = b.addRunArtifact(dep.artifact("server"));
    run_server.addArg(b.fmt("{d}", .{options.port}));
    run_server.addDirectoryArg2(files.getDirectory(), .{});
    for (options.additional_headers) |header| {
        run_server.addArg(header.name);
        run_server.addArg(header.value);
    }

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
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    server.root_module.addImport("mime", mime.module("mime"));

    b.installArtifact(server);
}
