shader_type canvas_item;
render_mode unshaded;

uniform vec2 hero_uv = vec2(0.5);
uniform float zoom = 0.0;

// 原生 `Field_Basic_Capture` 在接触怪物时先抓一帧地图+对象，然后：
//   `JC_grpSetMODE(GRP_MODE_ALPHA, 128)` + `JC_grpSetRGB(0)` + `JC_grpFillSCREEN()` → 压黑 50%
//   `JC_grpFillBLUR` → 3×3 高斯，核 {{1,2,1},{2,4,2},{1,2,1}} / 16
// 转场动画（缩放／黑白闪／渐黑）都画在这张已经淡出的图上，所以这里对采样结果做同一套处理。
void fragment() {
	vec2 uv = mix(UV, hero_uv, zoom);
	vec2 unit = TEXTURE_PIXEL_SIZE;
	vec3 sum = texture(TEXTURE, uv).rgb * 4.0;
	sum += texture(TEXTURE, uv + vec2(unit.x, 0.0)).rgb * 2.0;
	sum += texture(TEXTURE, uv - vec2(unit.x, 0.0)).rgb * 2.0;
	sum += texture(TEXTURE, uv + vec2(0.0, unit.y)).rgb * 2.0;
	sum += texture(TEXTURE, uv - vec2(0.0, unit.y)).rgb * 2.0;
	sum += texture(TEXTURE, uv + unit).rgb;
	sum += texture(TEXTURE, uv - unit).rgb;
	sum += texture(TEXTURE, uv + vec2(unit.x, -unit.y)).rgb;
	sum += texture(TEXTURE, uv + vec2(-unit.x, unit.y)).rgb;
	COLOR = vec4(sum / 16.0 * 0.5, 1.0);
}
