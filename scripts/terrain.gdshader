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
// трава: цвет, доля пятен на ровной земле, вес вершинной альфы (карты с готовой маской травы)
uniform vec3 grass_col = vec3(0.34, 0.38, 0.17);
uniform float grass_amt = 0.5;
uniform float grass_vert = 1.0;
// тёплые/холодные разводы земли и полосы слоёв на скале
uniform float strata = 0.0;

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
	vec3 cam = CAMERA_POSITION_WORLD;
	float dist = length(wpos - cam);
	float m = texture(macro, wpos.xz * 0.011).r;
	float m2 = texture(macro, wpos.xz * 0.0037 + vec2(0.37, 0.11)).r;
	float m3 = texture(macro, wpos.xz * 0.045 + vec2(0.61, 0.23)).r;
	vec3 a = texture(tex_a, UV).rgb;
	vec3 b = texture(tex_b, UV * 0.8).rgb;
	float wb = clamp(COLOR.r + (m - 0.5) * 0.7, 0.0, 1.0);
	float wr = clamp(COLOR.g * 1.3, 0.0, 1.0);
	vec3 alb = mix(a, b, wb);
	if (use_far > 0.5) {
		vec3 far = texture(tex_a, UV * 0.13).rgb;
		alb = mix(alb, mix(far, alb, 0.35), smoothstep(25.0, 110.0, dist));
	}
	// скала: на крутом склоне проекция сбоку (иначе текстура вытягивается), полосы слоёв по высоте
	vec3 r = texture(tex_r, UV * 0.55).rgb;
	if (slope > 0.22) {
		vec2 uvs = vec2(wpos.x + wpos.z * 0.8, wpos.y) * tile * 0.55;
		r = mix(r, texture(tex_r, uvs).rgb, smoothstep(0.22, 0.5, slope));
	}
	float band = sin(wpos.y * 0.9 + m * 7.0) * 0.5 + 0.5;
	r *= 1.0 - strata * (0.2 * band + 0.12 * smoothstep(0.55, 0.9, texture(macro, vec2(wpos.y * 0.021, (wpos.x + wpos.z) * 0.004)).r));
	alb = mix(alb, r * rock_dark, wr);
	alb = mix(vec3(dot(alb, vec3(0.3, 0.59, 0.11))), alb, 0.72) * tint;
	float lum = dot(a, vec3(0.3, 0.59, 0.11));
	// разводы тёплой и холодной земли
	alb *= mix(vec3(1.05, 1.0, 0.92), vec3(0.94, 0.99, 1.05), smoothstep(0.3, 0.7, m2));
	// травяные пятна: на ровной нетронутой земле, неровные края от среднего шума
	float road_w = COLOR.b;
	float gp = smoothstep(0.52, 0.68, m2 * 0.55 + m * 0.3 + m3 * 0.25 + 0.04) * grass_amt;
	float grass = clamp(gp + COLOR.a * grass_vert * (0.55 + 0.45 * m3), 0.0, 1.0);
	grass *= (1.0 - wr) * (1.0 - smoothstep(0.1, 0.32, slope)) * (1.0 - smoothstep(0.25, 0.6, road_w));
	vec3 gc = grass_col * mix(0.8, 1.25, m3) * mix(vec3(1.0), vec3(1.12, 1.05, 0.8), smoothstep(0.4, 0.8, m));
	alb = mix(alb, gc * (0.55 + 0.9 * lum), grass * 0.85);
	// дорога: неровный край, плотный тёмный центр, светлая пыльная обочина
	float rw = smoothstep(0.38, 0.62, road_w + (m3 - 0.5) * 0.35);
	float verge = smoothstep(0.04, 0.3, road_w) * (1.0 - rw);
	alb *= 1.0 + 0.16 * verge;
	alb = mix(alb, alb * vec3(0.7, 0.66, 0.6), rw);
	alb *= 1.0 - 0.1 * smoothstep(0.85, 1.0, road_w) * (0.4 + m3);
	alb *= 0.78 + 0.44 * m;
	// крупные пятна: следы техники, сырая/выжженная земля — убирает «однотонный песок»
	alb *= mix(vec3(0.8, 0.78, 0.76), vec3(1.04, 1.02, 0.99), smoothstep(0.25, 0.75, m2));
	// мелкая рябь яркости вблизи, чтобы земля не выглядела плоской
	alb *= 0.93 + 0.14 * texture(macro, wpos.xz * 0.19).r;
	// зерно/камешки под ногами и мелкая текстура вблизи (до 40 м), тёмные осыпи на склонах
	float near = 1.0 - smoothstep(12.0, 40.0, dist);
	if (near > 0.01) {
		float dn = dot(texture(tex_a, UV * 4.3).rgb, vec3(0.3, 0.59, 0.11));
		alb *= mix(1.0, 0.7 + 0.6 * dn / max(lum, 0.15), near * 0.5 * (1.0 - wr));
		alb *= mix(1.0, 0.86 + 0.28 * texture(macro, wpos.xz * 1.7).r, near);
	}
	alb *= mix(1.0, 0.8, smoothstep(0.12, 0.45, slope) * (1.0 - wr * 0.5));
	ALBEDO = alb;
	ROUGHNESS = mix(0.96, 0.86, wr) - 0.06 * rw;
	SPECULAR = 0.2;
	if (use_normal > 0.5) {
		vec3 na = texture(nor_a, UV).rgb;
		vec3 nr = texture(nor_r, UV * 0.55).rgb;
		NORMAL_MAP = mix(na, nr, wr);
	}
}
