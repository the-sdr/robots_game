shader_type canvas_item;

// The main menu's background: the robot's view of a hillside at night, the
// same language as the detector (scripts/detector.gd) - height contours that
// drift slowly, a faint grid, a sweep ring rolling out every few seconds and a
// warm spot that flares when the ring passes it. Cheap: a few sines per pixel.

uniform vec3 deep : source_color = vec3(0.012, 0.035, 0.05);
uniform vec3 teal : source_color = vec3(0.03, 0.14, 0.16);
uniform vec3 line_colour : source_color = vec3(0.35, 0.95, 1.0);
uniform vec3 warm : source_color = vec3(1.0, 0.5, 0.15);
uniform float sweep_period = 6.0;
uniform vec2 sweep_centre = vec2(0.72, 0.62);    // in UV
uniform vec2 find_at = vec2(0.86, 0.38);          // the warm spot, in UV

float height(vec2 p, float t) {
	return sin(p.x * 0.9 + sin(p.y * 0.6 + t * 0.05) * 1.4) * 0.9
		+ sin(p.y * 1.1 - p.x * 0.3 + t * 0.03) * 0.7
		+ sin((p.x + p.y) * 2.3 + t * 0.02) * 0.18;
}

float iso(float v, float width) {
	float d = abs(fract(v - 0.5) - 0.5);
	return 1.0 - smoothstep(0.0, width, d);
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y > 0.0 ? SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x : 16.0 / 9.0;
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y) * 6.0;
	float t = TIME;
	float h = height(p, t);
	float contour = iso(h * 3.0, fwidth(h * 3.0) * 1.3);
	float major = iso(h * 0.75, fwidth(h * 0.75) * 1.6);
	vec2 g = p * 2.0;
	vec2 gl = 1.0 - smoothstep(vec2(0.0), fwidth(g) * 1.2, abs(fract(g - 0.5) - 0.5));
	float grid = max(gl.x, gl.y);

	vec2 c = vec2(sweep_centre.x * aspect, sweep_centre.y) * 6.0;
	float d = distance(p, c);
	float phase = mod(t, sweep_period) / sweep_period;
	float r = phase * phase * 18.0;
	float fd = (d - r) / 0.25;
	float ring = exp(-fd * fd) * (1.0 - phase);

	vec2 f = vec2(find_at.x * aspect, find_at.y) * 6.0;
	float fdist = distance(p, f);
	float passed = clamp((r - distance(c, f)) * 2.0, 0.0, 1.0) * (1.0 - phase * 0.8);
	float blob = exp(-fdist * fdist * 1.8) * (0.25 + passed);

	vec3 col = mix(deep, teal, clamp(0.35 + h * 0.18 + (1.0 - uv.y) * 0.25, 0.0, 1.0));
	col += line_colour * (contour * 0.10 + major * 0.18 + grid * 0.025);
	col += line_colour * ring * 0.55;
	col += warm * blob * 0.55;
	float vignette = smoothstep(1.15, 0.35, distance(uv, vec2(0.5, 0.5)));
	col *= mix(0.45, 1.0, vignette);
	COLOR = vec4(col, 1.0);
}
