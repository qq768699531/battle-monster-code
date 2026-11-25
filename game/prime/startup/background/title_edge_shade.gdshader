shader_type canvas_item;

// 主菜单（存档选择）背景的压黑边：左右与下缘向黑色渐隐，遮掉抓取图/标题图的矩形边界。
uniform float fade_left : hint_range(0.0, 200.0) = 32.0;
uniform float fade_right : hint_range(0.0, 200.0) = 32.0;
uniform float fade_bottom : hint_range(0.0, 200.0) = 32.0;
uniform vec2 logical_size = vec2(400.0, 240.0);

void fragment() {
	vec2 pixel = UV * logical_size;
	float left = 1.0 - smoothstep(0.0, fade_left, pixel.x);
	float right = 1.0 - smoothstep(0.0, fade_right, logical_size.x - pixel.x);
	float bottom = 1.0 - smoothstep(0.0, fade_bottom, logical_size.y - pixel.y);
	float alpha = max(left, max(right, bottom));
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
