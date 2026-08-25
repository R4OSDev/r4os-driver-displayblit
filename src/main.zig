const r4os = @import("r4os");

const backend_name: [:0]const u8 = "DISPBLIT";
const max_regions: u32 = r4os.abi.display_damage_max_regions;
const Vector8 = @Vector(8, u32);

var registered = false;
var presents: u64 = 0;
var regions_presented: u64 = 0;
var pixels_presented: u64 = 0;

var backend = r4os.abi.DisplayBlitBackend{
    .flags = r4os.abi.display_blit_backend_flag_xrgb32 |
        r4os.abi.display_blit_backend_flag_synchronous |
        r4os.abi.display_blit_backend_flag_self_tested |
        r4os.abi.display_blit_backend_flag_cpu_fast_copy,
    .max_regions = max_regions,
    .present = present,
};

comptime {
    asm (r4os.r4dev.driverEntriesAsm("display_blit_init", "display_blit_shutdown"));
}

export fn display_blit_init(api: *const r4os.r4dev.DriverApi) callconv(.c) i32 {
    var ctx = r4os.r4dev.DriverContext.init(api);
    if (!ctx.apiCompatible()) {
        ctx.logError("DISPBLIT.R4D driver api mismatch");
        return -1;
    }
    saved_api = api;
    if (!selfTest()) {
        ctx.logError("DISPBLIT.R4D bounded copy self-test failed");
        return -2;
    }
    presents = 0;
    regions_presented = 0;
    pixels_presented = 0;
    const result = ctx.registerDisplayBlitBackend(backend_name, &backend);
    if (result != 0) {
        ctx.logError("DISPBLIT.R4D backend registration failed");
        return result;
    }
    registered = true;
    ctx.logInfo("DISPBLIT.R4D ready: xrgb32 regions=8 sync-fence selftest=OK");
    return 0;
}

export fn display_blit_shutdown() callconv(.c) i32 {
    if (!registered) {
        saved_api = null;
        return 0;
    }
    const api = driverApi() orelse return -1;
    const result = api.unregister_display_blit_backend(backend_name);
    if (result == 0) {
        registered = false;
        saved_api = null;
    }
    return result;
}

// The callback borrows all addresses for this call only. Validation is
// repeated at the module boundary before the first visible write; the kernel
// has already validated the same complete job and owns the fallback.
fn present(_: usize, job: *const r4os.abi.DisplayBlitJob) callconv(.c) i32 {
    if (!validJob(job)) return -1;
    const target: [*]volatile u32 = @ptrFromInt(job.target_address);
    const source: [*]const u32 = @ptrFromInt(job.source_address);
    const regions: [*]const r4os.abi.DisplayBlitRegion = @ptrFromInt(job.regions_address);

    var region_index: u32 = 0;
    var changed_pixels: u64 = 0;
    while (region_index < job.region_count) : (region_index += 1) {
        const region = regions[region_index];
        if (!validRegion(job, region)) return -2;
        copyRegion(target, source, job.target_pitch_pixels, job.source_stride_pixels, region);
        changed_pixels += @as(u64, region.w) * region.h;
    }
    asm volatile ("sfence" ::: .{ .memory = true });
    presents +%= 1;
    regions_presented +%= job.region_count;
    pixels_presented +%= changed_pixels;
    return 0;
}

fn validJob(job: *const r4os.abi.DisplayBlitJob) bool {
    return @intFromPtr(job) != 0 and
        job.version == r4os.abi.display_blit_backend_version and
        job.size >= @sizeOf(r4os.abi.DisplayBlitJob) and
        job.format == r4os.abi.display_present_format_xrgb32 and
        job.target_address != 0 and job.source_address != 0 and job.regions_address != 0 and
        job.target_width != 0 and job.target_height != 0 and
        job.target_pitch_pixels >= job.target_width and job.source_stride_pixels != 0 and
        job.source_pixel_count != 0 and job.region_count != 0 and job.region_count <= max_regions and
        (job.target_address & 3) == 0 and (job.source_address & 3) == 0 and (job.regions_address & 3) == 0;
}

fn validRegion(job: *const r4os.abi.DisplayBlitJob, region: r4os.abi.DisplayBlitRegion) bool {
    if (region.w == 0 or region.h == 0 or region.src_x >= job.source_stride_pixels) return false;
    if (region.w > job.source_stride_pixels - region.src_x) return false;
    if (region.dst_x >= job.target_width or region.dst_y >= job.target_height) return false;
    if (region.w > job.target_width - region.dst_x or region.h > job.target_height - region.dst_y) return false;
    const last_end = (@as(u64, region.src_y) + region.h - 1) * job.source_stride_pixels + region.src_x + region.w;
    return last_end <= job.source_pixel_count;
}

fn copyRegion(
    target: [*]volatile u32,
    source: [*]const u32,
    target_pitch: u32,
    source_stride: u32,
    region: r4os.abi.DisplayBlitRegion,
) void {
    var y: u32 = 0;
    while (y < region.h) : (y += 1) {
        const source_row = (@as(usize, region.src_y) + y) * source_stride + region.src_x;
        const target_row = (@as(usize, region.dst_y) + y) * target_pitch + region.dst_x;
        var x: u32 = 0;
        while (x + 8 <= region.w) : (x += 8) {
            const source_vector: *align(4) const Vector8 = @ptrCast(&source[source_row + x]);
            const target_vector: *align(4) volatile Vector8 = @ptrCast(&target[target_row + x]);
            target_vector.* = source_vector.*;
        }
        while (x < region.w) : (x += 1) target[target_row + x] = source[source_row + x];
    }
}

fn selfTest() bool {
    var source: [96]u32 align(32) = undefined;
    var target: [96]u32 align(32) = .{0xA5A5_A5A5} ** 96;
    for (&source, 0..) |*pixel, index| pixel.* = 0x1100_0000 | @as(u32, @intCast(index));
    const regions = [_]r4os.abi.DisplayBlitRegion{
        .{ .dst_x = 2, .dst_y = 1, .src_x = 5, .src_y = 0, .w = 10, .h = 2 },
        .{ .dst_x = 20, .dst_y = 2, .src_x = 1, .src_y = 2, .w = 5, .h = 1 },
    };
    const job = r4os.abi.DisplayBlitJob{
        .target_address = @intFromPtr(&target),
        .target_width = 32,
        .target_height = 3,
        .target_pitch_pixels = 32,
        .source_pixel_count = source.len,
        .source_address = @intFromPtr(&source),
        .source_stride_pixels = 32,
        .region_count = regions.len,
        .regions_address = @intFromPtr(&regions),
    };
    if (present(0, &job) != 0) return false;
    var y: usize = 0;
    while (y < 3) : (y += 1) {
        var x: usize = 0;
        while (x < 32) : (x += 1) {
            const first = y >= 1 and y < 3 and x >= 2 and x < 12;
            const second = y == 2 and x >= 20 and x < 25;
            const expected = if (first)
                source[(y - 1) * 32 + 5 + (x - 2)]
            else if (second)
                source[2 * 32 + 1 + (x - 20)]
            else
                0xA5A5_A5A5;
            if (target[y * 32 + x] != expected) return false;
        }
    }
    return true;
}

fn driverApi() ?*const r4os.r4dev.DriverApi {
    // The R4D entry ABI passes the stable table once. Keeping the pointer is
    // permitted for the resident lifetime and avoids any second ownership.
    return saved_api;
}

var saved_api: ?*const r4os.r4dev.DriverApi = null;

comptime {
    _ = &presents;
    _ = &regions_presented;
    _ = &pixels_presented;
}
