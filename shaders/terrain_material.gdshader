shader_type canvas_item;

uniform sampler2D dirt_texture : source_color, repeat_enable, filter_linear;
uniform sampler2D rock_texture : source_color, repeat_enable, filter_linear;
uniform sampler2D bedrock_texture : source_color, repeat_enable, filter_linear;
uniform sampler2D constructed_texture : source_color, repeat_enable, filter_linear;
uniform sampler2D rim_texture : source_color, repeat_enable, filter_linear;
uniform sampler2D material_map_texture : filter_linear;
uniform vec4 dirt_fallback : source_color = vec4(0.40, 0.27, 0.15, 1.0);
uniform vec4 rock_fallback : source_color = vec4(0.33, 0.38, 0.42, 1.0);
uniform vec4 bedrock_fallback : source_color = vec4(0.15, 0.17, 0.20, 1.0);
uniform vec4 constructed_fallback : source_color = vec4(0.66, 0.46, 0.24, 1.0);
uniform vec4 exposed_rim_color : source_color = vec4(0.19, 0.12, 0.07, 1.0);
uniform vec2 chunk_world_origin = vec2(0.0);
uniform vec2 chunk_world_size = vec2(120.0);
uniform vec2 material_uv_origin = vec2(0.0);
uniform vec2 material_uv_size = vec2(1.0);
uniform float texture_world_size = 512.0;

float occupancy_at(vec2 uv) {
	return texture(material_map_texture, clamp(uv, vec2(0.0), vec2(1.0))).a;
}

vec4 sample_or_fallback(sampler2D source, vec2 uv, vec4 fallback_color) {
	vec4 sampled = texture(source, uv);
	return sampled.a > 0.01 ? sampled : fallback_color;
}

void fragment() {
	vec2 local_uv = (UV - material_uv_origin) / material_uv_size;
	ivec2 texture_size = textureSize(material_map_texture, 0);
	vec2 world_position = chunk_world_origin + local_uv * chunk_world_size;
	vec2 contour_warp = vec2(
		sin(world_position.y * 0.073 + sin(world_position.x * 0.021))
			+ 0.45 * sin(world_position.y * 0.031 - world_position.x * 0.047),
		sin(world_position.x * 0.067 + sin(world_position.y * 0.019))
			+ 0.45 * sin(world_position.x * 0.029 + world_position.y * 0.043)
	) * 0.42;
	vec2 warped_uv = UV + contour_warp / vec2(texture_size);
	ivec2 cell = clamp(ivec2(warped_uv * vec2(texture_size)), ivec2(0), texture_size - ivec2(1));
	int material_id = int(round(texelFetch(material_map_texture, cell, 0).r * 255.0));
	vec2 texel = 1.0 / vec2(texture_size);
	float center_occupancy = occupancy_at(warped_uv);
	float neighbor_occupancy = (
		occupancy_at(warped_uv + vec2(texel.x, 0.0))
		+ occupancy_at(warped_uv - vec2(texel.x, 0.0))
		+ occupancy_at(warped_uv + vec2(0.0, texel.y))
		+ occupancy_at(warped_uv - vec2(0.0, texel.y))
	) * 0.25;
	float contour_noise = sin(world_position.x * 0.071 + sin(world_position.y * 0.037)) * 0.025;
	float alpha = smoothstep(0.34 + contour_noise, 0.66 + contour_noise, center_occupancy);
	float interior = smoothstep(0.55, 0.92, min(center_occupancy, neighbor_occupancy + 0.2));
	vec2 fill_uv = world_position / max(texture_world_size, 1.0);
	vec4 fill = dirt_fallback;
	if (material_id == 1) {
		fill = sample_or_fallback(dirt_texture, fill_uv, dirt_fallback);
	} else if (material_id == 2) {
		fill = sample_or_fallback(rock_texture, fill_uv, rock_fallback);
	} else if (material_id == 3) {
		fill = sample_or_fallback(bedrock_texture, fill_uv, bedrock_fallback);
	} else if (material_id == 4) {
		fill = sample_or_fallback(constructed_texture, fill_uv, constructed_fallback);
	}
	vec4 rim_fill = sample_or_fallback(rim_texture, fill_uv * 1.15, exposed_rim_color);
	vec3 shaded = mix(rim_fill.rgb, fill.rgb, interior);
	COLOR = vec4(shaded, alpha);
}
