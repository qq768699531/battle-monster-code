shader_type canvas_item;

uniform int brightness : hint_range(0, 63) = 0;
uniform bool focused = true;

void fragment() {
	if (focused) {
		vec3 levels = vec3(31.0, 63.0, 31.0);
		vec3 bits = round(COLOR.rgb * levels);
		COLOR.rgb = (bits + floor((levels - bits) * float(brightness) / 256.0)) / levels;
	}
}
