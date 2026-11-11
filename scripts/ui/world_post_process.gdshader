shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D world_screen : hint_screen_texture, repeat_disable, filter_nearest;
uniform float grayscale_amount = 0.0;
uniform float vignette_power = 0.0;
void fragment() {
	vec4 pixel = texture(world_screen, SCREEN_UV);
	float brightness = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
	float edge = length(SCREEN_UV - vec2(0.5)) * vignette_power;
	pixel.rgb = mix(pixel.rgb, vec3(brightness), grayscale_amount) * (1.0 - smoothstep(0.2, 0.8, edge));
	COLOR = pixel;
}
