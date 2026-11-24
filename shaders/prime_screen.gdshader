shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	vec4 source = COLOR;
	vec3 levels = vec3(31.0, 63.0, 31.0);
	vec3 divisor = vec3(32.0, 64.0, 32.0);
	vec3 source_bits = min(floor(source.rgb * 255.0 / vec3(8.0, 4.0, 8.0)), levels);
	vec3 destination = texture(screen_texture, SCREEN_UV).rgb;
	vec3 destination_bits = min(floor(destination * 255.0 / vec3(8.0, 4.0, 8.0)), levels);
	vec3 result = levels - floor((levels - source_bits) * (levels - destination_bits) / divisor);
	COLOR = vec4(result / levels, source.a);
}
