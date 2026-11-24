shader_type canvas_item;
// 程序化标题闪光：横向光带按时间滚动，再与屏幕做原生的量化混合。
// 贴图不再是形状来源，节点用 ColorRect 即可。

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float band_count = 2.0;
uniform float band_speed = 1.6;
uniform float band_softness = 0.35;

void fragment() {
	float wave = sin((UV.y * band_count - TIME * band_speed) * 6.2831853);
	float band = smoothstep(1.0 - band_softness, 1.0, wave);
	float edge = 1.0 - smoothstep(0.0, 1.0, abs(UV.x - 0.5) * 2.0);
	vec4 source = vec4(1.0, 1.0, 1.0, band * edge * COLOR.a);

	vec3 levels = vec3(31.0, 63.0, 31.0);
	vec3 divisor = vec3(32.0, 64.0, 32.0);
	vec3 source_bits = min(floor(source.rgb * 255.0 / vec3(8.0, 4.0, 8.0)), levels);
	vec3 destination = texture(screen_texture, SCREEN_UV).rgb;
	vec3 destination_bits = min(floor(destination * 255.0 / vec3(8.0, 4.0, 8.0)), levels);
	vec3 result = levels - floor((levels - source_bits) * (levels - destination_bits) / divisor);
	COLOR = vec4(result / levels, source.a);
}
