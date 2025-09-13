const std = @import("std");
const ig = @import("cimgui");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const simgui = sokol.imgui;

const state = struct {
    var pass_action: sg.PassAction = .{};
};

export fn init() void {
    // Initialize sokol
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    // Initialize imgui
    simgui.setup(.{ .logger = .{ .func = slog.func } });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
    };
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

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });
    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
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
