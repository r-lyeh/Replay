#version 450
// mesh.vert - a 3D mesh's vertices (editor/render3d.h): clip space, and its colour lit as the CPU
// rasterizer lights it (raster3d.h: Lambert from one sun, plus ambient, per vertex); the sun's share
// of it and where it is in the sun's view (shadows: mesh.frag). Also the shadow pass's (vp: the sun's).
// Instanced: each instance's model matrix and tint come per instance (vertex buffer 1, instance rate):
// a mesh drawn many times is one draw. SKIN (mesh_skin_vert.h, the same source): skinned on the GPU,
// 4 joints a vertex (vertex buffer 2); every skinned copy's matrices in one storage buffer (the frame's), each
// instance where its own begin (i_bone.x): copies of one mesh, each in its own pose, are one draw too.
// (MSL_BIND: Metal's numbering: the storage buffer after the uniform buffer, buffer(1); Vulkan's set 0, binding 0)
// SDL_gpu's sets: vertex uniform buffers are set 1.
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_nrm;
layout(location = 2) in vec2 a_uv;
layout(location = 3) in vec4 a_col;
layout(location = 4) in vec4 i_m0;   // the instance's model matrix (columns)
layout(location = 5) in vec4 i_m1;
layout(location = 6) in vec4 i_m2;
layout(location = 7) in vec4 i_m3;
layout(location = 8) in vec4 i_tint;
#ifdef SKIN
layout(location = 9) in uvec4 a_jnt;
layout(location = 10) in vec4 a_wgt;
layout(location = 11) in vec4 i_bone;   // x: where its matrices begin in the storage buffer
#endif
layout(set = 1, binding = 0) uniform U {
  mat4 vp;         // view-projection (the shadow pass: the sun's)
  mat4 light;      // the sun's view-projection (the world to its clip space)
  vec4 base;       // the part's base colour
  vec4 ambient;
  vec4 sun_dir;    // where it shines (normalized); w: the shadow test's normal offset (m)
  vec4 sun_col;
  vec4 wind;       // foliage: xy the wind (world x, z: its direction times its strength), z: seconds, w: 1 on; lines: w -R (unlit, fading out by R m from the camera)
  vec4 eye;        // foliage: xyz the camera, w: how far it stays whole (m; past it fewer copies, none at 1.5x; 0: no fading)
} u;
#ifdef SKIN
#ifdef MSL_BIND
layout(std430, set = 0, binding = 1) readonly buffer J { mat4 j[]; } sk;
#else
layout(std430, set = 0, binding = 0) readonly buffer J { mat4 j[]; } sk;
#endif
#endif
layout(location = 0) out vec4 v_col;
layout(location = 1) out vec2 v_uv;
layout(location = 2) out vec3 v_sun;
layout(location = 3) out vec3 v_lpos;
layout(location = 4) out float v_paint;           // (a tint's alpha 2 + a: painted, its texture grey under it: render.h's LOD colours)
void main() {
  vec3 p = a_pos, nr = a_nrm;
#ifdef SKIN
  float s = a_wgt.x + a_wgt.y + a_wgt.z + a_wgt.w;
  if (s > 1e-6) {                                  // (no weights: as it is)
    uvec4 jj = min(a_jnt, uvec4(255u)) + uvec4(uint(i_bone.x));
    mat4 S = sk.j[jj.x] * a_wgt.x + sk.j[jj.y] * a_wgt.y + sk.j[jj.z] * a_wgt.z + sk.j[jj.w] * a_wgt.w;
    p = (S * vec4(p, 1.0)).xyz;
    nr = mat3(S) * nr;                             // (no shear in a skeleton: the matrix itself, normalized below)
  }
#endif
  mat4 model = mat4(i_m0, i_m1, i_m2, i_m3);
  vec4 wp = model * vec4(p, 1.0);
  vec3 org = i_m3.xyz;                             // (the copy's place)
  if (u.wind.w > 0.0) {                            // the wind (Outerra's grass): the copy bends with it, more by its tip,
    float ph = dot(org.xz, vec2(0.37, 0.71));      // each place in its own phase: waves running over the field
    float gust = 0.35 + 0.6 * sin(u.wind.z * 1.7 + ph) + 0.25 * sin(u.wind.z * 3.1 + ph * 1.9);
    float h = max(p.y, 0.0);
    wp.xz += u.wind.xy * gust * h * h * length(i_m1.xyz);
  }
  bool gone = false;
  if (u.eye.w > 0.0) {                             // far away, fewer copies (each its own threshold): whole up to
    float d = distance(org, u.eye.xyz);            // eye.w, thinning till none at 1.5 eye.w
    float keep = clamp(1.0 - (d - u.eye.w) / (0.5 * u.eye.w), 0.0, 1.0);
    float hsh = fract(sin(dot(org.xz, vec2(12.9898, 78.233))) * 43758.5453);
    gone = hsh >= keep;
  }
  gl_Position = gone ? vec4(2.0, 2.0, 2.0, 1.0) : u.vp * wp;   // (gone: outside the view, clipped)
  vec3 n = normalize(transpose(inverse(mat3(model))) * nr);
  float lam = max(0.0, -dot(n, u.sun_dir.xyz));
  vec3 light = u.ambient.rgb + u.sun_col.rgb * lam;
  bool paint = i_tint.a > 1.5;
  vec4 base = u.base * vec4(i_tint.rgb, paint ? i_tint.a - 2.0 : i_tint.a);
  v_paint = paint ? 1.0 : 0.0;
  v_col = vec4(a_col.rgb * base.rgb * light, a_col.a * base.a);
  if (u.wind.w < 0.0)                              // (lines: their own colours, unlit; the grid fainter far away, where its lines crowd)
    v_col = vec4(a_col.rgb * base.rgb, a_col.a * base.a * clamp(1.0 - distance(wp.xyz, u.eye.xyz) / -u.wind.w, 0.0, 1.0));
  v_sun = a_col.rgb * base.rgb * u.sun_col.rgb * lam;
  vec3 lp = wp.xyz + n * u.sun_dir.w;              // (pushed off its surface: no acne)
  v_lpos = (u.light * vec4(lp, 1.0)).xyz;
  v_uv = a_uv;
}
