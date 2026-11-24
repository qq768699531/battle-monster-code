shader_type canvas_item;

// 通用物品格（30×30）格底的亮度与品级描边。
//
// 亮度：原生 `GRP_MODE_BRIGHT` 的 `8 * frames % 128`（超过 63 折回 `127 - v`），由 `Frame/Breath`
//   把 `brightness` 推到 0→63→0。这一段与 `native_menu_brightness.gdshader` 同式，但**故意不共用**
//   那一份——它还挂在 `menu.tscn` 的 6 个页签与 `item_category` 上，物品格要随自己那圈描边单独演进。
// 品级描边：原生 `Menu_Item_DrawItem@0x55238` 在格底上用 `Menu_Item_GetRGB` 的品级色画
//   `JC_grpDrawRoundRECT(1, x, y, 30, 30)`。style 1 分支（`JC_grpDrawRoundRECT@0x23810:64-81`）是四条
//   `长-2` 的边（四角不画）＋四角各一个内收 1px 的 1×1 补点，合计 `2*(w-2) + 2*(h-2) + 4` 像素；
//   `StyleBoxFlat` 的 `corner_radius = 1` 在 1px 边框上实测不切角（四角照旧填满），所以这一圈按像素画。

uniform int brightness : hint_range(0, 63) = 0;
uniform bool focused = true;
uniform vec4 grade_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool grade_enabled = false;
// 格底尺寸（像素）。`item_cell.gd` 在就绪与尺寸变化时写入，描边按它判断「最外 1px」。
uniform vec2 slot_size = vec2(30.0, 30.0);

const vec3 LEVELS = vec3(31.0, 63.0, 31.0);

varying vec2 local_pixel;

void vertex() {
	local_pixel = VERTEX;
}

void fragment() {
	if (focused) {
		vec3 bits = round(COLOR.rgb * LEVELS);
		COLOR.rgb = (bits + floor((LEVELS - bits) * float(brightness) / 256.0)) / LEVELS;
	}
	if (grade_enabled) {
		vec2 pixel = floor(local_pixel);
		vec2 corner = slot_size - 2.0;
		bool on_column = pixel.x < 0.5 || pixel.x > slot_size.x - 1.5;
		bool on_row = pixel.y < 0.5 || pixel.y > slot_size.y - 1.5;
		// 原生 style 1 的四条边各只有 `size - 2` 像素（四个角不画），
		// 再在四角各补一个内收 1px 的点——角上不是挖空，而是转进一格。
		bool on_inner_column = abs(pixel.x - 1.0) < 0.5 || abs(pixel.x - corner.x) < 0.5;
		bool on_inner_row = abs(pixel.y - 1.0) < 0.5 || abs(pixel.y - corner.y) < 0.5;
		bool on_ring = (on_column || on_row) && !(on_column && on_row);
		if (on_ring || (on_inner_column && on_inner_row)) {
			COLOR = grade_color;
		}
	}
}
