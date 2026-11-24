shader_type canvas_item;
render_mode unshaded;

// 标题菜单选中项的闪光：原版录屏（Downloads/untitled.gif 第 29–33 帧）显示的是
// 一块白色从按钮左边缘铺开、右边界是斜线，几帧内扫满整条按钮后消失。
// 相位沿用原版 `*p_n2` 的 0..3 帧：白块右边界按相位推进，第 4 帧起关闭。

uniform float progress = -1.0;      // <0 关闭；0..1 白色推进到的位置
uniform float edge_slant = 0.16;    // 斜边倾斜量（UV.x 比例）
uniform vec3 shine_color : source_color = vec3(1.0, 1.0, 1.0);

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float cover = 0.0;
	if (progress >= 0.0) {
		// 斜边：同一列上，y 越靠下边界越靠左，形成 "/" 斜线。
		float slant = (UV.y - 0.5) * edge_slant;
		float boundary = progress * (1.0 + edge_slant) - edge_slant * 0.5 + slant;
		cover = step(UV.x, boundary);
	}
	vec3 lit = mix(base.rgb, shine_color, cover);
	COLOR = vec4(lit, base.a);
}
