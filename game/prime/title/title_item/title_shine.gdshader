shader_type canvas_item;
render_mode unshaded;

// 标题菜单选中项的闪光。四帧全部按原生 `Prime_Title_DrawItem` 的绘制调用还原，坐标是
// 底条局部像素（底条画在 `x-40`，所以局部 x = 调用参数 x − (x−40)）：
//
//   n2=0: DrawCLIP (x-39, y+1, 20, 21, 源 8,0)          → (1,1)  20×21，源 (8,0)
//   n2=1: FillRoundRECT(style 1, x-39, y+1, 25, 21)      → (1,1)  25×21 白块
//         DrawSPRITE(x-15, y+1, 帧 2, mirror 0)          → (25,1) 28×21
//   n2=2: FillRoundRECT(style 1, x+14, y+1, 25, 21)      → (54,1) 25×21 白块
//         DrawSPRITE(x+15, y+22, 帧 2, mirror 3)         → (27,1) 28×21 镜像
//   n2=3: DrawCLIP (x+19, y+1, 20, 21, 源 8,0, mirror 3) → (59,1) 20×21，源 (8,0) 镜像
//
// 关键在 n2=2：`JC_fbmDrawSPRITE` 不是把 (x, y) 当左上角。它先 `JC_imgGetMIRROR` 得到
// mirror=3，`JC_fbmMIRROR` 把帧锚点翻成 (W−xOffset, H−yOffset)，再由
// `JC_fbmDrawBASIC(a1 − 锚点X, a2 − 锚点Y, …)` 落笔。ui_title2 第 2 帧是 28×21、锚点
// (0,0)，于是 (x+15, y+22) 翻成锚点 (28,21)、实际画在 (x−13, y+1) —— 底条局部 x=27，
// 不是 55。旧实现漏了这步，第 3 帧的斜带才会跑到右端、和右半白块叠在一起看不见。
//
// 白块是 `JC_grpFillRoundRECT` 的 style 1：顶行/底行各左右缩 1px，中段满宽，不是圆角。
// 原生先画白块再以 `GRP_MODE_SCREEN` 叠贴片（`JC_grpReset()` 只把模式还原成
// `GRP_MODE_NORMAL`，所以白块是不透明的 COPY）。SCREEN 用的是贴片的**颜色**而不是
// alpha：ui_title2 第 2 帧的 alpha 只有 0/255 两种（硬斜切），柔边全在亮度里
// （255 → 43 → 0 的窄渐变），透出的部分靠「颜色接近黑 → 提亮接近于 0」淡出。
// 用 alpha 当遮罩会得到硬边白块，必须按亮度 `dot(rgb, luma)` 取权重。
// 这一层要画在文字之上（原生先 `JC_fntDrawChars` 再画白块/贴片，白块会盖住字）。

uniform sampler2D gleam_tex : filter_linear, repeat_disable;
uniform int phase = -1;
uniform vec2 bar_px = vec2(80.0, 23.0);
uniform vec2 gleam_px = vec2(28.0, 21.0);


// JC_grpFillRoundRECT 的 style 1：顶/底行各缩 1px，中段满宽。
float style1_mask(vec2 p, vec2 origin, vec2 size) {
	if (p.x < origin.x || p.y < origin.y || p.x >= origin.x + size.x || p.y >= origin.y + size.y) {
		return 0.0;
	}
	float inset = (p.y < origin.y + 1.0 || p.y >= origin.y + size.y - 1.0) ? 1.0 : 0.0;
	if (p.x < origin.x + inset || p.x >= origin.x + size.x - inset) {
		return 0.0;
	}
	return 1.0;
}


void fragment() {
	vec2 px = UV * bar_px;
	float cover = 0.0;

	// 白块：n2=1 在左（x-39），n2=2 在右（x+14）。
	if (phase == 1) {
		cover = style1_mask(px, vec2(1.0, 1.0), vec2(25.0, 21.0));
	} else if (phase == 2) {
		cover = style1_mask(px, vec2(54.0, 1.0), vec2(25.0, 21.0));
	}

	// 斜向贴片。
	vec2 dest = vec2(0.0);
	vec2 size_px = vec2(0.0);
	vec2 source = vec2(0.0);
	bool mirrored = false;
	if (phase == 0) {
		dest = vec2(1.0, 1.0);
		size_px = vec2(20.0, 21.0);
		source = vec2(8.0, 0.0);
	} else if (phase == 1) {
		dest = vec2(25.0, 1.0);
		size_px = vec2(28.0, 21.0);
	} else if (phase == 2) {
		dest = vec2(27.0, 1.0);
		size_px = vec2(28.0, 21.0);
		mirrored = true;
	} else if (phase == 3) {
		dest = vec2(59.0, 1.0);
		size_px = vec2(20.0, 21.0);
		source = vec2(8.0, 0.0);
		mirrored = true;
	}

	if (phase >= 0 && phase <= 3) {
		vec2 local = px - dest;
		if (local.x >= 0.0 && local.y >= 0.0 && local.x < size_px.x && local.y < size_px.y) {
			vec2 uv_px = local + source;
			if (mirrored) {
				uv_px = source + size_px - vec2(1.0) - local;
			}
			vec4 texel = texture(gleam_tex, uv_px / gleam_px);
			// 亮度即 SCREEN 的提亮量；alpha 只表示像素是否参与（透明处是色键洋红）。
			float lift = dot(texel.rgb, vec3(0.299, 0.587, 0.114)) * step(0.5, texel.a);
			cover = max(cover, lift);
		}
	}

	COLOR = vec4(1.0, 1.0, 1.0, cover);
}
