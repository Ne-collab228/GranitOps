shader_type spatial;
// Рельеф: смешивание трёх слоёв по цвету вершин (r — сухая земля, g — скала, b — дорога/двор).

uniform sampler2D tex_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_r : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nor_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nor_r : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tile = 0.3;
uniform float use_normal = 1.0;
uniform float use_far = 1.0;
uniform vec3 tint = vec3(0.92, 0.9, 0.84);
uniform float rock_dark = 0.62;

varying vec3 wpos;
varying float slope;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	slope = 1.0 - clamp(NORMAL.y, 0.0, 1.0);
	UV = wpos.xz * tile;
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

void fragment() {
	float m = texture(macro, wpos.xz * 0.011).r;
	vec3 a = texture(tex_a, UV).rgb;
	vec3 b = texture(tex_b, UV * 0.8).rgb;
	vec3 r = texture(tex_r, UV * 0.55).rgb;
	float wb = clamp(COLOR.r + (m - 0.5) * 0.7, 0.0, 1.0);
	float wr = clamp(COLOR.g * 1.3, 0.0, 1.0);
	vec3 alb = mix(a, b, wb);
	if (use_far > 0.5) {
		float dist = length(wpos - CAMERA_POSITION_WORLD);
		vec3 far = texture(tex_a, UV * 0.13).rgb;
		alb = mix(alb, mix(far, alb, 0.35), smoothstep(25.0, 110.0, dist));
	}
	alb = mix(alb, r * rock_dark, wr);
	alb = mix(vec3(dot(alb, vec3(0.3, 0.59, 0.11))), alb, 0.72) * tint;
	alb *= mix(vec3(1.0), vec3(0.7, 0.66, 0.61), COLOR.b);
	alb *= 0.78 + 0.44 * m;
	// крупные пятна: следы техники, сырая/выжженная земля — убирает «однотонный песок»
	float m2 = texture(macro, wpos.xz * 0.0037 + vec2(0.37, 0.11)).r;
	alb *= mix(vec3(0.8, 0.78, 0.76), vec3(1.04, 1.02, 0.99), smoothstep(0.25, 0.75, m2));
	// мелкая рябь яркости вблизи, чтобы земля не выглядела плоской
	alb *= 0.93 + 0.14 * texture(macro, wpos.xz * 0.19).r;
	// зерно/камешки под ногами (только вблизи) и тёмные осыпи на склонах
	float near = 1.0 - smoothstep(12.0, 40.0, length(wpos - CAMERA_POSITION_WORLD));
	alb *= mix(1.0, 0.86 + 0.28 * texture(macro, wpos.xz * 1.7).r, near);
	alb *= mix(1.0, 0.8, smoothstep(0.12, 0.45, slope));
	ALBEDO = alb;
	ROUGHNESS = mix(0.96, 0.86, wr);
	SPECULAR = 0.2;
	if (use_normal > 0.5) {
		vec3 na = texture(nor_a, UV).rgb;
		vec3 nr = texture(nor_r, UV * 0.55).rgb;
		NORMAL_MAP = mix(na, nr, wr);
	}
}
