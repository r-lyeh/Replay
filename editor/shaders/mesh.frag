#version 450
// mesh.frag - a 3D mesh's pixels: its lit colour times its texture (nearest, repeating),
// alpha tested at 0.5 (raster3d.h does the same). Shadows: where the sun's depth map has
// something nearer, the sun's share is taken away (PCF 3x3, texel by texel: raster3d.h's
// r3_shadow_at). SDL_gpu's sets: fragment samplers are set 2, uniform buffers set 3.
layout(location = 0) in vec4 v_col;
layout(location = 1) in vec2 v_uv;
layout(location = 2) in vec3 v_sun;
layout(location = 3) in vec3 v_lpos;
layout(location = 4) in float v_paint;
layout(set = 2, binding = 0) uniform sampler2D tex;
layout(set = 2, binding = 1) uniform sampler2D shadow_map;
layout(set = 3, binding = 0) uniform F {
  vec4 shadow;     // x: on (1), y: the map's size, z: bias, w: 1 lines (the editor's grid: its own alpha, no texture, no test), 2 particles (blended: no test)
} f;
layout(location = 0) out vec4 o_col;
float lit_at(vec3 p) {
  float S = f.shadow.y;
  if (p.x < -1.0 || p.x > 1.0 || p.y < -1.0 || p.y > 1.0 || p.z > 1.0) return 1.0;
  int ix = int(floor((p.x * 0.5 + 0.5) * S)), iy = int(floor((0.5 - p.y * 0.5) * S)), n = int(S) - 1;
  float lit = 0.0;
  for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
    float d = texelFetch(shadow_map, ivec2(clamp(ix + dx, 0, n), clamp(iy + dy, 0, n)), 0).r;
    if (p.z - f.shadow.z <= d) lit += 1.0;
  }
  return lit / 9.0;
}
void main() {
  if (f.shadow.w > 1.5) { vec4 p = v_col * texture(tex, v_uv); o_col = vec4(clamp(p.rgb, 0.0, 1.0), p.a); return; }   // (particles: soft, blended)
  if (f.shadow.w > 0.5) { o_col = vec4(clamp(v_col.rgb, 0.0, 1.0), v_col.a); return; }   // (lines: blended, fading out)
  vec4 c = v_col;
  if (f.shadow.x > 0.5) {
    float lit = lit_at(v_lpos);
    if (lit < 1.0) c.rgb -= v_sun * (1.0 - lit);
  }
  vec4 tx = texture(tex, v_uv);
  if (v_paint > 0.5) tx.rgb = vec3(0.35 + 0.65 * dot(tx.rgb, vec3(0.299, 0.587, 0.114)));   // (painted: the texture's light alone)
  c *= tx;
  if (c.a < 0.5) discard;
  o_col = vec4(clamp(c.rgb, 0.0, 1.0), 1.0);
}
