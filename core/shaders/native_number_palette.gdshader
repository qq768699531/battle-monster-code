shader_type canvas_item;

void fragment() {
	if (all(lessThan(COLOR.rgb, vec3(0.001)))) {
		COLOR.a = 0.0;
	}
}
