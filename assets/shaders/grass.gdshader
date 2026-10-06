shader_type spatial;
render_mode cull_disabled;
// Grass blades (MultiMesh): wind sway grows with blade height (UV.y), gusts
// travel across the field; instance colour tints each blade.
uniform vec3 root_tint : source_color = vec3(0.12, 0.2, 0.08);
uniform float wind_strength = 0.16;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = UV.y * UV.y;
	float gust = sin(TIME * 1.6 + wp.x * 0.21 + wp.z * 0.17) + 0.5 * sin(TIME * 3.1 + wp.x * 0.7);
	VERTEX.x += gust * wind_strength * h;
	VERTEX.z += gust * wind_strength * 0.5 * h;
}

void fragment() {
	ALBEDO = mix(root_tint, COLOR.rgb, UV.y);
	ROUGHNESS = 0.9;
}
