// render3d.h - the GPU path of 3D viewports (docs/3D.md, phase 3): Mesh3D drawn
// by SDL_gpu into the viewport's own textures (colour, depth), which the 2D
// renderer then draws like any picture (one device: editor/gpu.h). Part of
// replay.c: included by render.h, after raster3d.h.
//
// The same picture as the CPU rasterizer (raster3d.h): Lambert from one sun
// plus ambient per vertex (editor/shaders/mesh.vert), times the texture,
// nearest, alpha tested (mesh.frag); shadows: a depth pass from the sun first (the shadow
// pipeline: mesh.vert, shadow.frag), the same PCF test as raster3d.h's. Shaders: SPIR-V and MSL, precompiled
// (editor/tools/shaders.sh). No device, or no pipeline: the CPU draws instead.
#pragma once
#include "shaders/mesh_vert.h"
#include "shaders/mesh_skin_vert.h"
#include "shaders/mesh_frag.h"
#include "shaders/shadow_frag.h"

typedef struct { float pos[3], nrm[3], uv[2]; unsigned char col[4]; } G3Vertex;   // 36 bytes
typedef struct { unsigned short j[4]; float w[4]; } G3SkinVertex;   // 24 bytes: a skinned mesh's binds and weights (vertex buffer 2)
typedef struct { float model[16], tint[4], bone[4]; } G3Instance;   // 96 bytes: a drawn copy (vertex buffer 1, instance rate); bone[0]: where its skin's matrices begin (the frame's bones buffer)
typedef struct { float vp[16], light[16], base[4], ambient[4], sun_dir[4], sun_col[4], wind[4], eye[4]; } G3Uniforms;
static float g3_eye[3], g3_time;                   // (the view's camera, the seconds: set before g3_render, for foliage's wind and fading)
#define G3_MAX_JOINTS 256                          // (mesh.vert's J: more binds than that: skinned on the CPU)
typedef struct { float shadow[4]; } G3FragUniforms;
static struct {
  bool tried, ok;
  SDL_GPUGraphicsPipeline *pipe, *shadow_pipe;     // shadow_pipe: NULL when the depth format can't be sampled (no GPU shadows: the CPU's)
  SDL_GPUGraphicsPipeline *line_pipe;              // lines (Mesh3D.lines: the editor's grid, dd's 3D lines): blended, depth tested, not written
  SDL_GPUGraphicsPipeline *wire_pipe;
  SDL_GPUGraphicsPipeline *part_pipe, *add_pipe;   // particles (G3Item.part): blended (alpha / additive), depth tested, not written
  SDL_GPUTexture *soft;                            // (a particle's soft disc)              // wireframe (mesh = { ..., wire = true }): the triangles' edges
  SDL_GPUGraphicsPipeline *skin_pipe, *skin_shadow_pipe;   // skinned on the GPU (NULL: posed on the CPU, as before)
  SDL_GPUSampler *samp, *shadow_samp;
  SDL_GPUTexture *white;
  SDL_GPUTextureFormat depth;
  char err[160];
} G3;
typedef struct { char file[1024]; unsigned version; SDL_GPUBuffer *vb, *ib, *sb; SDL_GPUTexture **tex; int ntex, nv, ni; } G3Mesh;   // sb: its binds and weights (skinned)
static G3Mesh g3meshes[128];
static int ng3meshes;
typedef struct { char file[1024]; SDL_GPUTexture *t; int w, h; } G3Tex;   // (a texture = "..." of a node: by its file)
static G3Tex g3texs[32];
static int ng3texs;

