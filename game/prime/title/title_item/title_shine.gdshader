shader_type canvas_item;
render_mode unshaded;

// 标题菜单选中项的闪光：几何照搬原版 `Prime_Title_DrawItem` 的 4 帧。
// 底条 Sprite2D 本身只有 80×23 的 alpha，闪光加色叠上去，天然不会溢出按钮。
//   0: 斜光裁切 (x-39, y+1, 20, 21)，源偏移 (8, 0)
//   1: 白圆角块 (x-39, y+1, 25, 21) + 斜光 (x-15, y+1)
//   2: 白圆角块 (x+14, y+1, 25, 21) + 斜光 (x+15, y+22) 翻转
//   3: 斜光裁切 (x+19, y+1, 20, 21)

uniform sampler2D gleam_tex : filter_linear, repeat_disable;
uniform int phase = -1;              // -1 关闭；0..3 对应原版 4 帧
uniform vec2 bar_px = vec2(80.0, 23.0);
uniform vec2 gleam_px = vec2(28.0, 21.0);
uniform float gleam_gain = 1.0;

float rounded_box(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + vec2(radius);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float lit = 0.0;
	if (phase >= 0 && phase <= 3) {
		vec2 px = UV * bar_px;

		// 第 1／2 帧：白圆角块贴在按钮两端。
		if (phase == 1 || phase == 2) {
			vec2 center = (phase == 1) ? vec2(13.5, 11.5) : vec2(66.5, 11.5);
			vec2 half_size = vec2(12.5, 10.5);
			float d = rounded_box(px - center, half_size, 3.0);
			lit = max(lit, 1.0 - smoothstep(-1.0, 0.5, d));
		}

		// 斜光：第 0／3 帧裁成 20×21 的小条。
		vec2 origin;
		bool flip_x = false;
		if (phase == 0) {
			origin = vec2(-7.0, 1.0);
		} else if (phase == 1) {
			origin = vec2(25.0, 1.0);
		} else if (phase == 2) {
			origin = vec2(55.0, 1.0);
			flip_x = true;
		} else {
			origin = vec2(59.0, 1.0);
			flip_x = true;
		}
		vec2 local = px - origin;
		bool inside = local.x >= 0.0 && local.x <= gleam_px.x && local.y >= 0.0 && local.y <= gleam_px.y;
		if (phase == 0) {
			inside = inside && local.x >= 1.0 && local.x <= 21.0;
		} else if (phase == 3) {
			inside = inside && px.x >= 59.0 && px.x <= 79.0;
		}
		if (inside) {
			vec2 guv = local / gleam_px;
			if (flip_x) {
				guv.x = 1.0 - guv.x;
			}
			lit = max(lit, texture(gleam_tex, guv).a * gleam_gain);
		}
	}
	COLOR = vec4(base.rgb + vec3(lit), base.a);
}
