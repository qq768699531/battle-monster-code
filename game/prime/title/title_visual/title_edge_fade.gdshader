shader_type canvas_item;
// 标题背景对象（Loop）的图层后处理：不再叠黑做边缘渐变，而是把已经画好的图层
// 取回来，直接调整它们的对比度（黑电平压到纯黑、亮部拉开）。近黑的图像边界因此变成
// 纯黑并与背景融合，图层内容本身保留。
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float contrast = 1.6;

void fragment() {
	vec3 source = texture(screen_texture, SCREEN_UV).rgb;
	vec3 adjusted = clamp((source - 0.5) * contrast + 0.5, 0.0, 1.0);
	COLOR = vec4(adjusted, 1.0);
}
