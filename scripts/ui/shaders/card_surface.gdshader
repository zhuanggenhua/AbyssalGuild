shader_type spatial;
render_mode cull_disabled;

// Independent material adapter. Inputs come only from the private manifest.
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D overlay_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 overlay_tint : source_color = vec4(1.0);
uniform vec2 overlay_offset = vec2(0.0);
uniform float overlay_scale = 1.0;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 selection_emission = vec3(0.0);

void fragment() {
    // Godot's imported UV/PNG convention is top-left; source UV is bottom-left.
    vec2 source_uv = vec2(UV.x, 1.0 - UV.y);
    vec2 art_uv = (source_uv - overlay_offset) / overlay_scale;
    vec4 art = texture(overlay_texture, vec2(art_uv.x, 1.0 - art_uv.y)) * overlay_tint;
    vec2 edge = abs(art_uv * 2.0 - 1.0);
    vec2 coverage = clamp((vec2(1.0) - edge) / max(fwidth(edge), vec2(0.000001)), vec2(0.0), vec2(1.0));
    art *= min(coverage.x, coverage.y);
    vec3 color = mix(texture(base_texture, UV).rgb, art.rgb, art.a);
    ALBEDO = mix(color, vec3(1.0), flash_amount) * (1.0 + flash_amount * 0.5);
    METALLIC = 0.0;
    ROUGHNESS = 1.0;
    EMISSION = selection_emission;
}
