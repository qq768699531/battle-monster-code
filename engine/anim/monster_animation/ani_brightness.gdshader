shader_type canvas_item;

// 灰阶（原生 `GRP_MODE_GRAY`）的逐像素公式，取自 `EFC_pixel_GRAY_Proc`。
// `JC_grpSetMODE` 的 default 分支把 17（`GRP_MODE_TYPE.GRP_MODE_GRAY`）直接写进
// `PixelData.pixel_operation_index`，`JC_pxlInitialize` 再把 `PixelProc[17]` 填成该函数；
// `EFC_pixel_GRAY_Proc:6-9` 等价于：
//   灰阶码 g5 = (R5*128 + G6*160 + B5*64) >> 9
//   输出 565 = RGB565(R5 = g5, G6 = 同一和值 >>8, B5 = g5)
// 其中 160 = `src & 0x7E0` 的 32 基项 + `(src << 21) >> 26 << 7` 的 128 补项（G6 权重）。
// 原生源像素本来就在 565 帧缓冲里，8 位贴图进来时按 `EX_grpGetPixelFromRGB` 的 >>3／>>2 截断量化。

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform bool grayscale = false;

// 8 位通道满量（`EX_grpGetPixelFromRGB` 的输入口径）。
const float CHANNEL_MAX = 255.0;
// 5/6 位码值的除数：red8>>3、blue8>>3 得 5 位，green8>>2 得 6 位。
const float RED_BLUE_CODE_DIVISOR = 8.0;
const float GREEN_CODE_DIVISOR = 4.0;
// `EFC_pixel_GRAY_Proc:6-7` 的三个权重（和 512，正好把 5 位满量折回 0..31）。
const float GRAY_RED_WEIGHT = 128.0;
const float GRAY_GREEN_WEIGHT = 160.0;
const float GRAY_BLUE_WEIGHT = 64.0;
// 权重和的位移口径：>>9 给 5 位灰阶码，>>8 给 6 位绿通道码。
const float GRAY_RED_BLUE_DIVISOR = 512.0;
const float GRAY_GREEN_DIVISOR = 256.0;
// 565 各通道满量，用于把码值还原成 0..1。
const float RED_BLUE_LEVELS = 31.0;
const float GREEN_LEVELS = 63.0;

void fragment() {
	vec4 source = COLOR;
	vec3 rgb = mix(source.rgb, vec3(1.0), strength);
	if (grayscale) {
		float red5 = floor(source.r * CHANNEL_MAX / RED_BLUE_CODE_DIVISOR);
		float green6 = floor(source.g * CHANNEL_MAX / GREEN_CODE_DIVISOR);
		float blue5 = floor(source.b * CHANNEL_MAX / RED_BLUE_CODE_DIVISOR);
		float luminance = red5 * GRAY_RED_WEIGHT + green6 * GRAY_GREEN_WEIGHT + blue5 * GRAY_BLUE_WEIGHT;
		rgb = vec3(floor(luminance / GRAY_RED_BLUE_DIVISOR) / RED_BLUE_LEVELS,
			floor(luminance / GRAY_GREEN_DIVISOR) / GREEN_LEVELS,
			floor(luminance / GRAY_RED_BLUE_DIVISOR) / RED_BLUE_LEVELS);
	}
	COLOR = vec4(rgb, source.a);
}
