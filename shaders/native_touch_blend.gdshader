shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform int native_mode = 23;
uniform int native_alpha = 16;
uniform int native_brightness = 0;
uniform vec3 native_gray_channels = vec3(1.0);
uniform bool grayscale = false;

void fragment() {
	// CanvasItem fragment COLOR already includes the texture sample.
	vec4 source = COLOR;
	if (grayscale) {
		vec3 bits = floor(source.rgb * 255.0 / vec3(8.0, 4.0, 8.0));
		float value = bits.r * 128.0 + bits.g * 160.0 + bits.b * 64.0;
		source.rgb = vec3(floor(value / 512.0) / 31.0,
			floor(value / 256.0) / 63.0, floor(value / 512.0) / 31.0);
	}
	vec3 destination = texture(screen_texture, SCREEN_UV).rgb;
	vec3 limits = vec3(31.0, 63.0, 31.0);
	vec3 source_bits = round(source.rgb * limits);
	vec3 result = max(destination, source_bits / limits);
	if (native_mode == 0) {
		result = source.rgb;
	} else if (native_mode == 8) {
		result = (source_bits + floor((limits - source_bits) * float(native_brightness) / 256.0)) / limits;
	} else if (native_mode == 14) {
		vec3 destination_bits = round(destination * limits);
		result = floor(destination_bits + (source_bits - destination_bits) * float(native_alpha) / 16.0) / limits;
	} else if (native_mode == 20) {
		vec3 destination_bits = round(destination * limits);
		vec3 multiplied = floor(destination_bits * source_bits / vec3(32.0, 64.0, 32.0));
		result = multiplied / limits;
	} else if (native_mode == 21) {
		vec3 destination_bits = round(destination * limits);
		vec3 screen_bits = limits - floor(
			(limits - destination_bits) * (limits - source_bits) / vec3(32.0, 64.0, 32.0)
		);
		result = max(destination, screen_bits / limits);
	} else if (native_mode == 22) {
		vec3 destination_bits = round(destination * limits);
		result = min(destination_bits + source_bits, limits) / limits;
	} else if (native_mode == 18) {
		// Object_drawBUFFER0 case GRP_MODE_GRAYCOLOR -> EFC_pixel_GRAYCOLOR_Proc:
		// 亮度 = R*128 + G*160 + B*64（5/6/5 位），红/蓝取 value>>9、绿取 value>>8，
		// 再按 JC_grpSetMODE 的 PixelData.mode_parameter_bits 逐通道取掩码。
		float value = source_bits.r * 128.0 + source_bits.g * 160.0 + source_bits.b * 64.0;
		vec3 gray_bits = vec3(floor(value / 512.0), floor(value / 256.0), floor(value / 512.0));
		result = gray_bits * native_gray_channels / limits;
	}
	COLOR = vec4(mix(destination, result, source.a), 1.0);
}
