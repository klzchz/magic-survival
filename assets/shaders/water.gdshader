shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
// Lake water: two scrolling noise layers for ripples, fresnel toward the
// sky colour, slight glow at night so lakes stay readable in the dark.
uniform vec4 deep_color : source_color = vec4(0.04, 0.14, 0.2, 0.92);
uniform vec4 shallow_color : source_color = vec4(0.22, 0.42, 0.45, 0.78);
uniform vec4 sky_color : source_color = vec4(0.55, 0.62, 0.78, 1.0);
uniform sampler2D ripples : repeat_enable, filter_linear_mipmap;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 a = world_pos.xz * 0.06 + TIME * vec2(0.020, 0.012);
	vec2 b = world_pos.xz * 0.11 - TIME * vec2(0.014, 0.021);
	float n = texture(ripples, a).r * 0.55 + texture(ripples, b).r * 0.45;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, smoothstep(0.35, 0.75, n));
	col = mix(col, sky_color.rgb, fres * 0.55);
	col += vec3(smoothstep(0.72, 0.8, n)) * 0.18;  // sparkle on ripple crests
	ALBEDO = col;
	ALPHA = mix(deep_color.a, 0.97, fres);
	ROUGHNESS = 0.06;
	SPECULAR = 0.8;
	EMISSION = vec3(0.01, 0.03, 0.05) * n;
}
