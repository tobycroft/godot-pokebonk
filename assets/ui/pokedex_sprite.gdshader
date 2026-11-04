// Pokédex-only sprite filter. Mirrors what the web dex does with CSS filters:
//  - unseen tiles: filter:brightness(0) invert() opacity(.2)  -> white silhouette
//  - unseen detail: filter:brightness(0) opacity(.6)         -> black silhouette
//  - shiny preview: filter:hue-rotate(...)                    -> hue rotation
shader_type canvas_item;

uniform float hue_deg : hint_range(0.0, 360.0) = 0.0;
uniform float silhouette : hint_range(0.0, 1.0) = 0.0;
uniform float silhouette_white : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_mul : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (silhouette > 0.5) {
		c.rgb = silhouette_white > 0.5 ? vec3(1.0) : vec3(0.0);
	} else if (hue_deg != 0.0) {
		// Rotation around the RGB grey axis, matching CSS hue-rotate()'s model.
		float a = radians(hue_deg);
		vec3 axis = vec3(0.57735);
		float ca = cos(a);
		float sa = sin(a);
		c.rgb = clamp(c.rgb * ca + cross(axis, c.rgb) * sa + axis * dot(axis, c.rgb) * (1.0 - ca), 0.0, 1.0);
	}
	c.a *= alpha_mul;
	COLOR = c;
}
