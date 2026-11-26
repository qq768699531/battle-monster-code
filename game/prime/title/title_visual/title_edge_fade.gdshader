shader_type canvas_item;
// 标题背景对象（Loop）的黑色渐变：形状是「平边在顶部、圆弧朝下」的半圆。
// 以 Loop 矩形顶边中点为圆心，半径以内的画面保持原样，半径以外压黑；
// 不改变图像的位置与大小，Copyright 层在 EdgeFade 之上（Layer019 z=1），不会被压黑。
uniform float radius : hint_range(0.1, 2.0) = 0.72;
uniform float feather : hint_range(0.0, 0.5) = 0.12;
// 矩形宽/高（Loop 的绘制矩形 304×325）。
uniform float aspect = 0.935;

void fragment() {
	vec2 q = vec2((UV.x - 0.5) * aspect, UV.y);
	float d = length(q);
	float alpha = smoothstep(radius - feather, radius, d);
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
