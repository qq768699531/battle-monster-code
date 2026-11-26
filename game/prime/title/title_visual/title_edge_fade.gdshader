shader_type canvas_item;
// 标题背景对象（Loop）的黑色渐变：形状改成椭圆渐晕。
// 椭圆中心放在背景图中心偏下（屏幕中心），纵向半径略大，让中间一列从上到下、
// 尤其是底部中央尽量保持原图；四角与两侧沿椭圆边界压黑。
// 不改变图像的位置与大小；Copyright 层在 EdgeFade 之上（Layer019 z=1），不受影响。
uniform float center_x = 0.5;
uniform float center_y = 0.64;
uniform float radius_x = 0.56;
uniform float radius_y = 0.52;
uniform float feather = 0.14;

void fragment() {
	vec2 q = vec2((UV.x - center_x) / radius_x, (UV.y - center_y) / radius_y);
	float d = length(q);
	float alpha = smoothstep(1.0 - feather, 1.0, d);
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
