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

const Camera = struct {
    position: zm.Vec,
    target_position: zm.Vec,
    front: zm.Vec,
    up: zm.Vec,
    smoothness: f32,
    speed: f32,
    yaw: f32,
    pitch: f32,
};

const State = struct {
    pass_action: sg.PassAction,
    bind: sg.Bindings,
    pip: sg.Pipeline,
    plane: Plane,
    mouse_locked: bool,
    camera: Camera,
    rotation_x: f32,
    rotation_y: f32,
    base_color: [4]f32,
    noise_frequency: f32,
    noise_amplitude: f32,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var arena = std.heap.ArenaAllocator.init(gpa.allocator());

var state: State = .{
    .pass_action = .{},
    .pip = .{},
    .bind = .{},
    .plane = .{
        .vertices = .{},
        .indices = .{},
        .size = 1.0,
    },
    .camera = .{
        .position = zm.f32x4(0.0, 0.0, 2.0, 1.0),
        .target_position = zm.f32x4(0.0, 0.0, 2.0, 1.0),
        .up = zm.f32x4(0.0, 1.0, 0.0, 0.0),
        .front = zm.f32x4(0.0, 0.0, -1.0, 0.0),
        .smoothness = 8.0,
        .speed = 10.0,
        .yaw = -90.0,
        .pitch = 0.0,
    },
    .mouse_locked = true,
    .rotation_x = 0.0,
    .rotation_y = 0.0,
    .base_color = .{
        @as(f32, 0xF2) / 255.0,
        @as(f32, 0xF4) / 255.0,
        @as(f32, 0xF8) / 255.0,
        @as(f32, 0xff) / 255.0,
    },
    .noise_frequency = 1.0,
    .noise_amplitude = 1.0,
};

fn computeVsParams() shader.VsParams {
    // Rotation matrix
    const rxm = zm.rotationX(state.rotation_x);
    const rym = zm.rotationY(state.rotation_y);

    // Model Matrix
    const model = zm.mul(rxm, rym);
    const aspect = sapp.widthf() / sapp.heightf();

    // Projection Matrix
    const proj = zm.perspectiveFovLh(std.math.degreesToRadians(60.0), aspect, 0.01, 10.0);

    // View Matrix
    const view = zm.lookAtLh(state.camera.position, state.camera.position + state.camera.front, state.camera.up);

    // Model View Projection Matrix
    const mvp = zm.mul(model, zm.mul(view, proj));
    return shader.VsParams{
        .mvp = mvp,
        .base_color = state.base_color,
        .noise_frequency = state.noise_frequency,
        .noise_amplitude = state.noise_amplitude,
    };
}

fn makePlane(division: usize, size: f32) !Plane {
    var plane: Plane = .{
        .vertices = .{},
        .indices = .{},
        .size = size,
    };
    const allocator = arena.allocator();
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

    state.plane = makePlane(64, 1.0) catch unreachable;

    // Initialize imgui
    simgui.setup(.{ .logger = .{ .func = slog.func } });

    // Setup render pass action
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{
            .r = @as(f32, 0x16) / 255.0,
            .g = @as(f32, 0x16) / 255.0,
            .b = @as(f32, 0x16) / 255.0,
            .a = 1.0,
        },
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
        .primitive_type = .TRIANGLES,
        .cull_mode = .NONE,
        .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true },
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shader.ATTR_terrain_position].format = .FLOAT3;
            break :init l;
        },
        .label = "terrain-pipeline",
    });

    sapp.lockMouse(state.mouse_locked);
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
        _ = ig.igColorEdit3(
            "Base Color",
            &state.base_color,
            ig.ImGuiColorEditFlags_None,
        );
        _ = ig.igSliderFloat("Noise Frequency", &state.noise_frequency, 0.0, 5.0);
        _ = ig.igSliderFloat("Noise Amplitude", &state.noise_amplitude, 0.0, 5.0);
    }
    ig.igEnd();

    // Smooth camera position
    const dt = sapp.frameDuration();
    const t: f32 = @floatCast(state.camera.smoothness * dt);
    state.camera.position = state.camera.position * zm.f32x4s(1.0 - t) + (state.camera.target_position * zm.f32x4s(t));

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
    arena.deinit();
    _ = gpa.deinit();
    simgui.shutdown();
    sg.shutdown();
}

export fn event(ev: [*c]const sapp.Event) void {
    const e = ev.*;
    _ = simgui.handleEvent(e);
    const dt: f32 = @floatCast(sapp.frameDuration());
    const camera_speed = zm.f32x4s(state.camera.speed * dt);

    if (e.type == .MOUSE_MOVE and state.mouse_locked) {
        const mouse_sensitivity = 0.05;
        state.camera.yaw += e.mouse_dx * mouse_sensitivity;
        state.camera.pitch += e.mouse_dy * mouse_sensitivity;

        // Limit pitch
        if (state.camera.pitch > 89.0) {
            state.camera.pitch = 89.0;
        }
        if (state.camera.pitch < -89.0) {
            state.camera.pitch = -89.0;
        }
        const x = std.math.cos(std.math.degreesToRadians(state.camera.yaw)) * std.math.cos(std.math.degreesToRadians(state.camera.pitch));
        const y = std.math.sin(std.math.degreesToRadians(state.camera.pitch));
        const z = std.math.sin(std.math.degreesToRadians(state.camera.yaw)) * std.math.cos(std.math.degreesToRadians(state.camera.pitch));
        const direction = zm.f32x4(x, y, z, 0.0);
        state.camera.front = direction;
    }

    if (e.type == .KEY_UP) {
        if (e.key_code == .X) {
            state.mouse_locked = !state.mouse_locked;
            sapp.lockMouse(state.mouse_locked);
        }
    }

    if (e.type == .KEY_DOWN) {
        if (e.key_code == .ESCAPE) {
            sapp.requestQuit();
        }
        if (e.key_code == .W) {
            state.camera.target_position += state.camera.front * camera_speed;
        }
        if (e.key_code == .S) {
            state.camera.target_position -= state.camera.front * camera_speed;
        }
        if (e.key_code == .A) {
            state.camera.target_position += zm.normalize3(zm.cross3(state.camera.front, state.camera.up)) * camera_speed;
        }
        if (e.key_code == .D) {
            state.camera.target_position -= zm.normalize3(zm.cross3(state.camera.front, state.camera.up)) * camera_speed;
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
        .sample_count = 4,
    });
}
