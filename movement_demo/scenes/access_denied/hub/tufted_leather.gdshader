shader_type spatial;

uniform vec4 leather : source_color = vec4(0.16, 0.23, 0.24, 1.0);

void fragment() {
	vec2 pattern = vec2(UV.x * 2.8 + UV.y * 2.0, UV.x * 2.8 - UV.y * 2.0);
	vec2 seam = abs(fract(pattern) - 0.5) * 2.0;
	float puff = 1.0 - smoothstep(0.0, 1.0, max(seam.x, seam.y));
	float button = smoothstep(0.79, 1.0, min(seam.x, seam.y));

	ALBEDO = leather.rgb * mix(0.48, 1.22, puff) * (1.0 - 0.48 * button);
	ROUGHNESS = mix(0.82, 0.49, puff);
	NORMAL_MAP = normalize(vec3(sin(pattern.x * TAU) + sin(pattern.y * TAU),
		sin(pattern.x * TAU) - sin(pattern.y * TAU), 4.0)) * 0.5 + 0.5;
}
