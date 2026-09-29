shader_type spatial;

// Painterly terrain. Four ground layers blended by the per-vertex weights the
// level build writes into the vertex colour:
//   R = path dirt, G = mud, B = moss/rock, whatever is left = forest floor.
// Each albedo texture carries its height map in alpha, so layers blend by
// height (dirt shows between leaves) instead of a soft fade.
// Kept cheap for integrated GPUs: 8 texture reads, no triplanar.

uniform sampler2D forest_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

group_uniforms layout;
uniform float tile_size = 4.0;             // metres per texture repeat
uniform float blend_sharpness : hint_range(0.02, 1.0) = 0.2;   // height-blend band; smaller = crisper edges

group_uniforms colour;                      // evens out sets photographed in different light
uniform vec3 forest_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 dirt_tint : source_color = vec3(0.72, 0.62, 0.52);
uniform vec3 mud_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 moss_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float brightness : hint_range(0.3, 2.0) = 1.1;

group_uniforms painterly;
uniform float color_bands : hint_range(0.0, 16.0) = 7.0;       // luminance steps; 0 = off
uniform float band_softness : hint_range(0.0, 1.0) = 0.6;
uniform float saturation : hint_range(0.0, 2.0) = 1.2;
uniform float detail_softening : hint_range(0.0, 4.0) = 1.2;   // mip bias: higher = softer, more painted
uniform float normal_strength : hint_range(0.0, 2.0) = 0.6;
uniform float slope_darkening : hint_range(0.0, 1.0) = 0.25;

// The detector's robot view (scripts/detector.gd sets these at runtime; they
// stay at their defaults in the saved material, so the normal look is untouched).
// Everything below is skipped while scan_amount and scan_spots_on are 0.
group_uniforms detector;
uniform float scan_amount = 0.0;            // 0 = normal look, 1 = full robot view (grid, contours)
uniform float scan_spots_on = 0.0;          // 1 while any warm spot is still glowing
uniform vec3 scan_origin = vec3(0.0);
uniform float scan_wave = -100.0;           // distance of the sweep's bright front from the robot
uniform float scan_range = 60.0;
uniform vec4 scan_spots[12];                // xyz = centre (world), w = radius (0 = unused)
uniform float scan_spot_heat[12];           // 0..1: how warm each spot glows right now

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = world_pos.xz / tile_size;
	vec4 a0 = texture(forest_albedo, uv, detail_softening);
	vec4 a1 = texture(dirt_albedo, uv, detail_softening);
	vec4 a2 = texture(mud_albedo, uv, detail_softening);
	vec4 a3 = texture(moss_albedo, uv, detail_softening);

	vec4 w = vec4(clamp(1.0 - COLOR.r - COLOR.g - COLOR.b, 0.0, 1.0), COLOR.r, COLOR.g, COLOR.b);
	vec4 h = vec4(a0.a, a1.a, a2.a, a3.a) + w;
	float top = max(max(h.x, h.y), max(h.z, h.w)) - blend_sharpness;
	vec4 hw = max(h - top, 0.0) * step(0.001, w);    // a layer with no weight never shows
	hw /= max(hw.x + hw.y + hw.z + hw.w, 0.0001);

	vec3 col = a0.rgb * forest_tint * hw.x + a1.rgb * dirt_tint * hw.y
			+ a2.rgb * mud_tint * hw.z + a3.rgb * moss_tint * hw.w;
	vec3 nrm = texture(forest_normal, uv, detail_softening).rgb * hw.x
			+ texture(dirt_normal, uv, detail_softening).rgb * hw.y
			+ texture(mud_normal, uv, detail_softening).rgb * hw.z
			+ texture(moss_normal, uv, detail_softening).rgb * hw.w;

	// Painterly: soft luminance bands, a little extra saturation.
	col *= brightness;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	if (color_bands > 0.0) {
		float q = lum * color_bands;
		float step_edge = smoothstep(0.5 - band_softness * 0.5, 0.5 + band_softness * 0.5, fract(q));
		float banded = (floor(q) + step_edge) / color_bands;
		col *= banded / max(lum, 0.001);
	}
	col = mix(vec3(dot(col, vec3(0.299, 0.587, 0.114))), col, saturation);
	col *= 1.0 - slope_darkening * (1.0 - clamp(world_normal.y, 0.0, 1.0)) * 2.0;

	if (scan_amount > 0.001 || scan_spots_on > 0.5) {
		float d = distance(world_pos.xz, scan_origin.xz);
		// robot view: the ground goes dark and cool so the lines read
		float lum_v = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(lum_v) * vec3(0.3, 0.5, 0.55), scan_amount * 0.8);
		// height contours every 0.5 m (major every 2.5 m) and a 2 m grid, antialiased
		float c1 = world_pos.y / 0.5;
		float contour = 1.0 - smoothstep(0.0, fwidth(c1) * 1.5, abs(fract(c1 - 0.5) - 0.5));
		float c2 = world_pos.y / 2.5;
		float major = 1.0 - smoothstep(0.0, fwidth(c2) * 2.0, abs(fract(c2 - 0.5) - 0.5));
		vec2 g = world_pos.xz / 2.0;
		vec2 gl = 1.0 - smoothstep(vec2(0.0), fwidth(g) * 1.2, abs(fract(g - 0.5) - 0.5));
		float grid = max(gl.x, gl.y) * 0.45;
		float near = 1.0 - smoothstep(scan_range * 0.5, scan_range, d);
		float fd = (d - scan_wave) / 1.4;
		float front = exp(-fd * fd);
		float lines = max(max(contour * 0.6, major), grid) * near;
		vec3 glow = vec3(0.35, 0.95, 1.0) * (lines * 0.7 + front * 1.4) * scan_amount;
		// warm spots: a soft blob, plus a crisp ring once the fix is tight (radius under 1.5 m)
		vec3 warm = vec3(0.0);
		for (int i = 0; i < 12; i++) {
			float r = scan_spots[i].w;
			if (r > 0.0 && scan_spot_heat[i] > 0.0) {
				float sd = distance(world_pos.xz, scan_spots[i].xz) / r;
				float blob = exp(-sd * sd * 2.5);
				float rd = (sd - 1.0) * 7.0;
				float ring = exp(-rd * rd) * (1.0 - smoothstep(1.0, 1.5, r));
				warm += mix(vec3(1.0, 0.35, 0.08), vec3(1.0, 0.8, 0.3), blob) * (blob * 0.9 + ring * 1.4) * scan_spot_heat[i];
			}
		}
		EMISSION = glow + warm * 1.5;
	}

	ALBEDO = clamp(col, 0.0, 1.0);
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
	SPECULAR = 0.2;
}
