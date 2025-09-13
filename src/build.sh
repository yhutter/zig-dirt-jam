# Compile shaders
sokol-shdc -i terrain.glsl -l metal_macos:glsl430:hlsl5 -f sokol_zig -o terrain.zig

# Build and run
zig build run
