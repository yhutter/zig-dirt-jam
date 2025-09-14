@header const m = @import("../math.zig")
@ctype mat4 m.Mat4

@vs vs
layout(binding = 0) uniform vs_params {
    mat4 mvp;
};
in vec4 position;
out vec4 color;

void main() {
    gl_Position = mvp * position;
    color = vec4(1.0, 1.0, 1.0, 1.0);
}
@end


@fs fs
in vec4 color;
out vec4 frag_color;

void main() {
    frag_color = color;
}
@end

@program terrain vs fs
