shader_type canvas_item;
render_mode unshaded, blend_disabled;

// 原生 Evt_eftSET：GRP_MODE_GRAY（1）把之后绘制的画面转灰度，
// GRP_MODE_DARK（2）按 0x909090 压暗。取整屏幕后重画，等价于原生绘制时就锁定的滤镜。
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform int mode = 1;
uniform vec3 dark_color = vec3(0.5647059, 0.5647059, 0.5647059);

void fragment() {
	vec3 color = texture(screen_texture, SCREEN_UV).rgb;
	if (mode == 1) {
		float gray = floor(dot(color, vec3(0.299, 0.587, 0.114)) * 255.0) / 255.0;
		COLOR = vec4(vec3(gray), 1.0);
	} else if (mode == 2) {
		COLOR = vec4(floor(color * dark_color * 255.0) / 255.0, 1.0);
	} else {
		COLOR = vec4(color, 1.0);
	}
}
