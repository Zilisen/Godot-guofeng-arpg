shader_type canvas_item;
// 受击闪白：用一个 uniform 在 0-1 之间插值到指定颜色，配合 Tween 做“白一下再回色”。
// 为什么不用 modulate：modulate 会连透明度和整体色一起动，而且无法只提亮高光区；
// 独立材质还能以后接 rim light / 描边。

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 col = texture(TEXTURE, UV) * COLOR;
	col.rgb = mix(col.rgb, flash_color.rgb, flash_amount);
	COLOR = col;
}
