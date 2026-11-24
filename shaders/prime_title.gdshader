shader_type canvas_item;

varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV) * COLOR;
	bool upper = local_position.y < -2.0;
	vec3 outline = upper ? vec3(16.0, 39.0, 90.0) : vec3(16.0, 0.0, 71.0);
	vec3 fill = upper ? vec3(32.0, 79.0, 181.0) : vec3(32.0, 0.0, 143.0);
	vec3 color = mix(outline, fill, COLOR.r / max(COLOR.a, 0.001)) / 255.0;
	float visible = abs(local_position.x) < 100.0 && abs(local_position.y) < 10.0 ? 1.0 : 0.0;
	COLOR = vec4(color, source.a * visible);
}