static SDL_GPUTexture *g3_texture(int w, int h, const unsigned char *rgba);
static void g3_release(void);
static bool g3_init(void) {
  if (G3.tried) return G3.ok;
  G3.tried = true;
  if (!g_gpu) { SDL_strlcpy(G3.err, "no GPU device", sizeof G3.err); return false; }
  const char *env = SDL_getenv("REPLAY_3D");
  if (env && !SDL_strcmp(env, "cpu")) { SDL_strlcpy(G3.err, "REPLAY_3D=cpu", sizeof G3.err); return false; }
  SDL_GPUShaderFormat have = SDL_GetGPUShaderFormats(g_gpu);
  SDL_GPUShaderFormat fmt = (have & SDL_GPU_SHADERFORMAT_SPIRV) ? SDL_GPU_SHADERFORMAT_SPIRV : (have & SDL_GPU_SHADERFORMAT_MSL) ? SDL_GPU_SHADERFORMAT_MSL : 0;
  if (!fmt) { SDL_strlcpy(G3.err, "no shaders for this backend", sizeof G3.err); return false; }
  bool msl = fmt == SDL_GPU_SHADERFORMAT_MSL;
  SDL_GPUShaderCreateInfo vi = { 0 }, fi = { 0 };
  vi.code = msl ? (const Uint8 *)mesh_vert_msl : mesh_vert_spv;
  vi.code_size = msl ? SDL_strlen(mesh_vert_msl) : sizeof mesh_vert_spv;
  vi.entrypoint = msl ? "main0" : "main"; vi.format = fmt; vi.stage = SDL_GPU_SHADERSTAGE_VERTEX; vi.num_uniform_buffers = 1;
  SDL_GPUShaderCreateInfo si0 = { 0 };
  si0.code = msl ? (const Uint8 *)shadow_frag_msl : shadow_frag_spv;
  si0.code_size = msl ? SDL_strlen(shadow_frag_msl) : sizeof shadow_frag_spv;
  si0.entrypoint = msl ? "main0" : "main"; si0.format = fmt; si0.stage = SDL_GPU_SHADERSTAGE_FRAGMENT;
  fi.code = msl ? (const Uint8 *)mesh_frag_msl : mesh_frag_spv;
  fi.code_size = msl ? SDL_strlen(mesh_frag_msl) : sizeof mesh_frag_spv;
  fi.entrypoint = msl ? "main0" : "main"; fi.format = fmt; fi.stage = SDL_GPU_SHADERSTAGE_FRAGMENT; fi.num_samplers = 2; fi.num_uniform_buffers = 1;
  SDL_GPUShaderCreateInfo ki = vi;                 // (the skinned variant: the frame's bones, a storage buffer)
  ki.code = msl ? (const Uint8 *)mesh_skin_vert_msl : mesh_skin_vert_spv;
  ki.code_size = msl ? SDL_strlen(mesh_skin_vert_msl) : sizeof mesh_skin_vert_spv;
  ki.num_uniform_buffers = 1; ki.num_storage_buffers = 1;
  SDL_GPUShader *vs = SDL_CreateGPUShader(g_gpu, &vi), *fs = SDL_CreateGPUShader(g_gpu, &fi), *ks = SDL_CreateGPUShader(g_gpu, &ki);
  if (!vs || !fs) {
    SDL_snprintf(G3.err, sizeof G3.err, "shaders: %s", SDL_GetError());
    if (vs) SDL_ReleaseGPUShader(g_gpu, vs);
    if (fs) SDL_ReleaseGPUShader(g_gpu, fs);
    if (ks) SDL_ReleaseGPUShader(g_gpu, ks);
    return false;
  }
  G3.depth = SDL_GPU_TEXTUREFORMAT_D32_FLOAT;       // (Apple GPUs have no 24-bit depth: docs/3D.md 9.1)
  if (!SDL_GPUTextureSupportsFormat(g_gpu, G3.depth, SDL_GPU_TEXTURETYPE_2D, SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET)) G3.depth = SDL_GPU_TEXTUREFORMAT_D24_UNORM;
  SDL_GPUVertexBufferDescription vb[3] = {         // its vertices; each copy drawn (instance rate); a skin's binds and weights
    { 0, sizeof(G3Vertex), SDL_GPU_VERTEXINPUTRATE_VERTEX, 0 },
    { 1, sizeof(G3Instance), SDL_GPU_VERTEXINPUTRATE_INSTANCE, 0 },
    { 2, sizeof(G3SkinVertex), SDL_GPU_VERTEXINPUTRATE_VERTEX, 0 },
  };
  SDL_GPUVertexAttribute va[12] = {
    { 0, 0, SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, offsetof(G3Vertex, pos) },
    { 1, 0, SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, offsetof(G3Vertex, nrm) },
    { 2, 0, SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, offsetof(G3Vertex, uv) },
    { 3, 0, SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM, offsetof(G3Vertex, col) },
    { 4, 1, SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, 0 },
    { 5, 1, SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, 16 },
    { 6, 1, SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, 32 },
    { 7, 1, SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, 48 },
    { 8, 1, SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, offsetof(G3Instance, tint) },
    { 9, 2, SDL_GPU_VERTEXELEMENTFORMAT_USHORT4, offsetof(G3SkinVertex, j) },
    { 10, 2, SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, offsetof(G3SkinVertex, w) },
    { 11, 1, SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, offsetof(G3Instance, bone) },
  };
  SDL_GPUColorTargetDescription ct = { 0 };
  ct.format = SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
  SDL_GPUGraphicsPipelineCreateInfo pi = { 0 };
  pi.vertex_shader = vs; pi.fragment_shader = fs;
  pi.vertex_input_state.vertex_buffer_descriptions = vb; pi.vertex_input_state.num_vertex_buffers = 2;
  pi.vertex_input_state.vertex_attributes = va; pi.vertex_input_state.num_vertex_attributes = 9;
  pi.primitive_type = SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;
  pi.rasterizer_state.fill_mode = SDL_GPU_FILLMODE_FILL;
  pi.rasterizer_state.cull_mode = SDL_GPU_CULLMODE_BACK;
  pi.rasterizer_state.enable_depth_clip = true;    // (clipped at the near plane: SDL_gpu's default clamps, and what runs past the camera folds back in)
  pi.rasterizer_state.front_face = SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE;
  pi.depth_stencil_state.enable_depth_test = true; pi.depth_stencil_state.enable_depth_write = true;
  pi.depth_stencil_state.compare_op = SDL_GPU_COMPAREOP_LESS;
  pi.target_info.color_target_descriptions = &ct; pi.target_info.num_color_targets = 1;
  pi.target_info.has_depth_stencil_target = true; pi.target_info.depth_stencil_format = G3.depth;
  G3.pipe = SDL_CreateGPUGraphicsPipeline(g_gpu, &pi);
  {                                                // (lines: the grid; after the solid ones, blended over them)
    SDL_GPUGraphicsPipelineCreateInfo pl = pi;
    SDL_GPUColorTargetDescription cl = ct;
    cl.blend_state.enable_blend = true;
    cl.blend_state.src_color_blendfactor = SDL_GPU_BLENDFACTOR_SRC_ALPHA; cl.blend_state.dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA;
    cl.blend_state.color_blend_op = SDL_GPU_BLENDOP_ADD;
    cl.blend_state.src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ZERO; cl.blend_state.dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE;   // (the picture stays opaque)
    cl.blend_state.alpha_blend_op = SDL_GPU_BLENDOP_ADD;
    pl.target_info.color_target_descriptions = &cl;
    pl.primitive_type = SDL_GPU_PRIMITIVETYPE_LINELIST;
    pl.rasterizer_state.cull_mode = SDL_GPU_CULLMODE_NONE;
    pl.depth_stencil_state.enable_depth_write = false;
    pl.depth_stencil_state.compare_op = SDL_GPU_COMPAREOP_LESS_OR_EQUAL;
    G3.line_pipe = SDL_CreateGPUGraphicsPipeline(g_gpu, &pl);
  }
  for (int k = 0; k < 2; k++) {                    // (particles: alpha over, or added; after the solid ones)
    SDL_GPUGraphicsPipelineCreateInfo pp = pi;
    SDL_GPUColorTargetDescription cp = ct;
    cp.blend_state.enable_blend = true;
    cp.blend_state.src_color_blendfactor = SDL_GPU_BLENDFACTOR_SRC_ALPHA;
    cp.blend_state.dst_color_blendfactor = k ? SDL_GPU_BLENDFACTOR_ONE : SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA;
    cp.blend_state.color_blend_op = SDL_GPU_BLENDOP_ADD;
    cp.blend_state.src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ZERO; cp.blend_state.dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE;
    cp.blend_state.alpha_blend_op = SDL_GPU_BLENDOP_ADD;
    pp.target_info.color_target_descriptions = &cp;
    pp.rasterizer_state.cull_mode = SDL_GPU_CULLMODE_NONE;
    pp.depth_stencil_state.enable_depth_write = false;
    if (k) G3.add_pipe = SDL_CreateGPUGraphicsPipeline(g_gpu, &pp); else G3.part_pipe = SDL_CreateGPUGraphicsPipeline(g_gpu, &pp);
  }
  {                                                // (wireframe: the same, its edges only, both faces)
    SDL_GPUGraphicsPipelineCreateInfo pw = pi;
    pw.rasterizer_state.fill_mode = SDL_GPU_FILLMODE_LINE;
    pw.rasterizer_state.cull_mode = SDL_GPU_CULLMODE_NONE;
    G3.wire_pipe = SDL_CreateGPUGraphicsPipeline(g_gpu, &pw);
  }
  if (ks) {                                        // (skinned: the third buffer, two attributes more)
    SDL_GPUGraphicsPipelineCreateInfo pk = pi;
    pk.vertex_shader = ks;
    pk.vertex_input_state.num_vertex_buffers = 3; pk.vertex_input_state.num_vertex_attributes = 12;
    G3.skin_pipe = SDL_CreateGPUGraphicsPipeline(g_gpu, &pk);
  }
  SDL_GPUShader *sfs = SDL_CreateGPUShader(g_gpu, &si0);
  if (G3.pipe && sfs && SDL_GPUTextureSupportsFormat(g_gpu, G3.depth, SDL_GPU_TEXTURETYPE_2D, SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET | SDL_GPU_TEXTUREUSAGE_SAMPLER)) {
    pi.fragment_shader = sfs;                      // (the shadow pass: the sun's depth, both faces, no colour)
    pi.rasterizer_state.cull_mode = SDL_GPU_CULLMODE_NONE;
    pi.rasterizer_state.enable_depth_clip = false;  // (the sun's: clamped, so a caster nearer than its near plane still casts)
    pi.target_info.num_color_targets = 0; pi.target_info.color_target_descriptions = NULL;
    G3.shadow_pipe = SDL_CreateGPUGraphicsPipeline(g_gpu, &pi);
    if (ks && G3.skin_pipe) {
      pi.vertex_shader = ks;
      pi.vertex_input_state.num_vertex_buffers = 3; pi.vertex_input_state.num_vertex_attributes = 12;
      G3.skin_shadow_pipe = SDL_CreateGPUGraphicsPipeline(g_gpu, &pi);
    }
  }
  if (G3.skin_pipe && G3.shadow_pipe && !G3.skin_shadow_pipe) { SDL_ReleaseGPUGraphicsPipeline(g_gpu, G3.skin_pipe); G3.skin_pipe = NULL; }   // (both or neither)
  if (!G3.skin_pipe) SDL_Log("3D: no GPU skinning (skinned models posed on the CPU, drawn one by one): %s", ks ? SDL_GetError() : "its shader");
  if (sfs) SDL_ReleaseGPUShader(g_gpu, sfs);
  SDL_ReleaseGPUShader(g_gpu, vs);
  SDL_ReleaseGPUShader(g_gpu, fs);
  if (ks) SDL_ReleaseGPUShader(g_gpu, ks);
  if (!G3.pipe) { SDL_snprintf(G3.err, sizeof G3.err, "pipeline: %s", SDL_GetError()); return false; }
  SDL_GPUSamplerCreateInfo si = { 0 };
  si.min_filter = si.mag_filter = SDL_GPU_FILTER_NEAREST;
  si.mipmap_mode = SDL_GPU_SAMPLERMIPMAPMODE_NEAREST;
  si.address_mode_u = si.address_mode_v = si.address_mode_w = SDL_GPU_SAMPLERADDRESSMODE_REPEAT;
  G3.samp = SDL_CreateGPUSampler(g_gpu, &si);
  si.address_mode_u = si.address_mode_v = si.address_mode_w = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
  G3.shadow_samp = SDL_CreateGPUSampler(g_gpu, &si);
  static const unsigned char white[4] = { 255, 255, 255, 255 };
  G3.white = g3_texture(1, 1, white);
  G3.ok = G3.samp && G3.white;
  g_gpu_release = g3_release;
  if (!G3.ok) SDL_snprintf(G3.err, sizeof G3.err, "sampler: %s", SDL_GetError());
  return G3.ok;
}

