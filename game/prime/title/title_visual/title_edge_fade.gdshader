shader_type canvas_item;
// 标题背景对象（Loop）自身的边缘渐变到黑：只收左、右、下三边（上边是超出屏幕的画面，没有边界）。
// 不改图像的位置与大小，只在 Loop 的绘制矩形内叠加“边缘黑、中心透明”的渐变。
uniform float edge_width_x : hint_range(0.0, 0.5) = 0.12;
uniform float edge_width_y : hint_range(0.0, 0.5) = 0.08;

void fragment() {
	float left = smoothstep(0.0, edge_width_x, UV.x);
	float right = smoothstep(0.0, edge_width_x, 1.0 - UV.x);
	float bottom = smoothstep(0.0, edge_width_y, 1.0 - UV.y);
	float alpha = 1.0 - min(min(left, right), bottom);
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
