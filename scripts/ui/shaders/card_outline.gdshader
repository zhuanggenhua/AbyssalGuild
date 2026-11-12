shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back;
// Independent translation of the referenced outline graph, in source card space.
uniform mat4 mesh_to_card = mat4(1.0);
uniform mat4 card_to_mesh = mat4(1.0);
uniform float outline_size;
uniform vec4 outline_color : source_color;
uniform float min_alpha;
uniform float rotation_speed;
uniform float unscaled_time;
void vertex() {
    vec3 position = (mesh_to_card * vec4(VERTEX, 1.0)).xyz;
    vec3 camera_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
    vec3 direction = normalize((mesh_to_card * vec4(camera_local - VERTEX, 0.0)).xyz);
    position.xz *= 1.0 + outline_size;
    position -= direction * vec3(0.0, 0.001, 0.0);
    VERTEX = (card_to_mesh * vec4(position, 1.0)).xyz;
}
void fragment() {
    vec2 source_uv = vec2(UV.x, 1.0 - UV.y) - vec2(0.5);
    float angle = atan(source_uv.y, source_uv.x);
    float phase = fract((angle + unscaled_time * rotation_speed) / 6.283180236816406);
    ALBEDO = outline_color.rgb;
    ALPHA = outline_color.a * mix(1.0, min_alpha, phase);
}