// uploads: a buffer or a texture's pixels, through a transfer buffer, in a copy pass of their own
static bool g3_upload(SDL_GPUBuffer *buf, SDL_GPUTexture *tex, int w, int h, const void *data, Uint32 size) {
  SDL_GPUTransferBufferCreateInfo ti = { SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, size, 0 };
  SDL_GPUTransferBuffer *tb = SDL_CreateGPUTransferBuffer(g_gpu, &ti);
  if (!tb) return false;
  void *p = SDL_MapGPUTransferBuffer(g_gpu, tb, false);
  if (!p) { SDL_ReleaseGPUTransferBuffer(g_gpu, tb); return false; }
  SDL_memcpy(p, data, size);
  SDL_UnmapGPUTransferBuffer(g_gpu, tb);
  SDL_GPUCommandBuffer *cb = SDL_AcquireGPUCommandBuffer(g_gpu);
  SDL_GPUCopyPass *cp = cb ? SDL_BeginGPUCopyPass(cb) : NULL;
  if (cp) {
    if (buf) {
      SDL_GPUTransferBufferLocation src = { tb, 0 };
      SDL_GPUBufferRegion dst = { buf, 0, size };
      SDL_UploadToGPUBuffer(cp, &src, &dst, true);   // (cycled: a posed mesh's buffer may still be drawn from)
    } else {
      SDL_GPUTextureTransferInfo src = { tb, 0, (Uint32)w, (Uint32)h };
      SDL_GPUTextureRegion dst = { 0 };
      dst.texture = tex; dst.w = (Uint32)w; dst.h = (Uint32)h; dst.d = 1;
      SDL_UploadToGPUTexture(cp, &src, &dst, false);
    }
    SDL_EndGPUCopyPass(cp);
  }
  bool ok = cb && cp && SDL_SubmitGPUCommandBuffer(cb);
  if (cb && !cp) SDL_CancelGPUCommandBuffer(cb);
  SDL_ReleaseGPUTransferBuffer(g_gpu, tb);
  return ok;
}
static SDL_GPUTexture *g3_texture(int w, int h, const unsigned char *rgba) {
  SDL_GPUTextureCreateInfo ti = { 0 };
  ti.type = SDL_GPU_TEXTURETYPE_2D; ti.format = SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM; ti.usage = SDL_GPU_TEXTUREUSAGE_SAMPLER;
  ti.width = (Uint32)w; ti.height = (Uint32)h; ti.layer_count_or_depth = 1; ti.num_levels = 1;
  SDL_GPUTexture *t = SDL_CreateGPUTexture(g_gpu, &ti);
  if (t && !g3_upload(NULL, t, w, h, rgba, (Uint32)(w * h * 4))) { SDL_ReleaseGPUTexture(g_gpu, t); t = NULL; }
  return t;
}
static void g3_mesh_free(G3Mesh *g) {
  if (g->vb) SDL_ReleaseGPUBuffer(g_gpu, g->vb);
  if (g->ib) SDL_ReleaseGPUBuffer(g_gpu, g->ib);
  if (g->sb) SDL_ReleaseGPUBuffer(g_gpu, g->sb);
  for (int i = 0; i < g->ntex; i++) if (g->tex[i]) SDL_ReleaseGPUTexture(g_gpu, g->tex[i]);
  SDL_free(g->tex);
  SDL_zerop(g);
}
// a mesh's GPU copy: made once, again when its file is read again (its version)
static G3Mesh *g3_mesh(const Mesh3D *m) {
  G3Mesh *g = NULL;
  for (int i = 0; i < ng3meshes && !g; i++) if (!strcmp(g3meshes[i].file, m->file)) g = &g3meshes[i];
  if (g && g->version == m->version && g->vb) return g;
  G3Vertex *vs = NULL;
  if (g && m->posed && g->vb && g->nv == m->nv && g->ni == m->ni) {   // a posed copy: its vertices again, the rest kept (CPU skinning: docs/3D.md 15)
    vs = SDL_malloc(sizeof(G3Vertex) * (size_t)m->nv);
    if (!vs) return NULL;
    for (int i = 0; i < m->nv; i++) {
      SDL_memcpy(vs[i].pos, &m->pos[i * 3], 12); SDL_memcpy(vs[i].nrm, &m->nrm[i * 3], 12);
      SDL_memcpy(vs[i].uv, &m->uv[i * 2], 8); SDL_memcpy(vs[i].col, &m->col[i * 4], 4);
    }
    bool ok = g3_upload(g->vb, NULL, 0, 0, vs, (Uint32)(sizeof(G3Vertex) * m->nv));
    SDL_free(vs);
    g->version = m->version;
    return ok ? g : NULL;
  }
  if (!g) {
    if (ng3meshes == (int)SDL_arraysize(g3meshes)) { for (int i = 0; i < ng3meshes; i++) g3_mesh_free(&g3meshes[i]); ng3meshes = 0; }
    g = &g3meshes[ng3meshes++];
  }
  g3_mesh_free(g);
  SDL_strlcpy(g->file, m->file, sizeof g->file);
  g->version = m->version; g->nv = m->nv; g->ni = m->ni;
  vs = SDL_malloc(sizeof(G3Vertex) * (size_t)m->nv);
  if (!vs) return NULL;
  for (int i = 0; i < m->nv; i++) {
    SDL_memcpy(vs[i].pos, &m->pos[i * 3], 12); SDL_memcpy(vs[i].nrm, &m->nrm[i * 3], 12);
    SDL_memcpy(vs[i].uv, &m->uv[i * 2], 8); SDL_memcpy(vs[i].col, &m->col[i * 4], 4);
  }
  SDL_GPUBufferCreateInfo bv = { SDL_GPU_BUFFERUSAGE_VERTEX, (Uint32)(sizeof(G3Vertex) * m->nv), 0 };
  SDL_GPUBufferCreateInfo bi = { SDL_GPU_BUFFERUSAGE_INDEX, (Uint32)(sizeof(unsigned) * m->ni), 0 };
  g->vb = SDL_CreateGPUBuffer(g_gpu, &bv);
  g->ib = SDL_CreateGPUBuffer(g_gpu, &bi);
  bool ok = g->vb && g->ib && g3_upload(g->vb, NULL, 0, 0, vs, bv.size) && g3_upload(g->ib, NULL, 0, 0, m->idx, bi.size);
  SDL_free(vs);
  if (ok && m->jnt && m->wgt && !m->posed && G3.skin_pipe) {   // (skinnable: its binds and weights, for the GPU's skinning)
    G3SkinVertex *sv = SDL_malloc(sizeof(G3SkinVertex) * (size_t)m->nv);
    SDL_GPUBufferCreateInfo bs = { SDL_GPU_BUFFERUSAGE_VERTEX, (Uint32)(sizeof(G3SkinVertex) * m->nv), 0 };
    if (sv) {
      for (int i = 0; i < m->nv; i++) { SDL_memcpy(sv[i].j, &m->jnt[i * 4], 8); SDL_memcpy(sv[i].w, &m->wgt[i * 4], 16); }
      g->sb = SDL_CreateGPUBuffer(g_gpu, &bs);
      if (g->sb && !g3_upload(g->sb, NULL, 0, 0, sv, bs.size)) { SDL_ReleaseGPUBuffer(g_gpu, g->sb); g->sb = NULL; }
      SDL_free(sv);
    }
  }
  if (ok && m->ntex) {
    g->tex = SDL_calloc((size_t)m->ntex, sizeof *g->tex);
    g->ntex = m->ntex;
    for (int i = 0; g->tex && i < m->ntex; i++) if (m->tex[i].rgba) g->tex[i] = g3_texture(m->tex[i].w, m->tex[i].h, m->tex[i].rgba);
  }
  if (!ok) { g3_mesh_free(g); return NULL; }
  return g;
}
static SDL_GPUTexture *g3_file_texture(const char *file, const Tex3D *t) {   // (a node's texture = "...": by its file, its size)
  for (int i = 0; i < ng3texs; i++) if (!strcmp(g3texs[i].file, file) && g3texs[i].w == t->w && g3texs[i].h == t->h) return g3texs[i].t;
  if (ng3texs == (int)SDL_arraysize(g3texs)) { for (int i = 0; i < ng3texs; i++) if (g3texs[i].t) SDL_ReleaseGPUTexture(g_gpu, g3texs[i].t); ng3texs = 0; }
  G3Tex *e = &g3texs[ng3texs++];
  SDL_strlcpy(e->file, file, sizeof e->file);
  e->w = t->w; e->h = t->h;
  e->t = g3_texture(t->w, t->h, t->rgba);
  return e->t;
}

