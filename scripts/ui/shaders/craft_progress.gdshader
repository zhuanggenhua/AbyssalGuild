shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D source_sprite : source_color, filter_linear, repeat_disable;
uniform vec4 background : source_color;
uniform vec4 fill_color : source_color;
uniform float ratio = 0.0;
void fragment() {
    // One coplanar surface implements background then Image.Filled in source order.
    // UV is cropped, not squeezed into the current fill fraction.
    vec4 fg = texture(source_sprite, UV) * fill_color;
    fg.a *= (ratio > 0.0 && UV.x <= ratio) ? 1.0 : 0.0;
    float a = fg.a + background.a * (1.0 - fg.a);
    vec3 premul = fg.rgb * fg.a + background.rgb * background.a * (1.0 - fg.a);
    ALBEDO = a > 0.0 ? premul / a : vec3(0.0);
    ALPHA = a;
}
