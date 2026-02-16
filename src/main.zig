const std = @import("std");
const mime = @import("mime");

pub const std_options: std.Options = .{
    .log_level = .info,
};
const log = std.log;

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main(init: std.process.Init) void {
    const gpa = init.gpa;
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch |err| failWithError("Parse arguments", err);
    const io = init.io;

    if (args.len != 3) {
        failWithError("Parse arguments", error.IncorrectNumberOfArguments);
    }
    log.info("server args: {s} {s} {s}", .{ args[0], args[1], args[2] });

    const port = std.fmt.parseInt(u16, args[1], 10) catch |err| failWithError("Parse port", err);
    const root_dir_path = args[2];

    var root_dir: std.Io.Dir = std.Io.Dir.cwd().openDir(io, root_dir_path, .{}) catch |err| failWithError("Open serving directory", err);
    defer root_dir.close();

    const address = std.Io.net.IpAddress.parse("127.0.0.1", port) catch |err| failWithError("obtain ip", err);
    var tcp_server = address.listen(io, .{
        .reuse_address = true,
    }) catch |err| failWithError("listen", err);
    defer tcp_server.deinit();

    log.warn("\x1b[2K\rServing website at http://{f}/\n", .{tcp_server.socket.address});

    var group: std.Io.Group = .init;

    accept: while (true) {
        const request = gpa.create(Request) catch |err| {
            failWithError("allocating request", err);
        };
        request.* = .{
            .io = io,
            .gpa = gpa,
            .public_dir = root_dir,
            .stream = undefined,

            .allocator_arena = undefined,
            .allocator = undefined,
            .http = undefined,
            .read_buffer = undefined,
            .write_buffer = undefined,
        };
        request.stream = tcp_server.accept(io) catch |err| {
            switch (err) {
                error.ConnectionAborted => {
                    log.warn("{s} on lister accept", .{@errorName(err)});
                    gpa.destroy(request);
                    continue :accept;
                },
                else => {},
            }
            failWithError("accept connection", err);
        };

        // Can't use async because it's not guaranteed to run until group.await.
        group.concurrent(io, Request.handle, .{request}) catch |err| switch (err) {
            error.ConcurrencyUnavailable => request.handle(),
        };
    }
}

fn failWithError(operation: []const u8, err: anytype) noreturn {
    std.debug.print("Unrecoverable Failure: {s} encountered error {s}.\n", .{ operation, @errorName(err) });
    std.process.exit(1);
}

const Request = struct {
    io: std.Io,
    // Fields are in initialization order.
    // Initialized by main.
    gpa: std.mem.Allocator,
    public_dir: std.Io.Dir,
    stream: std.Io.net.Stream,
    // Initialized by handle.
    allocator_arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    http: std.http.Server.Request,

    read_buffer: [1024]u8,
    write_buffer: [1024]u8,

    fn handle(req: *Request) void {
        defer req.gpa.destroy(req);
        defer req.stream.close(req.io);

        req.allocator_arena = std.heap.ArenaAllocator.init(req.gpa);
        defer req.allocator_arena.deinit();
        req.allocator = req.allocator_arena.allocator();

        var reader = req.stream.reader(req.io, &req.read_buffer);
        var writer = req.stream.writer(req.io, &req.write_buffer);

        var http_server = std.http.Server.init(&reader.interface, &writer.interface);
        req.http = http_server.receiveHead() catch |err| {
            if (err != error.HttpConnectionClosing) {
                log.err("Error with getting request headers:{s}", .{@errorName(err)});
                // TODO: We're supposed to serve an error to the request on some of these
                // error types, but the http server doesn't give us the response to write to,
                // so we're not going to bother doing it manually.
            }
            return;
        };
        req.handleFile() catch |err| {
            log.warn("Error {s} responding to request from {any} for {s}", .{ @errorName(err), req.stream.socket.address, req.http.head.target });
        };
    }

    const common_headers = [_]std.http.Header{
        .{ .name = "connection", .value = "close" },
        .{ .name = "Cache-Control", .value = "no-cache, no-store, must-revalidate" },
    };

    fn handleFile(req: *Request) !void {
        var path = req.http.head.target;

        if (std.mem.indexOf(u8, path, "..")) |_| {
            req.serveError("'..' not allowed in URLs", .bad_request);

            // Improvement: Allow relative paths while ensuring that directories
            // outside of the served directory can never be accessed.
            return error.BadPath;
        }

        if (std.mem.endsWith(u8, path, "/")) {
            path = try std.fmt.allocPrint(req.allocator, "{s}{s}", .{
                path,
                "index.html",
            });
        }

        if (path.len < 1 or path[0] != '/') {
            req.serveError("bad request path.", .bad_request);
            return error.BadPath;
        }

        path = path[1 .. std.mem.indexOfScalar(u8, path, '?') orelse path.len];

        const mime_type = mime.extension_map.get(std.fs.path.extension(path)) orelse
            .@"application/octet-stream";

        const file = req.public_dir.openFile(req.io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                req.serveError(null, .not_found);
                if (std.mem.eql(u8, path, "favicon.ico")) {
                    return; // Surpress error logging.
                }
                return err;
            },
            else => {
                req.serveError("accessing resource", .internal_server_error);
                return err;
            },
        };
        defer file.close(req.io);

        const stat = file.stat(req.io) catch |err| {
            req.serveError("accessing resource", .internal_server_error);
            return err;
        };
        if (stat.kind == .directory) {
            const location = try std.fmt.allocPrint(
                req.allocator,
                "{s}/",
                .{req.http.head.target},
            );
            try req.http.respond("redirecting...", .{
                .status = .see_other,
                .extra_headers = &([_]std.http.Header{
                    .{ .name = "location", .value = location },
                    .{ .name = "content-type", .value = "text/html" },
                } ++ common_headers),
            });
            return;
        }

        const content_type = switch (mime_type) {
            inline else => |mt| blk: {
                if (std.mem.startsWith(u8, @tagName(mt), "text")) {
                    break :blk @tagName(mt) ++ "; charset=utf-8";
                }
                break :blk @tagName(mt);
            },
        };

        var response = try req.http.respondStreaming(try req.allocator.alloc(u8, 4000), .{
            // .content_length = metadata.size(),
            .respond_options = .{
                .extra_headers = &([_]std.http.Header{
                    .{ .name = "content-type", .value = content_type },
                } ++ common_headers),
            },
        });

        var file_reader = file.reader(req.io, &.{});
        _ = try response.writer.sendFileAll(&file_reader, .unlimited);
        return response.end();
    }

    fn serveError(req: *Request, comptime reason: ?[]const u8, comptime status: std.http.Status) void {
        const sep = if (reason) |_| ": " else ".";
        const text = std.fmt.comptimePrint("{d} {s}{s}{s}", .{ @intFromEnum(status), comptime status.phrase().?, sep, reason orelse "" });
        req.http.respond(text, .{
            .status = status,
            .extra_headers = &([_]std.http.Header{
                .{ .name = "content-type", .value = "text/text" },
            } ++ common_headers),
        }) catch |err| {
            log.warn("Error {s} serving error text {s}", .{ @errorName(err), text });
        };
    }
};
