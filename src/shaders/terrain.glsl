@header const zm = @import("zmath")
@ctype mat4 zm.Mat

@vs vs
layout(binding = 0) uniform vs_params {
    vec4 base_color;
    mat4 mvp;
};
in vec4 position;
out vec4 color;

void main() {
    gl_Position = mvp * position;
    color = base_color;
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