// a viewport's GPU targets, and what to draw this frame
// (the CPU path keeps its list here too: cpu_tex, its texture = "..." of a node)
typedef struct { const Mesh3D *m; float model[16]; float tint[4]; SDL_GPUTexture *over; Tex3D cpu_tex; bool has_cpu_tex, outline, wire, culled, noshadow; unsigned char part; float sway, fade, depth; const Mesh3D *shadow_m; } G3Item;   // shadow_m: drawn in its place in the sun's pass (a LOD simpler: /config lod.shadow)   // part: 1 a particle (alpha), 2 (added); depth: its distance (alpha ones: far first)   // culled: out of the camera's view (g3_cull)   // sway: the wind's strength on it; fade: whole up to that far (m), foliage's   // outline: selected (render.h outline3d_build)
typedef struct { SDL_GPUTexture *col, *dep, *shadow; SDL_Texture *wrap; int w, h, shadow_size; G3Item *items; int n, cap; int tris, draws, nvis, culled;
                 SDL_GPUBuffer *inst; SDL_GPUTransferBuffer *inst_tb; int inst_cap; int *order; int order_cap;
                 SDL_GPUBuffer *bones; SDL_GPUTransferBuffer *bones_tb; int bones_cap; } G3View;   // bones: every skinned copy's matrices this frame (bones_cap: matrices)   // inst: this frame's copies (one a item); draws: the last frame's draw calls
