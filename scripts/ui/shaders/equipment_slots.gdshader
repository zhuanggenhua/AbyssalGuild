shader_type spatial;
render_mode unshaded, cull_disabled;

// Independent three-slot occupancy composition; media stays private.
uniform sampler2D overlay_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 active_color : source_color = vec4(1.0);
uniform vec4 inactive_color : source_color = vec4(0.25, 0.25, 0.25, 1.0);
uniform vec3 active_slots = vec3(0.0);

void fragment() {
    float second = step(0.3333, UV.x);
    float third = step(0.6666, UV.x);
    float enabled = dot(vec3(1.0 - second, second - third, third), active_slots);
    vec4 icon = texture(overlay_texture, UV);
    vec3 tint = mix(inactive_color.rgb, active_color.rgb, enabled);
    ALBEDO = mix(base_color.rgb, icon.rgb * tint, icon.a);
}
