shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
// 定格快照：以快照为背景的窗层（世界地图 `Menu_world_Draw`、野外 HUD 的 MAP 键）在开窗前把
// 那一帧抓成纹理（原生 `Field_Basic_Capture` 写 `MapRes.map_scratch_image`，之后各窗口层
// `Map_Copy()` 复用同一张）。`frozen` 为真时只采样它，实时屏幕不参与：模糊与半透明都落在
// 同一张快照上，所以背景完全静止。
uniform sampler2D snapshot : repeat_disable, filter_nearest;
uniform bool frozen = false;
// 原生 FillBLUR 在 400×240 缓存上取整像素；显示放大到 800×480 时步长仍是逻辑像素，
// 不能跟着 SCREEN_PIXEL_SIZE 变成半个逻辑像素。
uniform vec2 pixel_step = vec2(0.0025, 0.0041666667);

const vec3 RGB565_LEVELS = vec3(31.0, 63.0, 31.0);

void fragment() {
	vec3 weighted_sum = vec3(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 sample_uv = SCREEN_UV + vec2(float(x), float(y)) * pixel_step;
			if (any(lessThan(sample_uv, vec2(0.0))) || any(greaterThan(sample_uv, vec2(1.0)))) {
				continue;
			}
			float weight = (x == 0 ? 2.0 : 1.0) * (y == 0 ? 2.0 : 1.0);
			vec3 background = frozen
					? texture(snapshot, sample_uv).rgb
					: texture(screen_texture, sample_uv).rgb;
			vec3 sample_bits = floor(background * RGB565_LEVELS);
			weighted_sum += floor(sample_bits * (1.0 - COLOR.a)) * weight;
		}
	}
	COLOR = vec4(floor(weighted_sum / 16.0) / RGB565_LEVELS, 1.0);
}