static void g3_view_free(G3View *v) {
  if (v->bones) SDL_ReleaseGPUBuffer(g_gpu, v->bones);
  if (v->bones_tb) SDL_ReleaseGPUTransferBuffer(g_gpu, v->bones_tb);
  if (v->inst) SDL_ReleaseGPUBuffer(g_gpu, v->inst);
  if (v->inst_tb) SDL_ReleaseGPUTransferBuffer(g_gpu, v->inst_tb);
  SDL_free(v->order);
  if (v->shadow) SDL_ReleaseGPUTexture(g_gpu, v->shadow);
  if (v->wrap) SDL_DestroyTexture(v->wrap);
  if (v->col) SDL_ReleaseGPUTexture(g_gpu, v->col);
  if (v->dep) SDL_ReleaseGPUTexture(g_gpu, v->dep);
  SDL_free(v->items);
  SDL_zerop(v);
}
static bool g3_view_size(G3View *v, SDL_Renderer *ren, int w, int h) {
  if (v->col && v->w == w && v->h == h) return true;
  G3Item *items = v->items; int cap = v->cap;
  SDL_GPUBuffer *inst = v->inst; SDL_GPUTransferBuffer *inst_tb = v->inst_tb; int inst_cap = v->inst_cap; int *order = v->order, order_cap = v->order_cap;
  v->items = NULL; v->inst = NULL; v->inst_tb = NULL; v->order = NULL;
  g3_view_free(v);
  v->items = items; v->cap = cap;                  // (its shadow map: made again when asked, g3_render)
  v->inst = inst; v->inst_tb = inst_tb; v->inst_cap = inst_cap; v->order = order; v->order_cap = order_cap;
  SDL_GPUTextureCreateInfo ti = { 0 };
  ti.type = SDL_GPU_TEXTURETYPE_2D; ti.width = (Uint32)w; ti.height = (Uint32)h; ti.layer_count_or_depth = 1; ti.num_levels = 1;
  ti.format = SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM; ti.usage = SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | SDL_GPU_TEXTUREUSAGE_SAMPLER;
  v->col = SDL_CreateGPUTexture(g_gpu, &ti);
  ti.format = G3.depth; ti.usage = SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET;
  v->dep = SDL_CreateGPUTexture(g_gpu, &ti);
  if (!v->col || !v->dep) return false;
  SDL_PropertiesID p = SDL_CreateProperties();     // (the 2D renderer draws it: the same device's texture, wrapped)
  SDL_SetNumberProperty(p, SDL_PROP_TEXTURE_CREATE_FORMAT_NUMBER, SDL_PIXELFORMAT_RGBA32);
  SDL_SetNumberProperty(p, SDL_PROP_TEXTURE_CREATE_ACCESS_NUMBER, SDL_TEXTUREACCESS_TARGET);
  SDL_SetNumberProperty(p, SDL_PROP_TEXTURE_CREATE_WIDTH_NUMBER, w);
  SDL_SetNumberProperty(p, SDL_PROP_TEXTURE_CREATE_HEIGHT_NUMBER, h);
  SDL_SetPointerProperty(p, SDL_PROP_TEXTURE_CREATE_GPU_TEXTURE_POINTER, v->col);
  v->wrap = SDL_CreateTextureWithProperties(ren, p);
  SDL_DestroyProperties(p);
  if (!v->wrap) { SDL_snprintf(G3.err, sizeof G3.err, "its picture: %s", SDL_GetError()); return false; }
  SDL_SetTextureBlendMode(v->wrap, SDL_BLENDMODE_BLEND);
  SDL_SetTextureScaleMode(v->wrap, SDL_SCALEMODE_NEAREST);
  v->w = w; v->h = h;
  return true;
}
// frustum culling: an item's bounding sphere (its mesh's box, through its matrix) against the camera's six planes
// (Gribb & Hartmann, from the view-projection; depth 0..1). A posed mesh: its base's box, the sphere 1.5x (a pose reaches out).
static void g3_planes(const float vp[16], float P[6][4]) {
  for (int k = 0; k < 4; k++) {
    float r0 = vp[k * 4], r1 = vp[k * 4 + 1], r2 = vp[k * 4 + 2], r3 = vp[k * 4 + 3];   // (column k: x, y, z, w rows' k-th)
    P[0][k] = r3 + r0; P[1][k] = r3 - r0; P[2][k] = r3 + r1; P[3][k] = r3 - r1; P[4][k] = r2; P[5][k] = r3 - r2;
  }
  for (int i = 0; i < 6; i++) {
    float l = sqrtf(P[i][0] * P[i][0] + P[i][1] * P[i][1] + P[i][2] * P[i][2]);
    if (l > 1e-12f) for (int k = 0; k < 4; k++) P[i][k] /= l;
  }
}
static bool g3_visible(const Mesh3D *m, const float M[16], float P[6][4]) {
  bool posed = m->gpu_mats || m->posed;            // (posed: its base's box, the sphere half again as big: a pose reaches out of it)
  if (m->gpu_mats && m->gpu_base) m = (const Mesh3D *)m->gpu_base;
  float c[3] = { (m->bmin[0] + m->bmax[0]) / 2, (m->bmin[1] + m->bmax[1]) / 2, (m->bmin[2] + m->bmax[2]) / 2 };
  float h[3] = { (m->bmax[0] - m->bmin[0]) / 2, (m->bmax[1] - m->bmin[1]) / 2, (m->bmax[2] - m->bmin[2]) / 2 };
  float w[3];
  for (int a = 0; a < 3; a++) w[a] = M[a] * c[0] + M[4 + a] * c[1] + M[8 + a] * c[2] + M[12 + a];
  float s = 0;                                     // (its biggest scale: the sphere grown by it)
  for (int k = 0; k < 3; k++) s = SDL_max(s, M[k * 4] * M[k * 4] + M[k * 4 + 1] * M[k * 4 + 1] + M[k * 4 + 2] * M[k * 4 + 2]);
  float r = sqrtf(h[0] * h[0] + h[1] * h[1] + h[2] * h[2]) * sqrtf(s) * (posed ? 1.5f : 1);
  for (int i = 0; i < 6; i++) if (P[i][0] * w[0] + P[i][1] * w[1] + P[i][2] * w[2] + P[i][3] < -r) return false;
  return true;
}
static void g3_cull(G3View *v, const float vp[16]) {   // -> it->culled, v->culled (how many)
  float P[6][4];
  g3_planes(vp, P);
  v->culled = 0;
  for (int i = 0; i < v->n; i++) { G3Item *it = &v->items[i]; it->culled = !g3_visible(it->m, it->model, P); v->culled += it->culled; }
}
static G3Item *g3_add(G3View *v, const Mesh3D *m, const float model[16], const float tint[4], SDL_GPUTexture *over) {
  if (v->n == v->cap) {
    int cap = v->cap ? v->cap * 2 : 64;
    G3Item *it = SDL_realloc(v->items, sizeof *it * (size_t)cap);
    if (!it) return NULL;
    v->items = it; v->cap = cap;
  }
  G3Item *it = &v->items[v->n++];
  SDL_zerop(it);
  it->m = m; SDL_memcpy(it->model, model, sizeof it->model); SDL_memcpy(it->tint, tint, sizeof it->tint); it->over = over;
  return it;
}
// the sun's view for the items (shadows): fitted to their bounds, or `area` m round `focus` when that's smaller
static void s3_sun_fit(const G3View *v, R3Light *L, const float focus[3], float area) {
  float lo[3] = { 1e30f, 1e30f, 1e30f }, hi[3] = { -1e30f, -1e30f, -1e30f };
  for (int i = 0; i < v->n; i++) {
    const G3Item *it = &v->items[i];
    if (it->m->lines) continue;                    // (the grid: not the scene's)
    for (int k = 0; k < 8; k++) {
      float p[3] = { (k & 1) ? it->m->bmax[0] : it->m->bmin[0], (k & 2) ? it->m->bmax[1] : it->m->bmin[1], (k & 4) ? it->m->bmax[2] : it->m->bmin[2] };
      const float *M = it->model;
      for (int a = 0; a < 3; a++) {
        float q = M[a] * p[0] + M[4 + a] * p[1] + M[8 + a] * p[2] + M[12 + a];
        if (q < lo[a]) lo[a] = q;
        if (q > hi[a]) hi[a] = q;
      }
    }
  }
  float c[3] = { 0, 0, 0 }, r = 1;
  if (v->n) {
    for (int a = 0; a < 3; a++) c[a] = (lo[a] + hi[a]) / 2;
    r = sqrtf((hi[0] - lo[0]) * (hi[0] - lo[0]) + (hi[1] - lo[1]) * (hi[1] - lo[1]) + (hi[2] - lo[2]) * (hi[2] - lo[2])) / 2;
  }
  if (area > 0 && area < r) { SDL_memcpy(c, focus, sizeof c); r = area; }
  r3_sun_fit(L, c, r);
}
// the items drawn by the CPU: the sun's depth first (shadows), then each one; the list emptied
static void r3_render(R3Target *T, G3View *v, const float vp[16], R3Light *L) {
  L->shadow = NULL;
  static float *map;                               // (one map for every CPU view: drawn one at a time)
  static int map_size;
  if (L->shadows && v->n) {
    int S = L->shadow_size;
    if (map_size != S) { SDL_free(map); map = SDL_malloc((size_t)S * S * sizeof(float)); map_size = map ? S : 0; }
    if (map) {
      for (size_t i = 0; i < (size_t)S * S; i++) map[i] = 1;
      for (int i = 0; i < v->n; i++) if (!v->items[i].m->lines && !v->items[i].noshadow) r3_shadow_draw(map, S, v->items[i].shadow_m ? v->items[i].shadow_m : v->items[i].m, v->items[i].model, L->lvp);
      L->shadow = map;
    }
  }
  float P[6][4];
  g3_planes(vp, P);
  v->culled = 0;
  for (int i = 0; i < v->n; i++) {
    G3Item *it = &v->items[i];
    if (it->m->lines || it->part) continue;        // (lines, particles: the GPU's only)
    if (!g3_visible(it->m, it->model, P)) { v->culled++; continue; }   // (out of view: its shadow was drawn above)
    r3_draw(T, it->m, it->model, vp, it->tint, L, it->has_cpu_tex ? &it->cpu_tex : NULL);
  }
  L->shadow = NULL;
  v->n = 0;
}
// an item's mesh on the GPU: the posed copy's base when the GPU skins it (pose3d_get: gpu_mats), else itself
static const Mesh3D *g3_src(const G3Item *it) { return it->m->gpu_mats && G3.skin_pipe ? (const Mesh3D *)it->m->gpu_base : it->m; }
static int SDLCALL g3_order_cmp(void *ud, const void *a, const void *b) {   // skinned last; the same mesh, the same texture over it: together (skinned too: each copy's pose its own, in the bones buffer)
  const G3View *v = ud;
  const G3Item *x = &v->items[*(const int *)a], *y = &v->items[*(const int *)b];
  if (x->culled != y->culled) return x->culled ? 1 : -1;   // (out of view: after all the rest, the sun's pass only)
  if (x->m->lines != y->m->lines) return x->m->lines ? 1 : -1;   // (lines last: blended over the rest)
  if (x->part != y->part) return x->part > y->part ? 1 : -1;   // (particles after the solid: the alpha ones, then the added)
  if (x->part == 1 && x->depth != y->depth) return x->depth > y->depth ? -1 : 1;   // (alpha ones: far first)
  bool sx = x->m->gpu_mats && G3.skin_pipe, sy = y->m->gpu_mats && G3.skin_pipe;
  if (sx != sy) return sx ? 1 : -1;
  const Mesh3D *mx = g3_src(x), *my = g3_src(y);
  if (mx != my) return mx < my ? -1 : 1;
  if (x->over != y->over) return (uintptr_t)x->over < (uintptr_t)y->over ? -1 : 1;
  if (x->shadow_m != y->shadow_m) return (uintptr_t)x->shadow_m < (uintptr_t)y->shadow_m ? -1 : 1;
  if (x->wire != y->wire) return x->wire ? 1 : -1;
  if (x->noshadow != y->noshadow) return x->noshadow ? 1 : -1;
  if (x->sway != y->sway) return x->sway < y->sway ? -1 : 1;
  if (x->fade != y->fade) return x->fade < y->fade ? -1 : 1;
  return *(const int *)a - *(const int *)b;
}
// the items in their order, each drawn copy's matrix and tint in the view's instance buffer (uploaded in cp)
static bool g3_instances(G3View *v, SDL_GPUCopyPass *cp) {
  int n = v->n;
  if (v->order_cap < n) {
    int *o = SDL_realloc(v->order, sizeof(int) * (size_t)n);
    if (!o) return false;
    v->order = o; v->order_cap = n;
  }
  for (int i = 0; i < n; i++) v->order[i] = i;
  SDL_qsort_r(v->order, (size_t)n, sizeof(int), g3_order_cmp, v);
  if (v->inst_cap < n) {                           // (grown to fit, a little more: not again next frame)
    int cap = n + n / 2 + 16;
    if (v->inst) SDL_ReleaseGPUBuffer(g_gpu, v->inst);
    if (v->inst_tb) SDL_ReleaseGPUTransferBuffer(g_gpu, v->inst_tb);
    SDL_GPUBufferCreateInfo bi = { SDL_GPU_BUFFERUSAGE_VERTEX, (Uint32)(sizeof(G3Instance) * cap), 0 };
    SDL_GPUTransferBufferCreateInfo ti = { SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, bi.size, 0 };
    v->inst = SDL_CreateGPUBuffer(g_gpu, &bi);
    v->inst_tb = SDL_CreateGPUTransferBuffer(g_gpu, &ti);
    v->inst_cap = v->inst && v->inst_tb ? cap : 0;
    if (!v->inst_cap) return false;
  }
  G3Instance *ins = SDL_MapGPUTransferBuffer(g_gpu, v->inst_tb, true);   // (cycled: last frame's may still be read)
  if (!ins) return false;
  static const float **seen; static int *seen_at, *seen_n, seen_cap;   // (a pose shared by copies: its matrices once)
  int nseen = 0, nb = 0;
  for (int k = 0; k < n; k++) {
    const G3Item *it = &v->items[v->order[k]];
    SDL_memcpy(ins[k].model, it->model, sizeof ins[k].model);
    SDL_memcpy(ins[k].tint, it->tint, sizeof ins[k].tint);
    ins[k].bone[0] = ins[k].bone[1] = ins[k].bone[2] = ins[k].bone[3] = 0;
    if (it->m->gpu_mats && G3.skin_pipe) {         // (skinned: where its matrices go in the frame's bones)
      const Mesh3D *b = g3_src(it);
      int at = -1;
      for (int q = nseen - 1; q >= 0 && q >= nseen - 64 && at < 0; q--) if (seen[q] == it->m->gpu_mats) at = seen_at[q];
      if (at < 0) {
        if (nseen == seen_cap) {
          int c = seen_cap ? seen_cap * 2 : 256;
          const float **s2 = SDL_realloc(seen, sizeof *seen * (size_t)c); if (s2) seen = s2;
          int *a2 = SDL_realloc(seen_at, sizeof *seen_at * (size_t)c); if (a2) seen_at = a2;
          int *n2 = SDL_realloc(seen_n, sizeof *seen_n * (size_t)c); if (n2) seen_n = n2;
          if (s2 && a2 && n2) seen_cap = c;
        }
        at = nb;
        nb += SDL_min(b->nbinds, G3_MAX_JOINTS);
        if (nseen < seen_cap) { seen[nseen] = it->m->gpu_mats; seen_at[nseen] = at; seen_n[nseen] = nb - at; nseen++; }
        else nb = at;                              // (no room to remember it: not drawn skinned right; never in practice)
      }
      ins[k].bone[0] = (float)at;
    }
  }
  SDL_UnmapGPUTransferBuffer(g_gpu, v->inst_tb);
  if (nb > 0) {                                    // the frame's bones: every pose's matrices, end to end
    if (v->bones_cap < nb) {
      int cap = nb + nb / 2 + 256;
      if (v->bones) SDL_ReleaseGPUBuffer(g_gpu, v->bones);
      if (v->bones_tb) SDL_ReleaseGPUTransferBuffer(g_gpu, v->bones_tb);
      SDL_GPUBufferCreateInfo bb = { SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ, (Uint32)(sizeof(float) * 16 * cap), 0 };
      SDL_GPUTransferBufferCreateInfo tb = { SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, bb.size, 0 };
      v->bones = SDL_CreateGPUBuffer(g_gpu, &bb);
      v->bones_tb = SDL_CreateGPUTransferBuffer(g_gpu, &tb);
      v->bones_cap = v->bones && v->bones_tb ? cap : 0;
      if (!v->bones_cap) return false;
    }
    float *bm = SDL_MapGPUTransferBuffer(g_gpu, v->bones_tb, true);
    if (!bm) return false;
    for (int q = 0; q < nseen; q++) SDL_memcpy(&bm[(size_t)seen_at[q] * 16], seen[q], sizeof(float) * 16 * (size_t)seen_n[q]);   // (each pose once, where it was given)
    SDL_UnmapGPUTransferBuffer(g_gpu, v->bones_tb);
    SDL_GPUTransferBufferLocation bsrc = { v->bones_tb, 0 };
    SDL_GPUBufferRegion bdst = { v->bones, 0, (Uint32)(sizeof(float) * 16 * nb) };
    SDL_UploadToGPUBuffer(cp, &bsrc, &bdst, true);
  }
  SDL_GPUTransferBufferLocation src = { v->inst_tb, 0 };
  SDL_GPUBufferRegion dst = { v->inst, 0, (Uint32)(sizeof(G3Instance) * n) };
  SDL_UploadToGPUBuffer(cp, &src, &dst, true);
  return true;
}
// the items into a pass: runs of the same mesh (and texture over it) are one instanced draw a part; meshes the
// GPU skins too: each copy's matrices in the frame's bones buffer (a storage buffer), where its instance says. main: colours (samplers, its fragment
// uniforms pushed already), else the sun's depth
static void g3_draw_items(G3View *v, SDL_GPUCommandBuffer *cb, SDL_GPURenderPass *rp, bool main, const float vp[16], const R3Light *L, bool shadows) {
  int n = main ? v->nvis : v->n;                   // (the camera's pass: what's in view; the sun's: everything)
  G3Uniforms u;
  SDL_zero(u);
  SDL_memcpy(u.vp, vp, sizeof u.vp);
  SDL_memcpy(u.light, L->lvp, sizeof u.light);
  SDL_memcpy(u.ambient, L->ambient, 12);
  SDL_memcpy(u.sun_dir, L->sun_dir, 12); u.sun_dir[3] = L->normal_offset;
  SDL_memcpy(u.sun_col, L->sun_col, 12);
  SDL_GPUGraphicsPipeline *bound = NULL;
  for (int k = 0; k < n;) {
    const G3Item *it = &v->items[v->order[k]];
    bool skinned = it->m->gpu_mats && G3.skin_pipe;
    const Mesh3D *m = g3_src(it);
    int j = k + 1;
    while (j < n && (v->items[v->order[j]].m->gpu_mats && G3.skin_pipe) == skinned && g3_src(&v->items[v->order[j]]) == m && v->items[v->order[j]].over == it->over &&
             v->items[v->order[j]].sway == it->sway && v->items[v->order[j]].fade == it->fade && v->items[v->order[j]].wire == it->wire && v->items[v->order[j]].noshadow == it->noshadow && v->items[v->order[j]].part == it->part && v->items[v->order[j]].shadow_m == it->shadow_m) j++;
    int count = j - k, first = k;
    k = j;
    G3Mesh *g = g3_mesh(m);
    if (!g || (skinned && !g->sb)) continue;
    SDL_GPUGraphicsPipeline *want = main ? (skinned ? G3.skin_pipe : G3.pipe) : (skinned ? G3.skin_shadow_pipe : G3.shadow_pipe);
    if (m->lines) want = main ? G3.line_pipe : NULL;   // (lines: no shadow)
    else if (it->part) want = main ? (it->part == 2 ? G3.add_pipe : G3.part_pipe) : NULL;   // (particles: blended, no shadow)
    else if (!main && it->noshadow) want = NULL;   // (billboards: no shadow, till shadows are alpha tested)
    else if (it->wire && !skinned) want = main ? G3.wire_pipe : NULL;   // (wireframe: its edges, no shadow; skinned: solid)
    if (!want) continue;
    if (want != bound) {
      SDL_BindGPUGraphicsPipeline(rp, want); bound = want;
      if ((want == G3.skin_pipe || want == G3.skin_shadow_pipe) && v->bones) SDL_BindGPUVertexStorageBuffers(rp, 0, &v->bones, 1);   // (the frame's bones: each copy's pose, where its instance says)
      if (want == G3.line_pipe || want == G3.part_pipe || want == G3.add_pipe) { G3FragUniforms lf = { { 0, (float)L->shadow_size, L->bias, want == G3.line_pipe ? 1.f : 2.f } }; SDL_PushGPUFragmentUniformData(cb, 0, &lf, sizeof lf); }
    }
    SDL_GPUBufferBinding vb[3] = { { g->vb, 0 }, { v->inst, (Uint32)(sizeof(G3Instance) * first) }, { g->sb, 0 } };
    SDL_BindGPUVertexBuffers(rp, 0, vb, skinned ? 3 : 2);
    SDL_GPUBufferBinding ib = { g->ib, 0 };
    SDL_BindGPUIndexBuffer(rp, &ib, SDL_GPU_INDEXELEMENTSIZE_32BIT);
    static const float WIND[2] = { 0.83f, 0.55f };  // (the wind's way, across the world: one for every foliage)
    u.wind[0] = WIND[0] * it->sway; u.wind[1] = WIND[1] * it->sway; u.wind[2] = g3_time; u.wind[3] = it->sway > 0 ? 1.f : 0.f;
    if (m->lines) { u.wind[0] = u.wind[1] = 0; u.wind[3] = -(m->line_fade > 0 ? m->line_fade : 1e9f); }   // (lines: unlit; the grid faded by distance)
    else if (it->part) { u.wind[0] = u.wind[1] = 0; u.wind[3] = -1e9f; }   // (particles: unlit, their own colours)
    SDL_memcpy(u.eye, g3_eye, sizeof g3_eye); u.eye[3] = it->fade;
    if (!main) {                                   // (the sun's depth: the whole mesh at once; a simpler one when it has it)
      if (it->shadow_m) {                          // (skinned too: a LOD shares its base's binds, so the copy's matrices pose it)
        G3Mesh *sg = g3_mesh(it->shadow_m);
        if (sg && (!skinned || sg->sb)) {
          SDL_GPUBufferBinding svb[3] = { { sg->vb, 0 }, { v->inst, (Uint32)(sizeof(G3Instance) * first) }, { sg->sb, 0 } };
          SDL_BindGPUVertexBuffers(rp, 0, svb, skinned ? 3 : 2);
          SDL_GPUBufferBinding sib = { sg->ib, 0 };
          SDL_BindGPUIndexBuffer(rp, &sib, SDL_GPU_INDEXELEMENTSIZE_32BIT);
          SDL_PushGPUVertexUniformData(cb, 0, &u, sizeof u);
          SDL_DrawGPUIndexedPrimitives(rp, (Uint32)it->shadow_m->ni, (Uint32)count, 0, 0, 0);
          continue;
        }
      }
      SDL_PushGPUVertexUniformData(cb, 0, &u, sizeof u);
      SDL_DrawGPUIndexedPrimitives(rp, (Uint32)m->ni, (Uint32)count, 0, 0, 0);
      continue;
    }
    for (int p = 0; p < m->nparts; p++) {
      const Part3D *pt = &m->parts[p];
      SDL_memcpy(u.base, pt->base, sizeof u.base);
      SDL_GPUTexture *tx = it->over ? it->over : (pt->tex >= 0 && pt->tex < g->ntex && g->tex[pt->tex]) ? g->tex[pt->tex] : G3.white;
      SDL_GPUTextureSamplerBinding sb[2] = { { tx, G3.samp }, { shadows ? v->shadow : G3.white, G3.shadow_samp ? G3.shadow_samp : G3.samp } };
      SDL_BindGPUFragmentSamplers(rp, 0, sb, 2);
      SDL_PushGPUVertexUniformData(cb, 0, &u, sizeof u);
      SDL_DrawGPUIndexedPrimitives(rp, (Uint32)pt->count, (Uint32)count, (Uint32)pt->first, 0, 0);
      if (!m->lines) v->tris += pt->count / 3 * count;
      v->draws++;
    }
  }
}
// the frame's items drawn into the viewport's colour (and depth): its own command buffer, submitted
// now; the 2D renderer's (later, at present) samples the picture
static bool g3_render(G3View *v, const unsigned char clear[4], const float vp[16], const R3Light *L) {
  SDL_GPUCommandBuffer *cb = SDL_AcquireGPUCommandBuffer(g_gpu);
  if (!cb) return false;
  g3_cull(v, vp);
  v->nvis = v->n - v->culled;
  for (int i = 0; i < v->n; i++) { g3_mesh(g3_src(&v->items[i])); if (v->items[i].shadow_m) g3_mesh(v->items[i].shadow_m); }   // (uploads first: their own copy passes, before this buffer's)
  SDL_GPUCopyPass *cp = SDL_BeginGPUCopyPass(cb);
  bool ok = cp && g3_instances(v, cp);
  if (cp) SDL_EndGPUCopyPass(cp);
  if (!ok) { SDL_CancelGPUCommandBuffer(cb); v->n = 0; return false; }
  bool shadows = L->shadows && G3.shadow_pipe && v->n;
  if (shadows && (!v->shadow || v->shadow_size != L->shadow_size)) {
    if (v->shadow) SDL_ReleaseGPUTexture(g_gpu, v->shadow);
    SDL_GPUTextureCreateInfo ti = { 0 };
    ti.type = SDL_GPU_TEXTURETYPE_2D; ti.width = ti.height = (Uint32)L->shadow_size; ti.layer_count_or_depth = 1; ti.num_levels = 1;
    ti.format = G3.depth; ti.usage = SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET | SDL_GPU_TEXTUREUSAGE_SAMPLER;
    v->shadow = SDL_CreateGPUTexture(g_gpu, &ti);
    v->shadow_size = v->shadow ? L->shadow_size : 0;
  }
  shadows = shadows && v->shadow;
  if (shadows) {                                   // the sun's depth: every item, both faces
    SDL_GPUDepthStencilTargetInfo si = { 0 };
    si.texture = v->shadow; si.clear_depth = 1; si.load_op = SDL_GPU_LOADOP_CLEAR; si.store_op = SDL_GPU_STOREOP_STORE;
    si.stencil_load_op = SDL_GPU_LOADOP_DONT_CARE; si.stencil_store_op = SDL_GPU_STOREOP_DONT_CARE;
    SDL_GPURenderPass *sp = SDL_BeginGPURenderPass(cb, NULL, 0, &si);
    if (sp) {
      g3_draw_items(v, cb, sp, false, L->lvp, L, false);
      SDL_EndGPURenderPass(sp);
    } else shadows = false;
  }
  SDL_GPUColorTargetInfo ci = { 0 };
  ci.texture = v->col; ci.load_op = SDL_GPU_LOADOP_CLEAR; ci.store_op = SDL_GPU_STOREOP_STORE;
  ci.clear_color = (SDL_FColor){ clear[0] / 255.f, clear[1] / 255.f, clear[2] / 255.f, clear[3] / 255.f };
  SDL_GPUDepthStencilTargetInfo di = { 0 };
  di.texture = v->dep; di.clear_depth = 1; di.load_op = SDL_GPU_LOADOP_CLEAR; di.store_op = SDL_GPU_STOREOP_DONT_CARE;
  di.stencil_load_op = SDL_GPU_LOADOP_DONT_CARE; di.stencil_store_op = SDL_GPU_STOREOP_DONT_CARE;
  SDL_GPURenderPass *rp = SDL_BeginGPURenderPass(cb, &ci, 1, &di);
  if (!rp) { SDL_CancelGPUCommandBuffer(cb); return false; }
  G3FragUniforms fu = { { shadows ? 1.f : 0.f, (float)L->shadow_size, L->bias, 0 } };
  SDL_PushGPUFragmentUniformData(cb, 0, &fu, sizeof fu);
  v->tris = 0; v->draws = 0;
  g3_draw_items(v, cb, rp, true, vp, L, shadows);
  SDL_EndGPURenderPass(rp);
  v->n = 0;
  return SDL_SubmitGPUCommandBuffer(cb);
}
// the viewport's picture back into memory (tests: host_camera3d): waits for the GPU
static bool g3_read(G3View *v, unsigned char *rgba) {
  Uint32 size = (Uint32)(v->w * v->h * 4);
  SDL_GPUTransferBufferCreateInfo ti = { SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD, size, 0 };
  SDL_GPUTransferBuffer *tb = SDL_CreateGPUTransferBuffer(g_gpu, &ti);
  if (!tb) return false;
  SDL_GPUCommandBuffer *cb = SDL_AcquireGPUCommandBuffer(g_gpu);
  SDL_GPUCopyPass *cp = cb ? SDL_BeginGPUCopyPass(cb) : NULL;
  bool ok = false;
  if (cp) {
    SDL_GPUTextureRegion src = { 0 };
    src.texture = v->col; src.w = (Uint32)v->w; src.h = (Uint32)v->h; src.d = 1;
    SDL_GPUTextureTransferInfo dst = { tb, 0, (Uint32)v->w, (Uint32)v->h };
    SDL_DownloadFromGPUTexture(cp, &src, &dst);
    SDL_EndGPUCopyPass(cp);
    SDL_GPUFence *f = SDL_SubmitGPUCommandBufferAndAcquireFence(cb);
    if (f) {
      SDL_WaitForGPUFences(g_gpu, true, &f, 1);
      SDL_ReleaseGPUFence(g_gpu, f);
      void *p = SDL_MapGPUTransferBuffer(g_gpu, tb, false);
      if (p) { SDL_memcpy(rgba, p, size); SDL_UnmapGPUTransferBuffer(g_gpu, tb); ok = true; }
    }
  } else if (cb) SDL_CancelGPUCommandBuffer(cb);
  SDL_ReleaseGPUTransferBuffer(g_gpu, tb);
  return ok;
}

