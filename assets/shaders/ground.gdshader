shader_type spatial;
// Terrain: per-vertex biome colours (grass / dry patches / mud shore / rock)
// plus a world-space noise detail so close-up ground never looks flat.
uniform sampler2D detail : repeat_enable, filter_linear_mipmap;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fine = texture(detail, world_pos.xz * 0.11).r;
	float broad = texture(detail, world_pos.xz * 0.017).r;
	ALBEDO = COLOR.rgb * (0.78 + 0.32 * fine) * (0.9 + 0.2 * broad);
	ROUGHNESS = 1.0;
}
