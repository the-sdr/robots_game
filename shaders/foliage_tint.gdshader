shader_type spatial;
render_mode cull_disabled;

// Leaves drawn from the pack's plain white leaf masks, tinted per tree.
// Individual trees (solid_tree.gd) set the per-instance `leaf_tint`;
// merged background trees (level_bake.gd) carry their tint in the vertex
// colour, which individual trees ignore.

uniform sampler2D leaf_mask : source_color, filter_linear_mipmap_anisotropic;
uniform bool batched = false;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
uniform float brightness : hint_range(0.3, 2.0) = 1.0;
instance uniform vec3 leaf_tint : source_color = vec3(0.34, 0.52, 0.20);

varying vec3 tint;

void vertex() {
	// Vertex colours arrive as raw sRGB numbers; the instance uniform is already linear.
	tint = batched ? pow(COLOR.rgb, vec3(2.2)) : leaf_tint;
}

void fragment() {
	vec4 mask = texture(leaf_mask, UV);
	ALBEDO = mask.rgb * tint * brightness;
	ALPHA = mask.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