// everything of ours on the device, before it goes (gpu_shutdown); the viewports' (render.h) first
static void (*g3_release_views)(void);
static void g3_release(void) {
  if (g3_release_views) g3_release_views();
  for (int i = 0; i < ng3meshes; i++) g3_mesh_free(&g3meshes[i]);
  ng3meshes = 0;
  for (int i = 0; i < ng3texs; i++) if (g3texs[i].t) SDL_ReleaseGPUTexture(g_gpu, g3texs[i].t);
  ng3texs = 0;
  if (G3.white) SDL_ReleaseGPUTexture(g_gpu, G3.white);
  if (G3.samp) SDL_ReleaseGPUSampler(g_gpu, G3.samp);
  if (G3.shadow_samp) SDL_ReleaseGPUSampler(g_gpu, G3.shadow_samp);
  if (G3.pipe) SDL_ReleaseGPUGraphicsPipeline(g_gpu, G3.pipe);
  if (G3.skin_pipe) SDL_ReleaseGPUGraphicsPipeline(g_gpu, G3.skin_pipe);
  if (G3.line_pipe) SDL_ReleaseGPUGraphicsPipeline(g_gpu, G3.line_pipe);
  if (G3.wire_pipe) SDL_ReleaseGPUGraphicsPipeline(g_gpu, G3.wire_pipe);
  if (G3.part_pipe) SDL_ReleaseGPUGraphicsPipeline(g_gpu, G3.part_pipe);
  if (G3.add_pipe) SDL_ReleaseGPUGraphicsPipeline(g_gpu, G3.add_pipe);
  if (G3.soft) SDL_ReleaseGPUTexture(g_gpu, G3.soft);
  if (G3.skin_shadow_pipe) SDL_ReleaseGPUGraphicsPipeline(g_gpu, G3.skin_shadow_pipe);
  if (G3.shadow_pipe) SDL_ReleaseGPUGraphicsPipeline(g_gpu, G3.shadow_pipe);
  SDL_zero(G3);
}
