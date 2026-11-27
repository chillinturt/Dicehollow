shader_type canvas_item;
// Masks a portrait texture to a soft-edged circle for map tokens.
uniform float feather = 0.02;
uniform float grey = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = distance(UV, vec2(0.5));
	float a = 1.0 - smoothstep(0.5 - feather, 0.5, d);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, vec3(l * 0.6), grey);
	COLOR = vec4(c.rgb, c.a * a) * COLOR;
}
