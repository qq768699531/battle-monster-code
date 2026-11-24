shader_type canvas_item;
render_mode unshaded;

// 标题菜单选中项的闪光。`common/ui_title2.fbm` 第 2 帧（28×21）本身就是一张斜向渐变贴片
// （左下 → 右上的斜带，边缘柔和），原版四帧把它按不同位置/裁切画在按钮上：
//
//   n2=0: CLIP(x-39, v8+1, 20, 21, 8, 0)   → 目标 (1,1) 20×21，源 (8,0)
//   n2=1: SPRITE(x-15, v8+1)               → 目标 (25,1) 28×21
//   n2=2: SPRITE(x+15, v8+22)              → 目标 (55,1) 28×21
//   n2=3: CLIP(x+19, v8+1, 20, 21, 8, 0)   → 目标 (59,1) 20×21，源 (8,0)
//
// 贴片是“同一方向的斜块”，四帧只改位置，不翻转、不旋转；取它的 alpha 当白色遮罩。

uniform sampler2D gleam_tex : filter_linear, repeat_disable;
uniform int phase = -1;
uniform vec2 bar_px = vec2(80.0, 23.0);
uniform vec2 gleam_px = vec2(28.0, 21.0);

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec3 lit = base.rgb;
	if (phase >= 0 && phase <= 3) {
		vec2 px = UV * bar_px;

		vec2 dest; vec2 size_px; vec2 source;
		if (phase == 0) {
			dest = vec2(1.0, 1.0);  size_px = vec2(20.0, 21.0); source = vec2(8.0, 0.0);
		} else if (phase == 1) {
			dest = vec2(25.0, 1.0); size_px = vec2(28.0, 21.0); source = vec2(0.0, 0.0);
		} else if (phase == 2) {
			dest = vec2(55.0, 1.0); size_px = vec2(28.0, 21.0); source = vec2(0.0, 0.0);
		} else {
			dest = vec2(59.0, 1.0); size_px = vec2(20.0, 21.0); source = vec2(8.0, 0.0);
		}
		vec2 local = px - dest;
		if (local.x >= 0.0 && local.y >= 0.0 && local.x < size_px.x && local.y < size_px.y) {
			float band = texture(gleam_tex, (local + source) / gleam_px).a;
			lit = mix(lit, vec3(1.0), band);
		}
	}
	COLOR = vec4(lit, base.a);
}
