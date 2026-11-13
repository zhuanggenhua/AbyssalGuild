shader_type spatial;
render_mode cull_disabled;
uniform vec4 source_base_color : source_color = vec4(1.0);
void fragment() {
    ALBEDO = source_base_color.rgb;
    ROUGHNESS = 1.0;
    METALLIC = 0.0;
}
void light() {
    float cosine = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
    vec3 halfway_sum = LIGHT + VIEW;
    vec3 halfway = halfway_sum * inversesqrt(max(1.175494351e-38, dot(halfway_sum, halfway_sum)));
    float loh = clamp(dot(LIGHT, halfway), 0.0, 1.0);
    float highlight = 0.04 / (6.0 * max(0.1, loh * loh) * 1.00001 * 1.00001);
    DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * cosine * (0.96 / PI);
    SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * cosine * (highlight / PI);
}
