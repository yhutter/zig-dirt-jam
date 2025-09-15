const std = @import("std");
const ig = @import("cimgui");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const simgui = sokol.imgui;
const shader = @import("shaders/terrain.zig");
const zm = @import("zmath");

const Plane = struct {
    vertices: std.ArrayList(f32),
    indices: std.ArrayList(u32),
    size: f32,
};

const state = struct {
    var pass_action: sg.PassAction = .{};
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var plane: Plane = .{
        .vertices = .{},
        .indices = .{},
        .size = 1.0,
    };
    const rotx = 0.0;
    const roty = 0.0;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    const view: zm.Mat = zm.lookAtLh(
        zm.f32x4(0.0, 2.0, 1.0, 1.0), // eye position
        zm.f32x4(0.0, 0.0, 0.0, 1.0), // focus point
        zm.f32x4(0.0, 1.0, 0.0, 0.0), // up direction ('w' coord is zero because this is a vector not a point)
    );
};

fn computeVsParams() shader.VsParams {
    // Rotation matrix
    const rxm = zm.rotationX(state.rotx);
    const rym = zm.rotationY(state.roty);

    // Model Matrix
    const model = zm.mul(rxm, rym);
    const aspect = sapp.widthf() / sapp.heightf();
    // Projection Matrix
    const proj = zm.perspectiveFovLh(std.math.degreesToRadians(60.0), aspect, 0.01, 10.0);
    // Model View Projection Matrix
    const mvp = zm.mul(model, zm.mul(state.view, proj));
    return shader.VsParams{ .mvp = mvp };
}

fn makePlane(division: usize, size: f32) !Plane {
    var plane: Plane = .{
        .vertices = .{},
        .indices = .{},
        .size = size,
    };
    const allocator = state.arena_allocator.allocator();
    const num_vertices = (division + 1) * (division + 1);
    try plane.vertices.ensureTotalCapacity(allocator, num_vertices * 3);

    const division_f: f32 = @floatFromInt(division);
    const triangle_side = size / division_f;
    const center = size * 0.5;
    for (0..(division + 1)) |row| {
        for (0..(division + 1)) |col| {
            const col_f: f32 = @floatFromInt(col);
            const row_f: f32 = @floatFromInt(row);
            const x: f32 = col_f * triangle_side;
            const y = 0.0;
            const z = row_f * triangle_side;
            try plane.vertices.append(allocator, x - center);
            try plane.vertices.append(allocator, y);
            try plane.vertices.append(allocator, z - center);
        }
    }

    // Construct indices
    const num_indices = division * division * 2 * 3;
    try plane.indices.ensureTotalCapacity(allocator, num_indices);

    for (0..division) |row| {
        for (0..division) |col| {
            // Top triangle
            //   ---
            //   | /
            //   |/ <- index0
            const index0: u32 = @intCast(row * (division + 1) + col);
            const index1: u32 = @intCast(index0 + (division + 1) + 1);
            const index2: u32 = @intCast(index0 + (division + 1));
            try plane.indices.append(allocator, index0);
            try plane.indices.append(allocator, index1);
            try plane.indices.append(allocator, index2);

            // Bottom triangle
            //             /|
            //            / |
            // index0 -> /__|
            const index3: u32 = @intCast(index0 + 1);
            const index4: u32 = @intCast(index0 + (division + 1) + 1);
            try plane.indices.append(allocator, index0);
            try plane.indices.append(allocator, index3);
            try plane.indices.append(allocator, index4);
        }
    }

    return plane;
}

export fn init() void {
    // Initialize sokol
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    state.plane = makePlane(32, 1.0) catch unreachable;

    // Initialize imgui
    simgui.setup(.{ .logger = .{ .func = slog.func } });

    // Setup render pass action
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    };

    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(state.plane.vertices.items),
        .label = "terrain-vertices",
    });

    state.bind.index_buffer = sg.makeBuffer(.{
        .usage = .{ .index_buffer = true },
        .data = sg.asRange(state.plane.indices.items),
        .label = "terrain-indices",
    });

    const shd = sg.makeShader(shader.terrainShaderDesc(sg.queryBackend()));
    state.pip = sg.makePipeline(.{
        .shader = shd,
        .index_type = .UINT32,
        .primitive_type = .LINE_STRIP,
        .cull_mode = .NONE,
        .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true },
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shader.ATTR_terrain_position].format = .FLOAT3;
            break :init l;
        },
        .label = "terrain-pipeline",
    });
}

export fn frame() void {
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });

    const debugPanelWidth = 400.0;
    const debugPanelHeight = 200.0;
    ig.igSetNextWindowPos(.{ .x = sapp.widthf() - debugPanelWidth - 10, .y = 10 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = debugPanelWidth, .y = debugPanelHeight }, ig.ImGuiCond_Once);
    if (ig.igBegin("Zig Dirt Jam", null, ig.ImGuiWindowFlags_None)) {
        _ = ig.igColorEdit3(
            "Background",
            &state.pass_action.colors[0].clear_value.r,
            ig.ImGuiColorEditFlags_None,
        );
    }
    ig.igEnd();

    const vs_params = computeVsParams();

    const num_indices: u32 = @intCast(state.plane.indices.items.len);

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(shader.UB_vs_params, sg.asRange(&vs_params));
    sg.draw(0, num_indices, 1);
    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    state.arena_allocator.deinit();
    simgui.shutdown();
    sg.shutdown();
}

export fn event(ev: [*c]const sapp.Event) void {
    const e = ev.*;
    _ = simgui.handleEvent(e);
    if (e.type == .KEY_DOWN) {
        if (e.key_code == .ESCAPE) {
            sapp.requestQuit();
        }
    }
}

pub fn main() !void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .window_title = "Zig Dirt Jam",
        .width = 1920,
        .height = 1080,
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
    });
}
