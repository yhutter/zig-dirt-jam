@header const zm = @import("zmath")
@ctype mat4 zm.Mat

@block noise_functions

// https://thebookofshaders.com/edit.php#11/2d-snoise-clear.frag
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x*34.0)+1.0)*x); }

//
// Description : GLSL 2D simplex noise function
//      Author : Ian McEwan, Ashima Arts
//  Maintainer : ijm
//     Lastmod : 20110822 (ijm)
//     License :
//  Copyright (C) 2011 Ashima Arts. All rights reserved.
//  Distributed under the MIT License. See LICENSE file.
//  https://github.com/ashima/webgl-noise
//
float snoise(vec2 v) {

    // Precompute values for skewed triangular grid
    const vec4 C = vec4(0.211324865405187,
                        // (3.0-sqrt(3.0))/6.0
                        0.366025403784439,
                        // 0.5*(sqrt(3.0)-1.0)
                        -0.577350269189626,
                        // -1.0 + 2.0 * C.x
                        0.024390243902439);
                        // 1.0 / 41.0

    // First corner (x0)
    vec2 i  = floor(v + dot(v, C.yy));
    vec2 x0 = v - i + dot(i, C.xx);

    // Other two corners (x1, x2)
    vec2 i1 = vec2(0.0);
    i1 = (x0.x > x0.y)? vec2(1.0, 0.0):vec2(0.0, 1.0);
    vec2 x1 = x0.xy + C.xx - i1;
    vec2 x2 = x0.xy + C.zz;

    // Do some permutations to avoid
    // truncation effects in permutation
    i = mod289(i);
    vec3 p = permute(
            permute( i.y + vec3(0.0, i1.y, 1.0))
                + i.x + vec3(0.0, i1.x, 1.0 ));

    vec3 m = max(0.5 - vec3(
                        dot(x0,x0),
                        dot(x1,x1),
                        dot(x2,x2)
                        ), 0.0);

    m = m*m ;
    m = m*m ;

    // Gradients:
    //  41 pts uniformly over a line, mapped onto a diamond
    //  The ring size 17*17 = 289 is close to a multiple
    //      of 41 (41*7 = 287)

    vec3 x = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;

    // Normalise gradients implicitly by scaling m
    // Approximation of: m *= inversesqrt(a0*a0 + h*h);
    m *= 1.79284291400159 - 0.85373472095314 * (a0*a0+h*h);

    // Compute final noise value at P
    vec3 g = vec3(0.0);
    g.x  = a0.x  * x0.x  + h.x  * x0.y;
    g.yz = a0.yz * vec2(x1.x,x2.x) + h.yz * vec2(x1.y,x2.y);
    return 130.0 * dot(m, g);
}

// Normal calculation based on center difference method: https://iquilezles.org/articles/terrainmarching/
vec3 normal_snoise(vec3 p, float step_size) {
    return normalize(
        vec3(
            snoise(vec2(p.x - step_size, p.z)) - snoise(vec2(p.x + step_size, p.z)),
            2.0f * step_size,
            snoise(vec2(p.x, p.z - step_size)) - snoise(vec2(p.x, p.z + step_size))
        )
    );
}
@end



@vs vs
@include_block noise_functions

layout(binding = 0) uniform vs_params {
    vec3 base_color;
    vec3 peak_color;
    float noise_frequency;
    float noise_amplitude;
    float normal_step_size;
    mat4 model_matrix;
    mat4 mvp;
    vec3 camera_position;
};
layout(location = 0) in vec4 position;
out vec4 color;
out vec3 normal;
out vec3 position_world;
out vec3 camera;

void main() {
    float displacement = snoise(position.xz * noise_frequency) * noise_amplitude;
    vec4 displaced_position = vec4(position.x, position.y + displacement, position.z, position.w);
    gl_Position = mvp * displaced_position;

    vec3 mix_color = vec3(0.0);
    // Simplex noise returns value between -1 and 1 remap to 0 and 1
    float mix_value = (displacement * 0.5) + 0.5;
    mix_color = mix(base_color, peak_color, mix_value);
    color = vec4(mix_color, 1.0);

    vec3 calculated_normal = vec3(0.0);
    calculated_normal = normal_snoise(position.xyz, normal_step_size);
    normal = (model_matrix * vec4(calculated_normal, 0.0f)).xyz;

    position_world = (model_matrix * displaced_position).xyz;
    camera = camera_position;
}
@end


@fs fs
in vec4 color;
in vec3 normal;
in vec3 position_world;
in vec3 camera;
out vec4 frag_color;

void main() {
    vec3 normalized_normal = normalize(normal);
    vec3 view_direction = normalize(camera - position_world);

    vec3 base_colour = color.rgb;
    vec3 lighting = vec3(0.0f);

    // Ambient
    vec3 ambient = vec3(0.5);

    // Diffuse
    vec3 light_dir = normalize(vec3(1.0, 1.0, 1.0));
    vec3 light_color = vec3(1.0, 1.0, 1.0);
    float dp = max(0.0, dot(light_dir, normalized_normal));

    // Cell Shading
    dp *= smoothstep(0.5, 0.505, dp);

    vec3 diffuse = dp * light_color;

    // Lighting is sum of all lighting sources.
    lighting = diffuse * 0.8;

    vec3 colour = base_colour * lighting;

    // Appromixation of converting from linear to srgb color space.
    colour = pow(colour, vec3(1.0 / 2.2));

    frag_color = vec4(colour, 1.0f);
}
@end

@program terrain vs fs
