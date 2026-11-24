shader_type canvas_item;
render_mode unshaded, blend_disabled;

// 原生 `Map_eftDRAW`：用调用前的绘制组模式 + `PixelData.draw_color_rgb565_bits`
// 整屏填充，所以这里读屏幕再按模式合成。模式下标是 `GRP_MODE_TYPE`（`JC_grpSetMODE`），
// 只实现本族用到的三档。
const int GRP_MODE_NORMAL = 0;
const int GRP_MODE_MULTIPLY = 20;
const int GRP_MODE_LINEAR_DODGE = 22;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
// 默认 0 = GRP_MODE_NORMAL：uniform 的默认值不接受具名常量，只写数字并在此注明。
uniform int mode = 0;
uniform vec4 tint = vec4(1.0);

void fragment() {
	vec3 drawn = texture(screen_texture, SCREEN_UV).rgb;
	if (mode == GRP_MODE_MULTIPLY) {
		COLOR = vec4(floor(drawn * tint.rgb * 255.0) / 255.0, 1.0);
	} else if (mode == GRP_MODE_LINEAR_DODGE) {
		COLOR = vec4(min(drawn + tint.rgb, vec3(1.0)), 1.0);
	} else {
		COLOR = vec4(tint.rgb, 1.0);
	}
}
