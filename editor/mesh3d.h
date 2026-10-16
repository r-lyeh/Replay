// mesh3d.h - 3D models in memory (docs/3D.md: Mesh3D): what every importer
// gives, what the CPU rasterizer (raster3d.h) and the GPU path draw. Part of
// replay.c: included once, after render.h's texture helpers.
//
// A Mesh3D is triangles in model space (meters, y up, right-handed): per
// vertex a position, a normal, a uv and a colour; per part (a material) a
// range of indices, a base colour and a texture. The node hierarchy is baked
// into the vertices at load, but a skinned one's (phase 5): its vertices stay in
// bind space, with up to 4 joints and weights each; its skeleton (joints: parent,
// rest pose, inverse bind matrix) and its clips (keys per joint: translation,
// rotation, scale; step or linear, cubic read as linear) come along. One skin a file.
// Blend shapes (FBX): offsets a vertex, weighted by the clips (path 3) or the game.
//   mesh3d_pose(m, clip, t, loop, mats) -> the skin's matrices at t (clip: 0-based)
//   mesh3d_skin(m, mats, pos, nrm)     -> its vertices posed
//   mesh3d_get(V, name) -> the mesh (cached; read again when its file changes) | NULL
//     name: "cube", "plane", "sphere", "cylinder", "cone", "capsule", "triangle", "line" (1 m, centred), "grass" (a tuft
//     of blades: foliage), "tree", "pine", "bush" (plants by rules; "tree:3": another of its kind) (built in), or a file of assets/:
//     .gltf / .glb (cgltf), .fbx (ufbx), .vox (MagicaVoxel: our reader, a quad a
//     visible voxel face). Its textures: embedded, or files beside it.
//     Its clips: the file's, and sub-clips from "<file>@animlist.txt" or "animlist.txt"
//     beside it ("frame: 0-60 Idle (Loop)" a line: frames of its first clip).
#pragma once
#define CGLTF_IMPLEMENTATION
#include "3rd/models/cgltf.h"
#include "3rd/models/ufbx.h"
#include "3rd/models/ufbx.c"                       // (MIT / public domain: one unit with replay.c, as the rest)


typedef struct { int w, h; unsigned char *rgba; } Tex3D;
typedef struct { int first, count; float base[4]; int tex; } Part3D;   // tex: index in tex[] (-1: none)
typedef struct { int parent; float t[3], r[4], s[3]; bool has_matrix; float matrix[16], base[16]; char name[64]; } Joint3D;   // base: a root joint's ancestors (not joints) in the world
typedef struct { int joint, path, n; float *times, *vals; bool step; } Chan3D;   // path: 0 translation, 1 rotation (x, y, z, w), 2 scale; 3: a morph's weight (joint: the morph)
typedef struct { char name[64]; int first, count; float *dpos, *dnrm, def; } Morph3D;   // def: its weight with no clip (glTF's mesh weights; FBX: 0)   // a blend shape: offsets of vertices first.. (dnrm: NULL when the file has none)
typedef struct { char name[64]; float duration; int nchan; Chan3D *chan; int src; float start; bool loops; } Clip3D;   // src >= 0: a sub-clip, start s into that clip's keys (chan: none of its own); loops: "(Loop)" in its name
typedef struct {
  char file[1024];
  float *pos, *nrm, *uv;                           // 3, 3, 2 floats a vertex
  unsigned char *col;                              // 4 a vertex
  unsigned *idx;
  int nv, ni, nparts, ntex;
  Part3D *parts;
  Tex3D *tex;
  float bmin[3], bmax[3];
  unsigned short *jnt; float *wgt;                 // skinned: 4 binds, 4 weights a vertex (NULL: not skinned)
  int njoints, nclips, nbinds;
  Joint3D *joints;                                 // the skeleton (glTF: its skin's joints; FBX: the bones and their ancestors)
  int *bind_joint; float *ibm;                     // a bind: its joint and inverse bind matrix (16 floats; vertex space -> the joint's)
  int nmorphs; Morph3D *morphs;                    // blend shapes (face expressions...): weighted offsets before the skin
  Clip3D *clips;
  bool posed;                                      // (a posed copy: pose3d_get's, its arrays not its own but pos, nrm)
  const float *gpu_mats; const void *gpu_base;     // (a posed copy the GPU skins: the skin's matrices, the base mesh; pos / nrm: the
  void *pose; bool cpu_pending;                    //  base's, unskinned, till something on the CPU wants them: pose3d_cpu)
  SDL_Time mtime; Uint64 checked;
  bool ok;
  bool lines;                                      // (idx: pairs, a line each: "grid", "gridaxis", "line", dd's 3D lines; the GPU's line pipeline, unlit, no shadow, not on the CPU)
  float line_fade;                                 // (lines: gone by that far from the camera, m; 0: never)
  bool shares;                                     // (a LOD (mesh3d_lod): its textures, skeleton, clips are its base's: not freed with it)
  unsigned version;                                // (read again: +1; the GPU's copy follows it)
  char err[160];
} Mesh3D;

static void mesh3d_free(Mesh3D *m) {
  m->version++;
  SDL_free(m->pos); SDL_free(m->nrm); SDL_free(m->uv); SDL_free(m->col); SDL_free(m->idx); SDL_free(m->parts);
  if (m->shares) {                                 // (a LOD of another: its textures, skeleton and clips are that one's)
    SDL_free(m->jnt); SDL_free(m->wgt);
    m->pos = m->nrm = m->uv = NULL; m->col = NULL; m->idx = NULL; m->parts = NULL; m->tex = NULL; m->jnt = NULL; m->wgt = NULL;
    m->joints = NULL; m->ibm = NULL; m->bind_joint = NULL; m->clips = NULL; m->morphs = NULL; m->nmorphs = 0;
    m->nv = m->ni = m->nparts = m->ntex = m->njoints = m->nclips = m->nbinds = 0; m->ok = false; m->shares = false;
    return;
  }
  for (int i = 0; i < m->ntex; i++) SDL_free(m->tex[i].rgba);
  SDL_free(m->tex);
  SDL_free(m->jnt); SDL_free(m->wgt); SDL_free(m->joints); SDL_free(m->ibm); SDL_free(m->bind_joint);
  for (int c = 0; c < m->nclips; c++) {
    for (int k = 0; k < m->clips[c].nchan; k++) { SDL_free(m->clips[c].chan[k].times); SDL_free(m->clips[c].chan[k].vals); }
    SDL_free(m->clips[c].chan);
  }
  SDL_free(m->clips);
  for (int k = 0; k < m->nmorphs; k++) { SDL_free(m->morphs[k].dpos); SDL_free(m->morphs[k].dnrm); }
  SDL_free(m->morphs); m->morphs = NULL; m->nmorphs = 0;
  m->pos = m->nrm = m->uv = NULL; m->col = NULL; m->idx = NULL; m->parts = NULL; m->tex = NULL;
  m->jnt = NULL; m->wgt = NULL; m->joints = NULL; m->ibm = NULL; m->bind_joint = NULL; m->clips = NULL;
  m->nv = m->ni = m->nparts = m->ntex = m->njoints = m->nclips = m->nbinds = 0; m->ok = false;
}
static bool mesh3d_alloc(Mesh3D *m, int nv, int ni) {
  m->pos = SDL_calloc((size_t)nv * 3, sizeof(float)); m->nrm = SDL_calloc((size_t)nv * 3, sizeof(float));
  m->uv = SDL_calloc((size_t)nv * 2, sizeof(float)); m->col = SDL_malloc((size_t)nv * 4);
  m->idx = SDL_malloc((size_t)ni * sizeof(unsigned));
  if (!m->pos || !m->nrm || !m->uv || !m->col || !m->idx) return false;
  SDL_memset(m->col, 255, (size_t)nv * 4);
  m->nv = nv; m->ni = ni;
  return true;
}
static void mesh3d_bounds(Mesh3D *m) {
  for (int k = 0; k < 3; k++) { m->bmin[k] = 1e30f; m->bmax[k] = -1e30f; }
  for (int i = 0; i < m->nv; i++) for (int k = 0; k < 3; k++) {
    float v = m->pos[i * 3 + k];
    if (v < m->bmin[k]) m->bmin[k] = v;
    if (v > m->bmax[k]) m->bmax[k] = v;
  }
  if (m->nv == 0) for (int k = 0; k < 3; k++) m->bmin[k] = m->bmax[k] = 0;
}
static void mesh3d_one_part(Mesh3D *m) {
  m->parts = SDL_calloc(1, sizeof *m->parts);
  m->parts[0] = (Part3D){ 0, m->ni, { 1, 1, 1, 1 }, -1 };
  m->nparts = 1;
}

// the built-in shapes: a cube (1 m, centred), a plane (1 x 1 m on xz, facing +y), a sphere (1 m across)
static void mesh3d_cube(Mesh3D *m) {
  static const float F[6][4][3] = {               // each face: four corners, counter-clockwise from outside
    { { .5f, -.5f, .5f }, { .5f, -.5f, -.5f }, { .5f, .5f, -.5f }, { .5f, .5f, .5f } },      // +x
    { { -.5f, -.5f, -.5f }, { -.5f, -.5f, .5f }, { -.5f, .5f, .5f }, { -.5f, .5f, -.5f } },  // -x
    { { -.5f, .5f, .5f }, { .5f, .5f, .5f }, { .5f, .5f, -.5f }, { -.5f, .5f, -.5f } },      // +y
    { { -.5f, -.5f, -.5f }, { .5f, -.5f, -.5f }, { .5f, -.5f, .5f }, { -.5f, -.5f, .5f } },  // -y
    { { -.5f, -.5f, .5f }, { .5f, -.5f, .5f }, { .5f, .5f, .5f }, { -.5f, .5f, .5f } },      // +z
    { { .5f, -.5f, -.5f }, { -.5f, -.5f, -.5f }, { -.5f, .5f, -.5f }, { .5f, .5f, -.5f } },  // -z
  };
  static const float N[6][3] = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } };
  static const float UV[4][2] = { { 0, 1 }, { 1, 1 }, { 1, 0 }, { 0, 0 } };
  if (!mesh3d_alloc(m, 24, 36)) return;
  for (int f = 0; f < 6; f++) {
    for (int k = 0; k < 4; k++) {
      int v = f * 4 + k;
      SDL_memcpy(&m->pos[v * 3], F[f][k], sizeof(float) * 3);
      SDL_memcpy(&m->nrm[v * 3], N[f], sizeof(float) * 3);
      m->uv[v * 2] = UV[k][0]; m->uv[v * 2 + 1] = UV[k][1];
    }
    unsigned b = (unsigned)f * 4, *ix = &m->idx[f * 6];
    ix[0] = b; ix[1] = b + 1; ix[2] = b + 2; ix[3] = b; ix[4] = b + 2; ix[5] = b + 3;
  }
  mesh3d_one_part(m);
}
static void mesh3d_plane(Mesh3D *m) {
  if (!mesh3d_alloc(m, 4, 6)) return;
  static const float P[4][3] = { { -.5f, 0, .5f }, { .5f, 0, .5f }, { .5f, 0, -.5f }, { -.5f, 0, -.5f } };
  static const float UV[4][2] = { { 0, 1 }, { 1, 1 }, { 1, 0 }, { 0, 0 } };
  for (int v = 0; v < 4; v++) {
    SDL_memcpy(&m->pos[v * 3], P[v], sizeof(float) * 3);
    m->nrm[v * 3 + 1] = 1;
    m->uv[v * 2] = UV[v][0]; m->uv[v * 2 + 1] = UV[v][1];
  }
  static const unsigned I[6] = { 0, 1, 2, 0, 2, 3 };
  SDL_memcpy(m->idx, I, sizeof I);
  mesh3d_one_part(m);
}
static void mesh3d_sphere(Mesh3D *m) {
  enum { SEG = 24, RING = 12 };
  if (!mesh3d_alloc(m, (SEG + 1) * (RING + 1), SEG * RING * 6)) return;
  int v = 0, k = 0;
  for (int r = 0; r <= RING; r++) for (int s = 0; s <= SEG; s++, v++) {
    float th = (float)r / RING * 3.14159265f, ph = (float)s / SEG * 6.2831853f;
    float x = sinf(th) * cosf(ph), y = cosf(th), z = -sinf(th) * sinf(ph);
    m->pos[v * 3] = x * .5f; m->pos[v * 3 + 1] = y * .5f; m->pos[v * 3 + 2] = z * .5f;
    m->nrm[v * 3] = x; m->nrm[v * 3 + 1] = y; m->nrm[v * 3 + 2] = z;
    m->uv[v * 2] = (float)s / SEG; m->uv[v * 2 + 1] = (float)r / RING;
  }
  for (int r = 0; r < RING; r++) for (int s = 0; s < SEG; s++) {
    unsigned a = (unsigned)(r * (SEG + 1) + s), b = a + SEG + 1;
    m->idx[k++] = a; m->idx[k++] = b; m->idx[k++] = a + 1;
    m->idx[k++] = a + 1; m->idx[k++] = b; m->idx[k++] = b + 1;
  }
  mesh3d_one_part(m);
}

// "grass": a tuft of blades (after Outerra's procedural grass: thin blades, bending outward, darker at the
// root, lighter and yellower at the tip), 1 m tall and about 1 m across, standing on y = 0 (a foliage
// layer scales it). Each blade both ways round (both its faces drawn: they're seen from anywhere); its
// normals lean up, so the tuft is lit softly, as a whole. The wind bends it by height (mesh.vert).
static void mesh3d_grass(Mesh3D *m, unsigned variant) {   // (variant: "grass:2"... another tuft; 1: the first)
  enum { BLADES = 9, SEGS = 4 };
  int vb = (SEGS + 1) * 2, nv = BLADES * vb * 2, ni = BLADES * SEGS * 6 * 2;
  if (!mesh3d_alloc(m, nv, ni)) return;
  int v = 0, k = 0;
  unsigned seed = 12345 + (variant > 1 ? variant * 7919u : 0);
  for (int b = 0; b < BLADES; b++) {
    float r[4];
    for (int q = 0; q < 4; q++) { seed = seed * 1103515245u + 12345u; r[q] = (float)((seed >> 8) & 0xffff) / 65535.f; }
    float ang = (b + r[0] * 0.8f) / BLADES * 6.2831853f, cx = cosf(ang), cz = sinf(ang);
    float root = 0.12f * r[1], lean = 0.25f + 0.35f * r[2], hgt = 0.65f + 0.35f * r[3], wid = 0.035f + 0.02f * r[2];
    float px = -cz, pz = cx;                       // (across the blade)
    for (int side = 0; side < 2; side++) {
      int first = v;
      for (int sg = 0; sg <= SEGS; sg++) {
        float t = (float)sg / SEGS, y = hgt * t, out = root + lean * t * t;   // (bending outward, more near the tip)
        float w = wid * (1 - t) + 0.002f;
        for (int e = 0; e < 2; e++, v++) {
          float o = e ? w : -w;
          m->pos[v * 3] = cx * out + px * o; m->pos[v * 3 + 1] = y; m->pos[v * 3 + 2] = cz * out + pz * o;
          float n[3] = { cx * 0.45f * (side ? -1 : 1), 1, cz * 0.45f * (side ? -1 : 1) }, l = sqrtf(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
          for (int q = 0; q < 3; q++) m->nrm[v * 3 + q] = n[q] / l;
          m->uv[v * 2] = (float)e; m->uv[v * 2 + 1] = 1 - t;
          float shade = 0.5f + 0.5f * t;           // (darker at the root, lighter and a little yellow at the tip)
          m->col[v * 4] = (unsigned char)(255 * SDL_min(1.f, shade * (1 + 0.15f * t)));
          m->col[v * 4 + 1] = (unsigned char)(255 * shade);
          m->col[v * 4 + 2] = (unsigned char)(255 * shade * (1 - 0.35f * t));
          m->col[v * 4 + 3] = 255;
        }
      }
      for (int sg = 0; sg < SEGS; sg++) {
        unsigned a0 = (unsigned)(first + sg * 2), a1 = a0 + 1, b0 = a0 + 2, b1 = a0 + 3;
        if (!side) { m->idx[k++] = a0; m->idx[k++] = a1; m->idx[k++] = b0; m->idx[k++] = b0; m->idx[k++] = a1; m->idx[k++] = b1; }
        else { m->idx[k++] = a0; m->idx[k++] = b0; m->idx[k++] = a1; m->idx[k++] = b0; m->idx[k++] = b1; m->idx[k++] = a1; }
      }
    }
  }
  mesh3d_one_part(m);
}

// Plants made by rules (foliage's trees): "tree" (a broadleaf: a trunk forking into branches, leaf clusters at
// their ends), "pine" (a straight trunk, whorls of drooping branches, shorter towards the top: a cone),
// "bush" (stems from the ground, leaves all over). "tree:3": another of the kind (its own seed). Each fits a
// 1 m box standing on y = 0 (x, z: -0.5..0.5), so a foliage layer's size is its crown's width, its height.
// Leaves are small cards drawn both ways round, their normals pointing out of the crown (lit as a volume),
// darker inside (as if shaded by the others). Bark and leaves have their colours: a layer's colour tints them.
typedef struct { float *p, *n; unsigned char *c; unsigned *ix; int nv, ni, cv, ci; unsigned seed; bool bad; } MeshB;
static float mb_rand(MeshB *b) { b->seed = b->seed * 1103515245u + 12345u; return (float)((b->seed >> 8) & 0xffff) / 65535.f; }
static float mb_len(const float v[3]) { return sqrtf(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]); }
static void mb_unit(float v[3]) { float l = mb_len(v); if (l > 1e-9f) { v[0] /= l; v[1] /= l; v[2] /= l; } }
static void mb_cross(const float a[3], const float b[3], float o[3]) { o[0] = a[1] * b[2] - a[2] * b[1]; o[1] = a[2] * b[0] - a[0] * b[2]; o[2] = a[0] * b[1] - a[1] * b[0]; }
static void mb_basis(const float d[3], float e1[3], float e2[3]) {   // (two directions across d: (e1, e2, d) right-handed)
  float h[3] = { 0, 1, 0 };
  if (fabsf(d[1]) > 0.9f) { h[0] = 1; h[1] = 0; }
  mb_cross(d, h, e1); mb_unit(e1); mb_cross(d, e1, e2);
}
static int mb_vert(MeshB *b, const float p[3], const float n[3], float r, float g, float bl) {
  if (b->bad) return 0;
  if (b->nv == b->cv) {
    int c = b->cv ? b->cv * 2 : 1024;
    float *P = SDL_realloc(b->p, sizeof(float) * 3 * (size_t)c);
    if (P) b->p = P;
    float *N = P ? SDL_realloc(b->n, sizeof(float) * 3 * (size_t)c) : NULL;
    if (N) b->n = N;
    unsigned char *C = N ? SDL_realloc(b->c, 4 * (size_t)c) : NULL;
    if (C) b->c = C;
    if (!C) { b->bad = true; return 0; }
    b->cv = c;
  }
  int v = b->nv++;
  SDL_memcpy(&b->p[v * 3], p, sizeof(float) * 3);
  float nn[3] = { n[0], n[1], n[2] };
  mb_unit(nn);
  SDL_memcpy(&b->n[v * 3], nn, sizeof nn);
  b->c[v * 4] = (unsigned char)(255 * SDL_clamp(r, 0.f, 1.f)); b->c[v * 4 + 1] = (unsigned char)(255 * SDL_clamp(g, 0.f, 1.f));
  b->c[v * 4 + 2] = (unsigned char)(255 * SDL_clamp(bl, 0.f, 1.f)); b->c[v * 4 + 3] = 255;
  return v;
}
static void mb_tri(MeshB *b, int a, int c, int d) {
  if (b->bad) return;
  if (b->ni + 3 > b->ci) {
    int cap = b->ci ? b->ci * 2 : 3072;
    unsigned *I = SDL_realloc(b->ix, sizeof(unsigned) * (size_t)cap);
    if (!I) { b->bad = true; return; }
    b->ix = I; b->ci = cap;
  }
  b->ix[b->ni++] = (unsigned)a; b->ix[b->ni++] = (unsigned)c; b->ix[b->ni++] = (unsigned)d;
}
static void mb_tube(MeshB *b, const float a[3], const float e[3], float ra, float re, const float col[3]) {   // (a branch: 5 sides, tapering)
  enum { SIDES = 5 };
  float d[3] = { e[0] - a[0], e[1] - a[1], e[2] - a[2] }, e1[3], e2[3];
  mb_unit(d); mb_basis(d, e1, e2);
  int first = b->nv;
  for (int end = 0; end < 2; end++) for (int s = 0; s < SIDES; s++) {
    float t = s * 6.2831853f / SIDES, n[3], p[3];
    const float *o = end ? e : a;
    float r = end ? re : ra, k = end ? 1.f : 0.8f;   // (a little darker at its foot)
    for (int q = 0; q < 3; q++) { n[q] = cosf(t) * e1[q] + sinf(t) * e2[q]; p[q] = o[q] + n[q] * r; }
    mb_vert(b, p, n, col[0] * k, col[1] * k, col[2] * k);
  }
  for (int s = 0; s < SIDES; s++) {
    int a0 = first + s, a1 = first + (s + 1) % SIDES, b0 = a0 + SIDES, b1 = a1 + SIDES;
    mb_tri(b, a0, a1, b0); mb_tri(b, a1, b1, b0);
  }
}
// a leaf card: centre c, its long way u, across w (half sizes in them); both faces; lit by `nrm`; its colour
static void mb_card(MeshB *b, const float c[3], const float u[3], const float w[3], const float nrm[3], const float col[3]) {
  float p[4][3];
  for (int q = 0; q < 3; q++) { p[0][q] = c[q] - u[q]; p[1][q] = c[q] + w[q]; p[2][q] = c[q] + u[q]; p[3][q] = c[q] - w[q]; }
  int v[8];
  for (int side = 0; side < 2; side++) for (int k = 0; k < 4; k++) {
    float t = k == 2 ? 1.12f : 1.f;                // (its tip a little lighter)
    v[side * 4 + k] = mb_vert(b, p[k], nrm, col[0] * t, col[1] * t, col[2] * t);
  }
  mb_tri(b, v[0], v[1], v[2]); mb_tri(b, v[0], v[2], v[3]);
  mb_tri(b, v[4], v[6], v[5]); mb_tri(b, v[4], v[7], v[6]);
}
static void mb_leaves(MeshB *b, const float at[3], float rad, int count, float size, const float col[3]) {   // (a cluster)
  for (int i = 0; i < count; i++) {
    float d[3] = { mb_rand(b) * 2 - 1, mb_rand(b) * 2 - 1, mb_rand(b) * 2 - 1 };
    if (mb_len(d) > 1) { i--; if (b->bad) return; continue; }
    float c[3] = { at[0] + d[0] * rad, at[1] + d[1] * rad * 0.9f, at[2] + d[2] * rad };
    float r = mb_len(d), nrm[3] = { d[0], d[1] + 0.6f, d[2] }, n0[3] = { mb_rand(b) - 0.5f, mb_rand(b) - 0.5f, mb_rand(b) - 0.5f }, u[3], w[3];
    mb_unit(n0); mb_basis(n0, u, w);
    float s = size * (0.75f + 0.5f * mb_rand(b));
    for (int q = 0; q < 3; q++) { u[q] *= s; w[q] *= s * 0.55f; }
    float shade = 0.6f + 0.4f * r + (mb_rand(b) - 0.5f) * 0.15f;   // (inside: darker)
    float lc[3] = { col[0] * shade, col[1] * shade, col[2] * shade };
    mb_card(b, c, u, w, nrm, lc);
  }
}
static void mb_turn(const float d[3], float spread, float az, float up, float o[3]) {   // (d, turned off itself by spread, round it by az)
  float e1[3], e2[3];
  mb_basis(d, e1, e2);
  for (int q = 0; q < 3; q++) o[q] = d[q] * cosf(spread) + (e1[q] * cosf(az) + e2[q] * sinf(az)) * sinf(spread);
  o[1] += up;
  mb_unit(o);
}
static const float BARK[3] = { 0.42f, 0.31f, 0.22f }, LEAF[3] = { 0.36f, 0.62f, 0.25f }, NEEDLE[3] = { 0.17f, 0.36f, 0.2f }, SHRUB[3] = { 0.3f, 0.55f, 0.24f };
static void mb_branch(MeshB *b, const float at[3], const float d[3], float len, float rad, int depth) {
  float e[3] = { at[0] + d[0] * len, at[1] + d[1] * len, at[2] + d[2] * len };
  mb_tube(b, at, e, rad, rad * 0.72f, BARK);
  if (depth == 0) { mb_leaves(b, e, len * 1.7f, 16, len * 0.45f, LEAF); return; }
  if (depth <= 2) mb_leaves(b, e, len * 1.1f, 8, len * 0.35f, LEAF);
  int n = 2 + (mb_rand(b) < 0.5f);
  float az0 = mb_rand(b) * 6.2831853f;
  for (int i = 0; i < n; i++) {
    float nd[3];
    mb_turn(d, 0.3f + 0.35f * mb_rand(b), az0 + i * 6.2831853f / n + (mb_rand(b) - 0.5f), 0.35f, nd);
    mb_branch(b, e, nd, len * (0.66f + 0.14f * mb_rand(b)), rad * 0.68f, depth - 1);
  }
}
static void mb_tree(MeshB *b) {
  float o[3] = { 0, 0, 0 }, d[3] = { (mb_rand(b) - 0.5f) * 0.12f, 1, (mb_rand(b) - 0.5f) * 0.12f };
  mb_unit(d);
  float top[3] = { d[0] * 0.3f, d[1] * 0.3f, d[2] * 0.3f };
  mb_tube(b, o, top, 0.045f, 0.034f, BARK);
  mb_branch(b, top, d, 0.28f, 0.034f, 4);
}
static void mb_pine(MeshB *b) {
  float o[3] = { 0, 0, 0 }, m1[3] = { 0, 0.45f, 0 }, top[3] = { 0, 1, 0 };
  mb_tube(b, o, m1, 0.045f, 0.03f, BARK);
  mb_tube(b, m1, top, 0.03f, 0.004f, BARK);
  enum { LEVELS = 10 };
  for (int l = 0; l < LEVELS; l++) {
    float t = (float)l / (LEVELS - 1), h = 0.16f + 0.78f * t + (mb_rand(b) - 0.5f) * 0.03f;
    float reach = 0.46f * (1 - t) + 0.07f;
    int n = 5 + (mb_rand(b) < 0.5f);
    float az0 = mb_rand(b) * 6.2831853f;
    for (int i = 0; i < n; i++) {
      float az = az0 + i * 6.2831853f / n + (mb_rand(b) - 0.5f) * 0.5f;
      float d[3] = { cosf(az), -0.28f - 0.12f * mb_rand(b), sinf(az) }, at[3] = { 0, h, 0 };
      mb_unit(d);
      float e[3] = { d[0] * reach, h + d[1] * reach, d[2] * reach };
      mb_tube(b, at, e, 0.012f * (1 - t) + 0.004f, 0.003f, BARK);
      float c[3] = { e[0] * 0.55f, h + d[1] * reach * 0.5f, e[2] * 0.55f }, u[3] = { d[0] * reach * 0.55f, d[1] * reach * 0.55f, d[2] * reach * 0.55f };
      float side[3] = { -d[2], 0, d[0] }, w1[3], w2[3], nrm[3] = { d[0], 0.9f, d[2] };
      float wid = reach * 0.42f;
      for (int q = 0; q < 3; q++) { w1[q] = side[q] * wid; w2[q] = 0; }
      w2[1] = wid * 0.6f;                            // (a frond: one card flat, one across it, for its volume)
      float k = 0.85f + 0.3f * t + (mb_rand(b) - 0.5f) * 0.1f, col[3] = { NEEDLE[0] * k, NEEDLE[1] * k, NEEDLE[2] * k };
      mb_card(b, c, u, w1, nrm, col);
      mb_card(b, c, u, w2, nrm, col);
    }
  }
  float tip[3] = { 0, 0.97f, 0 };
  mb_leaves(b, tip, 0.05f, 6, 0.05f, NEEDLE);
}
static void mb_bush(MeshB *b) {
  int n = 5 + (int)(mb_rand(b) * 3);
  for (int i = 0; i < n; i++) {
    float az = (i + mb_rand(b) * 0.6f) * 6.2831853f / n, lean = 0.45f + 0.5f * mb_rand(b);
    float d[3] = { cosf(az) * sinf(lean), cosf(lean), sinf(az) * sinf(lean) }, o[3] = { d[0] * 0.03f, 0, d[2] * 0.03f };
    float len = 0.32f + 0.15f * mb_rand(b), e[3] = { o[0] + d[0] * len, o[1] + d[1] * len, o[2] + d[2] * len };
    mb_tube(b, o, e, 0.022f, 0.014f, BARK);
    float mid[3] = { (o[0] + e[0]) / 2, (o[1] + e[1]) / 2, (o[2] + e[2]) / 2 };
    mb_leaves(b, mid, 0.2f, 10, 0.08f, SHRUB);
    for (int k = 0; k < 2; k++) {
      float nd[3];
      mb_turn(d, 0.5f + 0.3f * mb_rand(b), az + (k ? 1.4f : -1.4f), 0.1f, nd);
      float l2 = len * 0.6f, e2[3] = { e[0] + nd[0] * l2, e[1] + nd[1] * l2, e[2] + nd[2] * l2 };
      mb_tube(b, e, e2, 0.013f, 0.007f, BARK);
      mb_leaves(b, e2, 0.24f, 16, 0.085f, SHRUB);
    }
  }
}
// the primitives a game draws with (mesh = { "cylinder" }...): 1 m, centred, y up, as "cube" and "sphere"
static bool mb_into(MeshB *b, Mesh3D *m) {         // (a built mesh, as it is: its normals its own)
  bool ok = !b->bad && b->nv > 0 && mesh3d_alloc(m, b->nv, b->ni);
  if (ok) {
    SDL_memcpy(m->pos, b->p, sizeof(float) * 3 * (size_t)b->nv); SDL_memcpy(m->nrm, b->n, sizeof(float) * 3 * (size_t)b->nv);
    SDL_memcpy(m->col, b->c, 4 * (size_t)b->nv); SDL_memcpy(m->idx, b->ix, sizeof(unsigned) * (size_t)b->ni);
    mesh3d_one_part(m);
  }
  SDL_free(b->p); SDL_free(b->n); SDL_free(b->c); SDL_free(b->ix);
  return ok;
}
static void mb_disc(MeshB *b, float y, float r, bool up, int seg) {   // (a cap)
  float n[3] = { 0, up ? 1.f : -1.f, 0 }, c[3] = { 0, y, 0 };
  int mid = mb_vert(b, c, n, 1, 1, 1), first = b->nv;
  for (int i = 0; i < seg; i++) { float t = i * 6.2831853f / seg, p[3] = { cosf(t) * r, y, -sinf(t) * r }; mb_vert(b, p, n, 1, 1, 1); }
  for (int i = 0; i < seg; i++) { int a = first + i, c2 = first + (i + 1) % seg; if (up) mb_tri(b, mid, a, c2); else mb_tri(b, mid, c2, a); }
}
static void mesh3d_shape(Mesh3D *m, int kind) {   // 0 cylinder, 1 cone, 2 capsule, 3 triangle, 4 line
  enum { SEG = 24 };
  MeshB b = { 0 };
  if (kind == 0 || kind == 1) {                    // (a side round y, from -0.5 to 0.5, radius 0.5; the cone's top a point)
    float slope = kind ? 0.5f : 0;                 // (the cone's normals lean up: its radius / height)
    int first = b.nv;
    for (int e = 0; e < 2; e++) for (int i = 0; i < SEG; i++) {
      float t = i * 6.2831853f / SEG, r = (kind && e) ? 0 : 0.5f, p[3] = { cosf(t) * r, e ? 0.5f : -0.5f, -sinf(t) * r }, n[3] = { cosf(t), slope, -sinf(t) };
      mb_vert(&b, p, n, 1, 1, 1);
    }
    for (int i = 0; i < SEG; i++) { int a0 = first + i, a1 = first + (i + 1) % SEG; mb_tri(&b, a0, a1, a0 + SEG); mb_tri(&b, a1, a1 + SEG, a0 + SEG); }
    mb_disc(&b, -0.5f, 0.5f, false, SEG);
    if (!kind) mb_disc(&b, 0.5f, 0.5f, true, SEG);
  } else if (kind == 2) {                          // (radius 0.25: a tube 0.5 high, half spheres on its ends: 1 m in all)
    enum { RING = 12 };
    int first = b.nv;
    for (int r = 0; r <= RING + 1; r++) {          // (the top half's rings, then the bottom's: the same ring twice at the middle, apart)
      int rr = r <= RING / 2 ? r : r - 1;
      float th = (float)rr / RING * 3.14159265f, off = r <= RING / 2 ? 0.25f : -0.25f;
      for (int s = 0; s <= SEG; s++) {
        float ph = (float)s / SEG * 6.2831853f, n[3] = { sinf(th) * cosf(ph), cosf(th), -sinf(th) * sinf(ph) };
        float p[3] = { n[0] * 0.25f, n[1] * 0.25f + off, n[2] * 0.25f };
        mb_vert(&b, p, n, 1, 1, 1);
      }
    }
    for (int r = 0; r <= RING; r++) for (int s = 0; s < SEG; s++) {
      int a = first + r * (SEG + 1) + s, c = a + SEG + 1;
      mb_tri(&b, a, c, a + 1); mb_tri(&b, a + 1, c, c + 1);
    }
  } else if (kind == 3) {                          // (both faces: seen from either side)
    float P[3][3] = { { -0.5f, -0.5f, 0 }, { 0.5f, -0.5f, 0 }, { 0, 0.5f, 0 } };
    for (int side = 0; side < 2; side++) {
      float n[3] = { 0, 0, side ? -1.f : 1.f };
      int a = mb_vert(&b, P[0], n, 1, 1, 1), c = mb_vert(&b, P[1], n, 1, 1, 1), d = mb_vert(&b, P[2], n, 1, 1, 1);
      if (side) mb_tri(&b, a, d, c); else mb_tri(&b, a, c, d);
    }
  } else {                                         // (a line along x, -0.5 .. 0.5)
    float A[3] = { -0.5f, 0, 0 }, B[3] = { 0.5f, 0, 0 }, n[3] = { 0, 1, 0 };
    int a = mb_vert(&b, A, n, 1, 1, 1), c = mb_vert(&b, B, n, 1, 1, 1);
    mb_tri(&b, a, c, c); b.ni = 2;                // (the index array grown by a triangle's worth; a pair kept)
    m->lines = true;
  }
  mb_into(&b, m);
}
static void mesh3d_plant(Mesh3D *m, int kind, unsigned variant) {   // kind: 0 tree, 1 pine, 2 bush
  MeshB b = { 0 };
  b.seed = 977u * (unsigned)(kind + 1) + (variant > 1 ? variant * 7919u : 0);
  if (kind == 0) mb_tree(&b); else if (kind == 1) mb_pine(&b); else mb_bush(&b);
  if (!b.bad && b.nv > 0 && mesh3d_alloc(m, b.nv, b.ni)) {
    float lo[3] = { 1e30f, 1e30f, 1e30f }, hi[3] = { -1e30f, -1e30f, -1e30f };
    for (int i = 0; i < b.nv; i++) for (int q = 0; q < 3; q++) { lo[q] = SDL_min(lo[q], b.p[i * 3 + q]); hi[q] = SDL_max(hi[q], b.p[i * 3 + q]); }
    float half = SDL_max(SDL_max(fabsf(lo[0]), fabsf(hi[0])), SDL_max(fabsf(lo[2]), fabsf(hi[2])));   // (round its foot: x, z alike)
    float k[3] = { 0.5f / SDL_max(half, 1e-6f), 1 / SDL_max(hi[1] - SDL_min(lo[1], 0.f), 1e-6f), 0 };
    k[2] = k[0];
    for (int i = 0; i < b.nv; i++) {
      float n[3];
      for (int q = 0; q < 3; q++) { m->pos[i * 3 + q] = (q == 1 ? b.p[i * 3 + q] - SDL_min(lo[1], 0.f) : b.p[i * 3 + q]) * k[q]; n[q] = b.n[i * 3 + q] / k[q]; }
      mb_unit(n);                                  // (squashed into its box: its normals the other way)
      SDL_memcpy(&m->nrm[i * 3], n, sizeof n);
    }
    SDL_memcpy(m->col, b.c, 4 * (size_t)b.nv);
    SDL_memcpy(m->idx, b.ix, sizeof(unsigned) * (size_t)b.ni);
    mesh3d_one_part(m);
  }
  SDL_free(b.p); SDL_free(b.n); SDL_free(b.c); SDL_free(b.ix);
}

// "grid": the editor's ground grid (render.h, stopped or paused), lines 1 m apart over 40 x 40 m round y = 0, every 5th
// brighter, fading out from the middle (vertex alpha); "gridaxis": one line along x, 40 m, fading the same (tinted: an axis)
static void mesh3d_gridlines(Mesh3D *m, bool axis) {
  enum { N = 20 };
  int nl = axis ? 1 : 2 * (2 * N + 1), nv = nl * (2 * N + 1), ni = nl * 2 * N * 2;
  if (!mesh3d_alloc(m, nv, ni)) return;
  int v = 0, k = 0;
  for (int l = 0; l < nl; l++) {
    int dir = axis ? 0 : l / (2 * N + 1), at = axis ? 0 : l % (2 * N + 1) - N;   // (dir 0: along x at z = at; 1: along z at x = at)
    float a0 = axis ? 0.8f : (at % 5 == 0 ? 0.4f : 0.18f);
    int first = v;
    for (int s = -N; s <= N; s++, v++) {
      float x = dir ? (float)at : (float)s, z = dir ? (float)s : (float)at, r = sqrtf(x * x + z * z) / N;
      m->pos[v * 3] = x; m->pos[v * 3 + 1] = 0; m->pos[v * 3 + 2] = z;
      m->nrm[v * 3 + 1] = 1;
      float a = a0 * SDL_max(0.f, 1 - r * r);
      m->col[v * 4 + 3] = (unsigned char)(255 * a);
    }
    for (int s = 0; s < 2 * N; s++) { m->idx[k++] = (unsigned)(first + s); m->idx[k++] = (unsigned)(first + s + 1); }
  }
  m->lines = true; m->line_fade = 14;
  mesh3d_one_part(m);
}

// Levels of detail (docs/3D.md §31): mesh3d_lod(base, level) -> a simpler copy, made once (again when the base is read
// again). Vertex clustering: a grid over its box (48, 24, 12, 6 cells along its longest side, levels 1..4), the
// vertices in a cell (of the same part, the same 1/16th of the texture: seams kept, no island's uv stretched over
// another's) made one (positions and normals averaged; uv, colour and the skin's binds the
// first one's), triangles left with fewer than three corners dropped. The textures, skeleton and clips are the
// base's (shared: posed as it is). Blend shapes are dropped.
typedef struct { Uint64 key; int id; } LodKey;
static int SDLCALL lod_key_cmp(const void *a, const void *b) {
  Uint64 x = ((const LodKey *)a)->key, y = ((const LodKey *)b)->key;
  return x < y ? -1 : x > y ? 1 : ((const LodKey *)a)->id - ((const LodKey *)b)->id;
}
static bool mesh3d_simplify(const Mesh3D *b, Mesh3D *o, int R) {
  SDL_zerop(o);
  if (!b->ok || b->nv <= 0 || b->ni < 3 || b->lines) return false;
  float ext = SDL_max(SDL_max(b->bmax[0] - b->bmin[0], b->bmax[1] - b->bmin[1]), b->bmax[2] - b->bmin[2]);
  float cell = SDL_max(ext / R, 1e-6f);
  int *vpart = SDL_malloc(sizeof(int) * (size_t)b->nv), *cl = SDL_malloc(sizeof(int) * (size_t)b->nv);
  LodKey *k = SDL_malloc(sizeof *k * (size_t)b->nv);
  if (!vpart || !cl || !k) { SDL_free(vpart); SDL_free(cl); SDL_free(k); return false; }
  for (int i = 0; i < b->nv; i++) vpart[i] = 0;
  for (int p = b->nparts - 1; p >= 0; p--)         // (a vertex's part: the first that uses it)
    for (int q = b->parts[p].first; q < b->parts[p].first + b->parts[p].count && q < b->ni; q++) if (b->idx[q] < (unsigned)b->nv) vpart[b->idx[q]] = p;
  for (int i = 0; i < b->nv; i++) {              // (its key: part, cell, and where in the texture it is: a seam's two
    Uint64 c[3], t[2];                             //  sides, the same place but each its island, kept apart)
    for (int a = 0; a < 3; a++) c[a] = (Uint64)SDL_clamp((int)((b->pos[i * 3 + a] - b->bmin[a]) / cell), 0, 4095);
    for (int a = 0; a < 2; a++) t[a] = (Uint64)((int)SDL_floorf(b->uv[i * 2 + a] * 16.f) & 1023);
    k[i].key = ((Uint64)(vpart[i] & 0xff) << 56) | (c[0] << 44) | (c[1] << 32) | (c[2] << 20) | (t[0] << 10) | t[1];
    k[i].id = i;
  }
  SDL_qsort(k, (size_t)b->nv, sizeof *k, lod_key_cmp);
  int nc = 0;
  for (int i = 0; i < b->nv; i++) { if (i && k[i].key != k[i - 1].key) nc++; cl[k[i].id] = nc; }
  nc++;
  bool ok = mesh3d_alloc(o, nc, b->ni);
  if (ok && b->jnt) { o->jnt = SDL_calloc((size_t)nc * 4, sizeof *o->jnt); o->wgt = SDL_calloc((size_t)nc * 4, sizeof *o->wgt); ok = o->jnt && o->wgt; }
  int *cnt = ok ? SDL_calloc((size_t)nc, sizeof(int)) : NULL;
  o->parts = cnt ? SDL_calloc((size_t)SDL_max(b->nparts, 1), sizeof *o->parts) : NULL;
  o->shares = true;                                // (from here on: freeing it leaves the base's)
  if (!o->parts) { SDL_free(vpart); SDL_free(cl); SDL_free(k); SDL_free(cnt); mesh3d_free(o); return false; }
  SDL_memset(o->pos, 0, sizeof(float) * 3 * (size_t)nc); SDL_memset(o->nrm, 0, sizeof(float) * 3 * (size_t)nc);
  for (int i = 0; i < b->nv; i++) {
    int c = cl[i];
    for (int a = 0; a < 3; a++) { o->pos[c * 3 + a] += b->pos[i * 3 + a]; o->nrm[c * 3 + a] += b->nrm[i * 3 + a]; }
    if (!cnt[c]++) {                               // (the first one's: uv, colour, binds)
      SDL_memcpy(&o->uv[c * 2], &b->uv[i * 2], sizeof(float) * 2); SDL_memcpy(&o->col[c * 4], &b->col[i * 4], 4);
      if (b->jnt) { SDL_memcpy(&o->jnt[c * 4], &b->jnt[i * 4], sizeof *o->jnt * 4); SDL_memcpy(&o->wgt[c * 4], &b->wgt[i * 4], sizeof *o->wgt * 4); }
    }
  }
  for (int c = 0; c < nc; c++) {
    for (int a = 0; a < 3; a++) o->pos[c * 3 + a] /= (float)cnt[c];
    float *n = &o->nrm[c * 3], l = sqrtf(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
    if (l > 1e-9f) { n[0] /= l; n[1] /= l; n[2] /= l; } else n[1] = 1;
  }
  int ni = 0;
  for (int p = 0; p < b->nparts; p++) {
    o->parts[p] = b->parts[p];
    o->parts[p].first = ni;
    for (int q = b->parts[p].first; q + 2 < b->parts[p].first + b->parts[p].count && q + 2 < b->ni; q += 3) {
      unsigned A = b->idx[q], B = b->idx[q + 1], C = b->idx[q + 2];
      if (A >= (unsigned)b->nv || B >= (unsigned)b->nv || C >= (unsigned)b->nv) continue;
      int x = cl[A], y = cl[B], z = cl[C];
      if (x == y || y == z || x == z) continue;    // (collapsed)
      o->idx[ni++] = (unsigned)x; o->idx[ni++] = (unsigned)y; o->idx[ni++] = (unsigned)z;
    }
    o->parts[p].count = ni - o->parts[p].first;
  }
  o->ni = ni; o->nparts = b->nparts;
  o->tex = b->tex; o->ntex = b->ntex;              // (shared with the base)
  o->joints = b->joints; o->njoints = b->njoints; o->clips = b->clips; o->nclips = b->nclips;
  o->nbinds = b->nbinds; o->bind_joint = b->bind_joint; o->ibm = b->ibm;
  mesh3d_bounds(o);
  o->ok = ni > 0;
  SDL_free(vpart); SDL_free(cl); SDL_free(k); SDL_free(cnt);
  return o->ok;
}
static struct { const Mesh3D *base; unsigned ver; int level; Uint64 used; Mesh3D m; } lods3d[64];
static Mesh3D *mesh3d_lod(const Mesh3D *base, int level) {   // -> the base's level-th LOD (1..4), else the base itself
  static const int GRID[4] = { 48, 24, 12, 6 };
  if (!base || level <= 0 || !base->ok || base->lines || base->posed || base->shares) return (Mesh3D *)base;
  level = SDL_min(level, 4);
  int slot = -1, old = 0;
  for (int i = 0; i < (int)SDL_arraysize(lods3d) && slot < 0; i++) {
    if (lods3d[i].base == base && lods3d[i].level == level) slot = i;
    else if (lods3d[i].used < lods3d[old].used) old = i;
  }
  if (slot < 0 || lods3d[slot].ver != base->version) {   // (not made yet, or its base read again: made now)
    if (slot < 0) slot = old;
    if (lods3d[slot].m.shares) mesh3d_free(&lods3d[slot].m);
    unsigned v = lods3d[slot].m.version;
    lods3d[slot].base = base; lods3d[slot].level = level; lods3d[slot].ver = base->version;
    if (!mesh3d_simplify(base, &lods3d[slot].m, GRID[level - 1]) || lods3d[slot].m.ni >= base->ni) {   // (no simpler: the base)
      if (lods3d[slot].m.shares) mesh3d_free(&lods3d[slot].m);
      lods3d[slot].m.ok = false;
    }
    SDL_snprintf(lods3d[slot].m.file, sizeof lods3d[slot].m.file, "%s#lod%d", base->file, level);
    lods3d[slot].m.version = v + 1;                // (the GPU's copy made again)
  }
  lods3d[slot].used = SDL_GetTicks() + 1;
  return lods3d[slot].m.ok ? &lods3d[slot].m : (Mesh3D *)base;
}

// landscapes (runtime/landscape.lua: a node's landscape3d, plugins/landscape's preview): a height field's mesh, a
// grid nx x nz over w x d (centred, row 1 at the back: -d/2), its points' heights h and colours c (0xRRGGBB), made
// again when its version changes. Kept in 8 slots by key ("land:<its table>", "lite:<view>"); one part, no texture.
static struct { char key[64]; unsigned ver; Uint64 used; Mesh3D m; } lands3d[8];
static Mesh3D *land3d_get(const char *key, unsigned ver, int nx, int nz, float w, float d, const float *h, const Uint32 *c) {
  if (nx < 2 || nz < 2 || !h) return NULL;
  int slot = -1, old = 0;
  for (int i = 0; i < (int)SDL_arraysize(lands3d) && slot < 0; i++) {
    if (!strcmp(lands3d[i].key, key)) slot = i;
    else if (lands3d[i].used < lands3d[old].used) old = i;
  }
  if (slot < 0) { slot = old; lands3d[slot].ver = 0; SDL_strlcpy(lands3d[slot].key, key, sizeof lands3d[slot].key); }
  Mesh3D *m = &lands3d[slot].m;
  lands3d[slot].used = SDL_GetTicks() + 1;
  if (m->ok && lands3d[slot].ver == ver && m->nv == nx * nz) return m;
  unsigned v = m->version;
  bool same = m->ok && m->nv == nx * nz;           // (the same grid: its arrays kept, the heights written over)
  if (!same) {
    if (m->ok || m->pos) mesh3d_free(m);
    SDL_zerop(m);
    if (!mesh3d_alloc(m, nx * nz, (nx - 1) * (nz - 1) * 6)) { mesh3d_free(m); SDL_zerop(m); return NULL; }
    int q = 0;
    for (int j = 0; j + 1 < nz; j++) for (int i = 0; i + 1 < nx; i++) {   // (counter-clockwise seen from above)
      unsigned a = (unsigned)(j * nx + i), b = a + 1, cc = a + (unsigned)nx, dd = cc + 1;
      m->idx[q++] = a; m->idx[q++] = cc; m->idx[q++] = b;
      m->idx[q++] = b; m->idx[q++] = cc; m->idx[q++] = dd;
    }
    mesh3d_one_part(m);
  }
  float sx = w / (nx - 1), sz = d / (nz - 1);
  for (int j = 0; j < nz; j++) for (int i = 0; i < nx; i++) {
    int k = j * nx + i;
    float *P = &m->pos[k * 3], *N = &m->nrm[k * 3];
    P[0] = -w / 2 + i * sx; P[1] = h[k]; P[2] = -d / 2 + j * sz;
    int i0 = i > 0 ? i - 1 : i, i1 = i + 1 < nx ? i + 1 : i, j0 = j > 0 ? j - 1 : j, j1 = j + 1 < nz ? j + 1 : j;
    float dx = (h[j * nx + i1] - h[j * nx + i0]) / ((i1 - i0) * sx), dz = (h[j1 * nx + i] - h[j0 * nx + i]) / ((j1 - j0) * sz);
    float l = sqrtf(dx * dx + 1 + dz * dz);
    N[0] = -dx / l; N[1] = 1 / l; N[2] = -dz / l;
    m->uv[k * 2] = P[0]; m->uv[k * 2 + 1] = P[2];
    Uint32 cv = c ? c[k] : 0x7f9a5a;
    m->col[k * 4] = (unsigned char)(cv >> 16); m->col[k * 4 + 1] = (unsigned char)(cv >> 8); m->col[k * 4 + 2] = (unsigned char)cv; m->col[k * 4 + 3] = 255;
  }
  mesh3d_bounds(m);
  m->ok = true;
  SDL_snprintf(m->file, sizeof m->file, "land:%d:%s", slot, key);
  m->version = v + 1;                              // (the GPU's copy made again)
  lands3d[slot].ver = ver;
  return m;
}

// glTF 2.0 (cgltf): every node's mesh, baked at the node's world transform; materials' base colour (factor, texture),
// vertex colours (COLOR_0)
static int mesh3d_image(Mesh3D *m, cgltf_image *img, const char *dir, cgltf_image *images) {
  int at = (int)(img - images);
  if (at < 0 || at >= m->ntex) return -1;
  if (m->tex[at].rgba) return at;
  const unsigned char *data = NULL;
  size_t len = 0;
  void *file = NULL;
  if (img->buffer_view && img->buffer_view->buffer->data) {
    data = (const unsigned char *)img->buffer_view->buffer->data + img->buffer_view->offset;
    len = img->buffer_view->size;
  } else if (img->uri && SDL_strncmp(img->uri, "data:", 5)) {
    char path[1200];
    SDL_snprintf(path, sizeof path, "%s%s", dir, img->uri);
    cgltf_decode_uri(path + SDL_strlen(dir));     // (%20 and the like)
    file = SDL_LoadFile(path, &len);
    data = file;
  }
  if (data && len) {
    int w = 0, h = 0;
    unsigned char *px = editor_image_decode(data, (int)len, &w, &h);
    if (px) {
      m->tex[at].rgba = SDL_malloc((size_t)w * h * 4);
      if (m->tex[at].rgba) { SDL_memcpy(m->tex[at].rgba, px, (size_t)w * h * 4); m->tex[at].w = w; m->tex[at].h = h; }
      editor_image_free(px);
    }
  }
  SDL_free(file);
  return m->tex[at].rgba ? at : -1;
}
// a skin: its joints (parents among them, the rest pose, inverse bind matrices) and the clips that move them
static void mesh3d_skeleton(Mesh3D *m, cgltf_data *d, cgltf_skin *skin) {
  int n = (int)SDL_min(skin->joints_count, 255);
  m->joints = SDL_calloc((size_t)n, sizeof *m->joints);
  m->ibm = SDL_calloc((size_t)n * 16, sizeof(float));
  m->bind_joint = SDL_calloc((size_t)n, sizeof(int));
  if (!m->joints || !m->ibm || !m->bind_joint) return;
  m->njoints = m->nbinds = n;
  for (int j = 0; j < n; j++) m->bind_joint[j] = j;   // (glTF: a bind a joint)
  for (int j = 0; j < n; j++) {
    cgltf_node *nd = skin->joints[j];
    Joint3D *J = &m->joints[j];
    J->parent = -1;
    for (int k = 0; k < n; k++) if (nd->parent && skin->joints[k] == nd->parent) J->parent = k;
    SDL_memset(J->base, 0, sizeof J->base); J->base[0] = J->base[5] = J->base[10] = J->base[15] = 1;
    if (J->parent < 0 && nd->parent) cgltf_node_transform_world(nd->parent, J->base);
    J->r[3] = 1; J->s[0] = J->s[1] = J->s[2] = 1;
    if (nd->has_translation) SDL_memcpy(J->t, nd->translation, 12);
    if (nd->has_rotation) SDL_memcpy(J->r, nd->rotation, 16);
    if (nd->has_scale) SDL_memcpy(J->s, nd->scale, 12);
    J->has_matrix = nd->has_matrix;
    if (nd->has_matrix) SDL_memcpy(J->matrix, nd->matrix, 64);
    SDL_strlcpy(J->name, nd->name ? nd->name : "", sizeof J->name);
    float *I = &m->ibm[j * 16];
    I[0] = I[5] = I[10] = I[15] = 1;
    if (skin->inverse_bind_matrices) cgltf_accessor_read_float(skin->inverse_bind_matrices, (cgltf_size)j, I, 16);
  }
  m->jnt = SDL_calloc((size_t)m->nv * 4, sizeof(unsigned short));
  m->wgt = SDL_calloc((size_t)m->nv * 4, sizeof(float));
}
// its clips: channels on the skin's joints (translation, rotation, scale) and on the morphs' nodes (weights)
static void mesh3d_gltf_clips(Mesh3D *m, cgltf_data *d, cgltf_skin *skin, cgltf_node **mnode, int *mtarget, int *mntg) {
  if (!d->animations_count || (!m->njoints && !m->nmorphs)) return;
  int n = m->njoints;
  m->clips = SDL_calloc(d->animations_count, sizeof *m->clips);
  for (cgltf_size a = 0; m->clips && a < d->animations_count; a++) {
    cgltf_animation *an = &d->animations[a];
    Clip3D *C = &m->clips[m->nclips];
    C->src = -1;
    int cap = (int)an->channels_count + m->nmorphs + 1;
    C->chan = SDL_calloc((size_t)cap, sizeof *C->chan);
    if (!C->chan) continue;
    if (an->name) SDL_strlcpy(C->name, an->name, sizeof C->name); else SDL_snprintf(C->name, sizeof C->name, "clip %d", (int)a + 1);
    for (cgltf_size c = 0; c < an->channels_count; c++) {
      cgltf_animation_channel *ch = &an->channels[c];
      cgltf_animation_sampler *sa = ch->sampler;
      if (!sa || !sa->input || !sa->output || !sa->input->count) continue;
      int keys = (int)sa->input->count;
      bool cubic = sa->interpolation == cgltf_interpolation_type_cubic_spline;
      if (ch->target_path == cgltf_animation_path_type_weights) {   // (a node's morph weights: every key holds all its targets')
        for (int k = 0; k < m->nmorphs && C->nchan < cap; k++) {
          if (mnode[k] != ch->target_node) continue;
          Chan3D *K = &C->chan[C->nchan];
          K->times = SDL_malloc(sizeof(float) * (size_t)keys); K->vals = SDL_malloc(sizeof(float) * (size_t)keys);
          if (!K->times || !K->vals) { SDL_free(K->times); SDL_free(K->vals); K->times = K->vals = NULL; continue; }
          for (int f = 0; f < keys; f++) {
            cgltf_accessor_read_float(sa->input, (cgltf_size)f, &K->times[f], 1);
            cgltf_accessor_read_float(sa->output, (cgltf_size)((cubic ? f * 3 + 1 : f) * mntg[k] + mtarget[k]), &K->vals[f], 1);
          }
          K->joint = k; K->path = 3; K->n = keys; K->step = sa->interpolation == cgltf_interpolation_type_step;
          if (K->times[keys - 1] > C->duration) C->duration = K->times[keys - 1];
          C->nchan++;
        }
        continue;
      }
      int path = ch->target_path == cgltf_animation_path_type_translation ? 0 : ch->target_path == cgltf_animation_path_type_rotation ? 1 :
                 ch->target_path == cgltf_animation_path_type_scale ? 2 : -1;
      int joint = -1;
      for (int k = 0; skin && k < n; k++) if (skin->joints[k] == ch->target_node) joint = k;
      if (path < 0 || joint < 0 || C->nchan >= cap) continue;   // (other nodes: not yet)
      int comp = path == 1 ? 4 : 3;
      Chan3D *K = &C->chan[C->nchan];
      K->times = SDL_malloc(sizeof(float) * (size_t)keys); K->vals = SDL_malloc(sizeof(float) * (size_t)keys * comp);
      if (!K->times || !K->vals) { SDL_free(K->times); SDL_free(K->vals); K->times = K->vals = NULL; continue; }
      for (int k = 0; k < keys; k++) {
        cgltf_accessor_read_float(sa->input, (cgltf_size)k, &K->times[k], 1);
        cgltf_accessor_read_float(sa->output, (cgltf_size)(cubic ? k * 3 + 1 : k), &K->vals[k * comp], (cgltf_size)comp);   // (cubic: the key's value, read as linear)
      }
      K->joint = joint; K->path = path; K->n = keys; K->step = sa->interpolation == cgltf_interpolation_type_step;
      if (K->times[keys - 1] > C->duration) C->duration = K->times[keys - 1];
      C->nchan++;
    }
    m->nclips++;
  }
}
static bool mesh3d_gltf(Mesh3D *m, const char *path) {
  cgltf_options opt = { 0 };
  cgltf_data *d = NULL;
  if (cgltf_parse_file(&opt, path, &d) != cgltf_result_success) { SDL_snprintf(m->err, sizeof m->err, "not a glTF file"); return false; }
  if (cgltf_load_buffers(&opt, d, path) != cgltf_result_success) { SDL_snprintf(m->err, sizeof m->err, "its buffers can't be read"); cgltf_free(d); return false; }
  char dir[1024];
  SDL_strlcpy(dir, path, sizeof dir);
  char *sl = SDL_strrchr(dir, '/'), *bs = SDL_strrchr(dir, '\\');
  if (bs > sl) sl = bs;
  if (sl) sl[1] = 0; else dir[0] = 0;
  // the nodes to draw: the scene's (all of them, depth first), else every node with a mesh
  int nnodes = 0;
  cgltf_node **nodes = SDL_calloc(d->nodes_count + 1, sizeof *nodes);
  if (d->nodes_count) {
    for (cgltf_size i = 0; i < d->nodes_count; i++) if (d->nodes[i].mesh) nodes[nnodes++] = &d->nodes[i];
  }
  int nv = 0, ni = 0, np = 0;                      // (sizes first)
  for (int k = 0; k < nnodes; k++) {
    cgltf_mesh *me = nodes[k]->mesh;
    for (cgltf_size p = 0; p < me->primitives_count; p++) {
      cgltf_primitive *pr = &me->primitives[p];
      if (pr->type != cgltf_primitive_type_triangles) continue;
      cgltf_accessor *pa = NULL;
      for (cgltf_size a = 0; a < pr->attributes_count; a++) if (pr->attributes[a].type == cgltf_attribute_type_position) pa = pr->attributes[a].data;
      if (!pa) continue;
      nv += (int)pa->count;
      ni += pr->indices ? (int)pr->indices->count : (int)pa->count;
      np++;
    }
  }
  if (!nv || !ni || !mesh3d_alloc(m, nv, ni)) { SDL_free(nodes); cgltf_free(d); SDL_snprintf(m->err, sizeof m->err, "no triangles in it"); return false; }
  m->nv = nv;
  m->parts = SDL_calloc((size_t)np, sizeof *m->parts);
  m->ntex = (int)d->images_count;
  m->tex = m->ntex ? SDL_calloc((size_t)m->ntex, sizeof *m->tex) : NULL;
  cgltf_skin *skin = NULL;                         // (the first skin a mesh node has: its nodes' vertices stay in bind space)
  for (int k = 0; k < nnodes && !skin; k++) if (nodes[k]->skin && nodes[k]->skin->joints_count) skin = nodes[k]->skin;
  if (skin) mesh3d_skeleton(m, d, skin);
  int ntg_all = 0;                                 // morph targets: one Morph3D a node's target (its vertices: that node's)
  for (int k = 0; k < nnodes; k++) {
    cgltf_mesh *me = nodes[k]->mesh;
    int t = 0;
    for (cgltf_size p = 0; p < me->primitives_count; p++) if ((int)me->primitives[p].targets_count > t) t = (int)me->primitives[p].targets_count;
    ntg_all += t;
  }
  if (ntg_all > 256) ntg_all = 256;
  cgltf_node **mnode = ntg_all ? SDL_calloc((size_t)ntg_all, sizeof *mnode) : NULL;
  int *mtarget = ntg_all ? SDL_calloc((size_t)ntg_all, sizeof(int)) : NULL, *mntg = ntg_all ? SDL_calloc((size_t)ntg_all, sizeof(int)) : NULL;
  if (ntg_all && mnode && mtarget && mntg) m->morphs = SDL_calloc((size_t)ntg_all, sizeof *m->morphs);
  int v0 = 0, i0 = 0;
  for (int k = 0; k < nnodes; k++) {
    float W[16];
    bool skinned = skin && nodes[k]->skin == skin;
    cgltf_node_transform_world(nodes[k], W);       // (column-major)
    if (skinned) { SDL_memset(W, 0, sizeof W); W[0] = W[5] = W[10] = W[15] = 1; }   // (glTF: a skinned mesh's node transform is ignored)
    float Nm[9];                                   // its normals' matrix: the upper 3x3's inverse transpose
    {
      float a = W[0], b = W[4], c = W[8], dd = W[1], e = W[5], f = W[9], g = W[2], h = W[6], ii = W[10];
      float C00 = e * ii - f * h, C01 = -(dd * ii - f * g), C02 = dd * h - e * g;   // (the cofactors: the inverse transpose is them / det)
      float C10 = -(b * ii - c * h), C11 = a * ii - c * g, C12 = -(a * h - b * g);
      float C20 = b * f - c * e, C21 = -(a * f - c * dd), C22 = a * e - b * dd;
      float det = a * C00 + b * C01 + c * C02;
      if (fabsf(det) < 1e-12f) det = 1;
      float inv = 1 / det;
      Nm[0] = C00 * inv; Nm[1] = C01 * inv; Nm[2] = C02 * inv;
      Nm[3] = C10 * inv; Nm[4] = C11 * inv; Nm[5] = C12 * inv;
      Nm[6] = C20 * inv; Nm[7] = C21 * inv; Nm[8] = C22 * inv;
    }
    cgltf_mesh *me = nodes[k]->mesh;
    int ntg = 0, node_nv = 0, mo0 = m->nmorphs;
    for (cgltf_size p = 0; p < me->primitives_count; p++) {
      cgltf_primitive *pr = &me->primitives[p];
      if (pr->type != cgltf_primitive_type_triangles) continue;
      if ((int)pr->targets_count > ntg) ntg = (int)pr->targets_count;
      for (cgltf_size a = 0; a < pr->attributes_count; a++) if (pr->attributes[a].type == cgltf_attribute_type_position) node_nv += (int)pr->attributes[a].data->count;
    }
    if (!m->morphs || m->nmorphs + ntg > ntg_all) ntg = 0;
    for (int t = 0; t < ntg; t++) {                // (its targets: named by the mesh's extras "targetNames", else "<mesh> <n>")
      Morph3D *M = &m->morphs[m->nmorphs];
      if ((size_t)t < me->target_names_count && me->target_names[t]) SDL_strlcpy(M->name, me->target_names[t], sizeof M->name);
      else SDL_snprintf(M->name, sizeof M->name, "%s %d", me->name ? me->name : "morph", t + 1);
      M->first = v0; M->count = node_nv;
      M->def = (size_t)t < me->weights_count ? me->weights[t] : 0;
      M->dpos = SDL_calloc((size_t)node_nv * 3, sizeof(float)); M->dnrm = SDL_calloc((size_t)node_nv * 3, sizeof(float));
      mnode[m->nmorphs] = nodes[k]; mtarget[m->nmorphs] = t; mntg[m->nmorphs] = ntg;
      m->nmorphs++;
    }
    for (cgltf_size p = 0; p < me->primitives_count; p++) {
      cgltf_primitive *pr = &me->primitives[p];
      if (pr->type != cgltf_primitive_type_triangles) continue;
      cgltf_accessor *pa = NULL, *na = NULL, *ta = NULL, *ca = NULL, *ja = NULL, *wa = NULL;
      for (cgltf_size a = 0; a < pr->attributes_count; a++) {
        cgltf_attribute *at = &pr->attributes[a];
        if (at->type == cgltf_attribute_type_position) pa = at->data;
        else if (at->type == cgltf_attribute_type_normal) na = at->data;
        else if (at->type == cgltf_attribute_type_texcoord && at->index == 0) ta = at->data;
        else if (at->type == cgltf_attribute_type_color && at->index == 0) ca = at->data;
        else if (at->type == cgltf_attribute_type_joints && at->index == 0) ja = at->data;
        else if (at->type == cgltf_attribute_type_weights && at->index == 0) wa = at->data;
      }
      if (!pa) continue;
      int n = (int)pa->count;
      for (int v = 0; v < n; v++) {
        float p3[3] = { 0 }, n3[3] = { 0, 1, 0 }, t2[2] = { 0 }, c4[4] = { 1, 1, 1, 1 };
        cgltf_accessor_read_float(pa, (cgltf_size)v, p3, 3);
        if (na) cgltf_accessor_read_float(na, (cgltf_size)v, n3, 3);
        if (ta) cgltf_accessor_read_float(ta, (cgltf_size)v, t2, 2);
        if (ca) cgltf_accessor_read_float(ca, (cgltf_size)v, c4, ca->type == cgltf_type_vec3 ? 3 : 4);
        float *P = &m->pos[(v0 + v) * 3], *N = &m->nrm[(v0 + v) * 3];
        for (int r = 0; r < 3; r++) P[r] = W[r] * p3[0] + W[4 + r] * p3[1] + W[8 + r] * p3[2] + W[12 + r];
        for (int r = 0; r < 3; r++) N[r] = Nm[r * 3] * n3[0] + Nm[r * 3 + 1] * n3[1] + Nm[r * 3 + 2] * n3[2];
        float l = sqrtf(N[0] * N[0] + N[1] * N[1] + N[2] * N[2]);
        if (l > 1e-12f) { N[0] /= l; N[1] /= l; N[2] /= l; }
        m->uv[(v0 + v) * 2] = t2[0]; m->uv[(v0 + v) * 2 + 1] = t2[1];
        for (int r = 0; r < 4; r++) { float c = c4[r] < 0 ? 0 : c4[r] > 1 ? 1 : c4[r]; m->col[(v0 + v) * 4 + r] = (unsigned char)(c * 255 + .5f); }
        for (int t = 0; t < ntg && (size_t)t < pr->targets_count; t++) {   // (its offsets in each target, placed as the vertex is)
          Morph3D *M = &m->morphs[mo0 + t];
          int at = v0 + v - M->first;
          if (at < 0 || at >= M->count || !M->dpos) continue;
          cgltf_morph_target *tg = &pr->targets[t];
          for (cgltf_size a = 0; a < tg->attributes_count; a++) {
            float d3[3] = { 0 };
            cgltf_attribute *ta2 = &tg->attributes[a];
            if (ta2->type != cgltf_attribute_type_position && ta2->type != cgltf_attribute_type_normal) continue;
            cgltf_accessor_read_float(ta2->data, (cgltf_size)v, d3, 3);
            float *D = ta2->type == cgltf_attribute_type_position ? M->dpos : M->dnrm;
            if (!D) continue;
            for (int r = 0; r < 3; r++) D[at * 3 + r] = ta2->type == cgltf_attribute_type_position ? W[r] * d3[0] + W[4 + r] * d3[1] + W[8 + r] * d3[2]
                                                                                            : Nm[r * 3] * d3[0] + Nm[r * 3 + 1] * d3[1] + Nm[r * 3 + 2] * d3[2];
          }
        }
        if (skinned && m->jnt && ja && wa) {       // (else: weights 0, it stays as it is)
          cgltf_uint j4[4] = { 0 };
          float w4[4] = { 0 };
          cgltf_accessor_read_uint(ja, (cgltf_size)v, j4, 4);
          cgltf_accessor_read_float(wa, (cgltf_size)v, w4, 4);
          float sum = w4[0] + w4[1] + w4[2] + w4[3];
          for (int r = 0; r < 4; r++) {
            m->jnt[(v0 + v) * 4 + r] = (unsigned short)(j4[r] < (cgltf_uint)m->njoints ? j4[r] : 0);
            m->wgt[(v0 + v) * 4 + r] = sum > 1e-6f ? w4[r] / sum : 0;
          }
        }
      }
      int cnt = pr->indices ? (int)pr->indices->count : n;
      for (int q = 0; q < cnt; q++) m->idx[i0 + q] = (unsigned)v0 + (unsigned)(pr->indices ? cgltf_accessor_read_index(pr->indices, (cgltf_size)q) : (cgltf_size)q);
      Part3D *pt = &m->parts[m->nparts++];
      *pt = (Part3D){ i0, cnt, { 1, 1, 1, 1 }, -1 };
      if (pr->material) {
        cgltf_material *mt = pr->material;
        if (mt->has_pbr_metallic_roughness) {
          SDL_memcpy(pt->base, mt->pbr_metallic_roughness.base_color_factor, sizeof pt->base);
          cgltf_texture *tx = mt->pbr_metallic_roughness.base_color_texture.texture;
          if (tx && tx->image) pt->tex = mesh3d_image(m, tx->image, dir, d->images);
        }
      }
      v0 += n; i0 += cnt;
    }
  }
  mesh3d_gltf_clips(m, d, skin, mnode, mtarget, mntg);
  SDL_free(mnode); SDL_free(mtarget); SDL_free(mntg);
  SDL_free(nodes);
  cgltf_free(d);
  return true;
}


// FBX (ufbx): every visible mesh, triangulated, each corner a vertex; positions in its node's place (meters, y up);
// materials' base colour and texture (embedded, or a file beside it). A skin: the clusters' bones and their
// ancestors are the joints, a cluster a bind (inverse bind: geometry_to_bone, from the node's place); each
// animation stack sampled at the file's frame rate into keys a joint.
static void ufbx_m16(const ufbx_matrix *u, float o[16]) {
  for (int c = 0; c < 4; c++) { o[c * 4] = (float)u->cols[c].x; o[c * 4 + 1] = (float)u->cols[c].y; o[c * 4 + 2] = (float)u->cols[c].z; o[c * 4 + 3] = c == 3 ? 1.f : 0.f; }
}
static int mesh3d_fbx_texture(Mesh3D *m, ufbx_texture *t, const char *dir) {
  if (!t) return -1;
  int at = (int)t->typed_id;
  if (at < 0 || at >= m->ntex) return -1;
  if (m->tex[at].rgba) return at;
  const unsigned char *data = t->content.data;
  size_t len = t->content.size;
  void *file = NULL;
  if (!data || !len) {                             // (a file: as written, else its name beside the model)
    const char *names[3] = { t->filename.data, t->relative_filename.data, NULL };
    for (int k = 0; k < 2 && !file; k++) {
      const char *nm = names[k];
      if (!nm || !nm[0]) continue;
      file = SDL_LoadFile(nm, &len);
      if (!file) {
        const char *b = nm, *p;
        for (p = nm; *p; p++) if (*p == '/' || *p == '\\') b = p + 1;
        char path[1200];
        SDL_snprintf(path, sizeof path, "%s%s", dir, b);
        file = SDL_LoadFile(path, &len);
      }
    }
    data = file;
  }
  if (data && len) {
    int w = 0, h = 0;
    unsigned char *px = editor_image_decode(data, (int)len, &w, &h);
    if (px) {
      m->tex[at].rgba = SDL_malloc((size_t)w * h * 4);
      if (m->tex[at].rgba) { SDL_memcpy(m->tex[at].rgba, px, (size_t)w * h * 4); m->tex[at].w = w; m->tex[at].h = h; }
      editor_image_free(px);
    }
  }
  SDL_free(file);
  return m->tex[at].rgba ? at : -1;
}
static bool mesh3d_fbx(Mesh3D *m, const char *path, float *fps_out) {
  ufbx_load_opts opt = { 0 };
  opt.target_axes = ufbx_axes_right_handed_y_up;
  opt.target_unit_meters = 1.0f;
  opt.generate_missing_normals = true;
  ufbx_error err;
  ufbx_scene *sc = ufbx_load_file(path, &opt, &err);
  if (!sc) { SDL_snprintf(m->err, sizeof m->err, "FBX: %s", err.description.data); return false; }
  char dir[1024];
  SDL_strlcpy(dir, path, sizeof dir);
  char *sl = SDL_strrchr(dir, '/'), *bs = SDL_strrchr(dir, '\\');
  if (bs > sl) sl = bs;
  if (sl) sl[1] = 0; else dir[0] = 0;
  int nv = 0, np = 0;
  for (size_t i = 0; i < sc->meshes.count; i++) {
    ufbx_mesh *me = sc->meshes.data[i];
    if (!me->instances.count || !me->instances.data[0]->visible) continue;   // (hidden: a rig's helper boxes, say)
    nv += (int)me->num_triangles * 3;
    np += (int)SDL_max(1, me->materials.count);
  }
  if (!nv || !mesh3d_alloc(m, nv, nv)) { ufbx_free_scene(sc); SDL_snprintf(m->err, sizeof m->err, "no triangles in it"); return false; }
  m->parts = SDL_calloc((size_t)np, sizeof *m->parts);
  m->ntex = (int)sc->textures.count;
  m->tex = m->ntex ? SDL_calloc((size_t)m->ntex, sizeof *m->tex) : NULL;
  // the skeleton: every skinned mesh's clusters' bones, and their ancestors (the scene's root left out)
  int nnodes = (int)sc->nodes.count, nb = 0;
  int *jof = SDL_malloc(sizeof(int) * (size_t)(nnodes + 1));
  for (int i = 0; i < nnodes; i++) jof[i] = -1;
  for (size_t i = 0; i < sc->skin_clusters.count; i++) {
    ufbx_node *b = sc->skin_clusters.data[i]->bone_node;
    for (; b && !b->is_root; b = b->parent) jof[b->typed_id] = 0;
    nb++;
  }
  int nj = 0;
  if (nb) {
    for (int depth = 0; depth < 256; depth++) for (int i = 0; i < nnodes; i++)   // (parents first: by depth)
      if (jof[i] == 0 && (int)sc->nodes.data[i]->node_depth == depth) jof[i] = -2 - nj++;
    for (int i = 0; i < nnodes; i++) jof[i] = jof[i] <= -2 ? -2 - jof[i] : -1;
    m->joints = SDL_calloc((size_t)nj, sizeof *m->joints);
    m->bind_joint = SDL_calloc((size_t)nb, sizeof(int));
    m->ibm = SDL_calloc((size_t)nb * 16, sizeof(float));
    m->jnt = SDL_calloc((size_t)m->nv * 4, sizeof(unsigned short));
    m->wgt = SDL_calloc((size_t)m->nv * 4, sizeof(float));
    if (m->joints && m->bind_joint && m->ibm && m->jnt && m->wgt) { m->njoints = nj; m->nbinds = nb; }
    for (int i = 0; i < nnodes && m->njoints; i++) {
      if (jof[i] < 0) continue;
      ufbx_node *nd = sc->nodes.data[i];
      Joint3D *J = &m->joints[jof[i]];
      J->parent = nd->parent && !nd->parent->is_root ? jof[nd->parent->typed_id] : -1;
      SDL_memset(J->base, 0, sizeof J->base); J->base[0] = J->base[5] = J->base[10] = J->base[15] = 1;
      if (J->parent < 0 && nd->parent) ufbx_m16(&nd->parent->node_to_world, J->base);
      ufbx_transform lt = nd->local_transform;
      J->t[0] = (float)lt.translation.x; J->t[1] = (float)lt.translation.y; J->t[2] = (float)lt.translation.z;
      J->r[0] = (float)lt.rotation.x; J->r[1] = (float)lt.rotation.y; J->r[2] = (float)lt.rotation.z; J->r[3] = (float)lt.rotation.w;
      J->s[0] = (float)lt.scale.x; J->s[1] = (float)lt.scale.y; J->s[2] = (float)lt.scale.z;
      SDL_strlcpy(J->name, nd->name.data, sizeof J->name);
    }
  }
  int nmo = 0;                                     // blend shapes: a channel each (its last keyframe's shape, at full weight)
  for (size_t i = 0; i < sc->meshes.count; i++) {
    ufbx_mesh *me = sc->meshes.data[i];
    if (!me->instances.count || !me->instances.data[0]->visible) continue;
    for (size_t d = 0; d < me->blend_deformers.count; d++) nmo += (int)me->blend_deformers.data[d]->channels.count;
  }
  if (nmo > 256) nmo = 256;                        // (mesh3d_weights' share)
  ufbx_blend_channel **mch = nmo ? SDL_calloc((size_t)nmo, sizeof *mch) : NULL;
  if (nmo && mch) { m->morphs = SDL_calloc((size_t)nmo, sizeof *m->morphs); if (!m->morphs) nmo = 0; }
  int v0 = 0;
  for (size_t i = 0; i < sc->meshes.count; i++) {
    ufbx_mesh *me = sc->meshes.data[i];
    if (!me->instances.count || !me->instances.data[0]->visible) continue;
    ufbx_node *nd = me->instances.data[0];       // (its first instance)
    int mesh_v0 = v0, mo0 = m->nmorphs, mon = 0;   // (its morphs: m->morphs[mo0 .. mo0 + mon])
    for (size_t d = 0; m->morphs && d < me->blend_deformers.count; d++) {
      ufbx_blend_deformer *bd = me->blend_deformers.data[d];
      for (size_t c = 0; c < bd->channels.count && m->nmorphs < nmo; c++) {
        ufbx_blend_channel *ch = bd->channels.data[c];
        if (!ch->keyframes.count || !ch->keyframes.data[ch->keyframes.count - 1].shape) continue;
        Morph3D *M = &m->morphs[m->nmorphs];
        SDL_strlcpy(M->name, ch->name.data, sizeof M->name);
        M->first = v0; M->count = (int)me->num_triangles * 3;
        M->dpos = SDL_calloc((size_t)M->count * 3, sizeof(float));
        if (ch->keyframes.data[ch->keyframes.count - 1].shape->normal_offsets.count) M->dnrm = SDL_calloc((size_t)M->count * 3, sizeof(float));
        if (!M->dpos) continue;
        mch[m->nmorphs++] = ch; mon++;
      }
    }
    ufbx_matrix GW = nd->geometry_to_world, GN = ufbx_matrix_for_normals(&GW), WG = ufbx_matrix_invert(&GW);
    ufbx_skin_deformer *sk = m->nbinds && me->skin_deformers.count ? me->skin_deformers.data[0] : NULL;
    if (sk) for (size_t c = 0; c < sk->clusters.count; c++) {   // (its binds: from the node's place to the bone)
      ufbx_skin_cluster *cl = sk->clusters.data[c];
      int b = (int)cl->typed_id;
      if (b < 0 || b >= m->nbinds || !cl->bone_node) continue;
      ufbx_matrix ib = ufbx_matrix_mul(&cl->geometry_to_bone, &WG);
      ufbx_m16(&ib, &m->ibm[b * 16]);
      m->bind_joint[b] = jof[cl->bone_node->typed_id] >= 0 ? jof[cl->bone_node->typed_id] : 0;
    }
    uint32_t tri[64 * 3];
    int nmat = (int)SDL_max(1, me->materials.count);
    for (int mt = 0; mt < nmat; mt++) {          // (a part a material: its faces)
      int first = v0;
      for (size_t f = 0; f < me->faces.count; f++) {
        if (me->materials.count && me->face_material.count && (int)me->face_material.data[f] != mt) continue;
        uint32_t n = ufbx_triangulate_face(tri, SDL_arraysize(tri), me, me->faces.data[f]);
        for (uint32_t k = 0; k < n * 3 && v0 < m->nv; k++, v0++) {
          uint32_t ix = tri[k];
          ufbx_vec3 p = ufbx_get_vertex_vec3(&me->vertex_position, ix), wp = ufbx_transform_position(&GW, p);
          float *P = &m->pos[v0 * 3], *N = &m->nrm[v0 * 3];
          P[0] = (float)wp.x; P[1] = (float)wp.y; P[2] = (float)wp.z;
          if (me->vertex_normal.exists) {
            ufbx_vec3 nn = ufbx_transform_direction(&GN, ufbx_get_vertex_vec3(&me->vertex_normal, ix));
            float l = (float)sqrt(nn.x * nn.x + nn.y * nn.y + nn.z * nn.z);
            if (l > 1e-12f) { N[0] = (float)(nn.x / l); N[1] = (float)(nn.y / l); N[2] = (float)(nn.z / l); } else N[1] = 1;
          } else N[1] = 1;
          if (me->vertex_uv.exists) {
            ufbx_vec2 uv = ufbx_get_vertex_vec2(&me->vertex_uv, ix);
            m->uv[v0 * 2] = (float)uv.x; m->uv[v0 * 2 + 1] = 1 - (float)uv.y;   // (FBX's v goes up)
          }
          if (me->vertex_color.exists) {
            ufbx_vec4 c = ufbx_get_vertex_vec4(&me->vertex_color, ix);
            double cc[4] = { c.x, c.y, c.z, c.w };
            for (int r = 0; r < 4; r++) m->col[v0 * 4 + r] = (unsigned char)(SDL_clamp(cc[r], 0, 1) * 255 + .5);
          }
          m->idx[v0] = (unsigned)v0;
          for (int k = mo0; k < mo0 + mon; k++) {   // (its offsets in each blend shape, placed as the vertex is)
            Morph3D *M = &m->morphs[k];
            ufbx_blend_shape *bs = mch[k]->keyframes.data[mch[k]->keyframes.count - 1].shape;
            uint32_t vx = me->vertex_indices.data[ix];
            int at = v0 - M->first;
            if (at < 0 || at >= M->count) continue;
            ufbx_vec3 d = ufbx_transform_direction(&GW, ufbx_get_blend_shape_vertex_offset(bs, vx));
            M->dpos[at * 3] = (float)d.x; M->dpos[at * 3 + 1] = (float)d.y; M->dpos[at * 3 + 2] = (float)d.z;
            if (M->dnrm) {
              uint32_t oi = ufbx_get_blend_shape_offset_index(bs, vx);
              if (oi != UFBX_NO_INDEX && oi < bs->normal_offsets.count) {
                ufbx_vec3 dn = ufbx_transform_direction(&GN, bs->normal_offsets.data[oi]);
                M->dnrm[at * 3] = (float)dn.x; M->dnrm[at * 3 + 1] = (float)dn.y; M->dnrm[at * 3 + 2] = (float)dn.z;
              }
            }
          }
          if (sk) {                                // (its 4 heaviest weights, normalized)
            uint32_t vx = me->vertex_indices.data[ix];
            if (vx < sk->vertices.count) {
              ufbx_skin_vertex sv = sk->vertices.data[vx];
              float sum = 0;
              int cnt = (int)SDL_min(sv.num_weights, 4);
              for (int r = 0; r < cnt; r++) {
                ufbx_skin_weight w = sk->weights.data[sv.weight_begin + r];
                ufbx_skin_cluster *cl = sk->clusters.data[w.cluster_index];
                m->jnt[v0 * 4 + r] = (unsigned short)cl->typed_id;
                m->wgt[v0 * 4 + r] = (float)w.weight;
                sum += (float)w.weight;
              }
              for (int r = 0; r < cnt; r++) m->wgt[v0 * 4 + r] = sum > 1e-6f ? m->wgt[v0 * 4 + r] / sum : 0;
            }
          }
        }
      }
      if (v0 == first) continue;
      Part3D *pt = &m->parts[m->nparts++];
      *pt = (Part3D){ first, v0 - first, { 1, 1, 1, 1 }, -1 };
      ufbx_material *ma = me->materials.count ? me->materials.data[mt] : NULL;
      if (ma) {
        ufbx_material_map *bc = &ma->pbr.base_color;
        if (bc->has_value) { pt->base[0] = (float)bc->value_vec4.x; pt->base[1] = (float)bc->value_vec4.y; pt->base[2] = (float)bc->value_vec4.z; }
        if (ma->pbr.base_factor.has_value) for (int r = 0; r < 3; r++) pt->base[r] *= (float)ma->pbr.base_factor.value_real;
        ufbx_texture *tx = bc->texture ? bc->texture : ma->fbx.diffuse_color.texture;
        pt->tex = mesh3d_fbx_texture(m, tx, dir);
        if (pt->tex >= 0) pt->base[0] = pt->base[1] = pt->base[2] = 1;   // (a texture: as it is, not dimmed by FBX's 0.8 diffuse)
      }
    }
  }
  m->ni = v0; m->nv = v0;
  for (int k = 0; k < m->nmorphs; k++) if (m->morphs[k].first + m->morphs[k].count > v0) m->morphs[k].count = v0 - m->morphs[k].first;
  // the clips: each animation stack, sampled a frame at a time, every joint
  double fps = sc->settings.frames_per_second > 0 ? sc->settings.frames_per_second : 30;
  *fps_out = (float)fps;
  if ((m->njoints || m->nmorphs) && sc->anim_stacks.count) m->clips = SDL_calloc(sc->anim_stacks.count, sizeof *m->clips);
  for (size_t a = 0; m->clips && a < sc->anim_stacks.count; a++) {
    ufbx_anim_stack *st = sc->anim_stacks.data[a];
    Clip3D *C = &m->clips[m->nclips];
    C->src = -1;
    SDL_strlcpy(C->name, st->name.length ? st->name.data : "clip", sizeof C->name);
    double dur = st->time_end - st->time_begin;
    int keys = (int)SDL_min(SDL_floor(dur * fps + 0.5) + 1, 100000);
    if (keys < 1) keys = 1;
    C->chan = SDL_calloc((size_t)m->njoints * 3 + (size_t)m->nmorphs + 1, sizeof *C->chan);
    if (!C->chan) continue;
    C->duration = (float)((keys - 1) / fps);
    for (int i = 0; i < nnodes; i++) {
      if (jof[i] < 0) continue;
      int j = jof[i];
      Chan3D *K = &C->chan[C->nchan];
      for (int path = 0; path < 3; path++) {
        K[path].joint = j; K[path].path = path; K[path].n = keys;
        K[path].times = SDL_malloc(sizeof(float) * (size_t)keys);
        K[path].vals = SDL_malloc(sizeof(float) * (size_t)keys * (path == 1 ? 4 : 3));
      }
      if (!K[0].vals || !K[1].vals || !K[2].vals || !K[0].times || !K[1].times || !K[2].times) {
        for (int path = 0; path < 3; path++) { SDL_free(K[path].times); SDL_free(K[path].vals); }
        continue;
      }
      for (int k = 0; k < keys; k++) {
        ufbx_transform tr = ufbx_evaluate_transform(st->anim, sc->nodes.data[i], st->time_begin + k / fps);
        for (int path = 0; path < 3; path++) K[path].times[k] = (float)(k / fps);
        K[0].vals[k * 3] = (float)tr.translation.x; K[0].vals[k * 3 + 1] = (float)tr.translation.y; K[0].vals[k * 3 + 2] = (float)tr.translation.z;
        K[1].vals[k * 4] = (float)tr.rotation.x; K[1].vals[k * 4 + 1] = (float)tr.rotation.y; K[1].vals[k * 4 + 2] = (float)tr.rotation.z; K[1].vals[k * 4 + 3] = (float)tr.rotation.w;
        K[2].vals[k * 3] = (float)tr.scale.x; K[2].vals[k * 3 + 1] = (float)tr.scale.y; K[2].vals[k * 3 + 2] = (float)tr.scale.z;
      }
      C->nchan += 3;
    }
    for (int k = 0; k < m->nmorphs; k++) {         // (each blend shape's weight, a frame at a time)
      Chan3D *K = &C->chan[C->nchan];
      K->joint = k; K->path = 3; K->n = keys;
      K->times = SDL_malloc(sizeof(float) * (size_t)keys); K->vals = SDL_malloc(sizeof(float) * (size_t)keys);
      if (!K->times || !K->vals) { SDL_free(K->times); SDL_free(K->vals); K->times = K->vals = NULL; continue; }
      for (int f = 0; f < keys; f++) { K->times[f] = (float)(f / fps); K->vals[f] = (float)ufbx_evaluate_blend_weight(st->anim, mch[k], st->time_begin + f / fps); }
      C->nchan++;
    }
    m->nclips++;
  }
  SDL_free(mch);
  SDL_free(jof);
  ufbx_free_scene(sc);
  return true;
}


static void m4_mul_cm(const float a[16], const float b[16], float o[16]);
static void m4_identity_cm(float o[16]) { SDL_memset(o, 0, sizeof(float) * 16); o[0] = o[5] = o[10] = o[15] = 1; }
// MagicaVoxel (.vox, our reader: ogt_vox is C++): the models (SIZE, XYZI), the palette (RGBA), the scene
// graph (nTRN: translation and rotation of its first frame, nGRP, nSHP; hidden nodes and layers left out).
// A quad a voxel face with no voxel beside it (watertight; greedy meshing: later); z up turned y up, a voxel
// 10 cm, the palette as vertex colours; stood on y = 0, centred on x and z.
typedef struct { const unsigned char *p, *end; bool bad; } VoxIn;
static int vox_i32(VoxIn *in) { if (in->end - in->p < 4) { in->bad = true; in->p = in->end; return 0; } int v = (int)(in->p[0] | in->p[1] << 8 | in->p[2] << 16 | (unsigned)in->p[3] << 24); in->p += 4; return v; }
static void vox_str(VoxIn *in, char *out, int cap) {
  int n = vox_i32(in);
  if (n < 0 || in->end - in->p < n) { in->bad = true; in->p = in->end; if (cap) out[0] = 0; return; }
  if (cap) { int k = SDL_min(n, cap - 1); SDL_memcpy(out, in->p, (size_t)k); out[k] = 0; }
  in->p += n;
}
// a dict: the values of up to 3 keys asked for ("_t", "_r", "_hidden")
static void vox_dict(VoxIn *in, const char **keys, char (*vals)[64], int nk) {
  for (int k = 0; k < nk; k++) vals[k][0] = 0;
  int n = vox_i32(in);
  for (int i = 0; i < n && !in->bad; i++) {
    char key[64], val[64];
    vox_str(in, key, sizeof key); vox_str(in, val, sizeof val);
    for (int k = 0; k < nk; k++) if (!strcmp(key, keys[k])) SDL_strlcpy(vals[k], val, 64);
  }
}
typedef struct { int sx, sy, sz; unsigned char *v; } VoxModel;
typedef struct { int type, child, nkids, *kids, layer, model[8], nmodels; bool hidden; float M[16]; } VoxNode;   // type 1 trn, 2 grp, 3 shp
typedef struct { VoxModel *models; int nmodels; VoxNode *nodes; int nnodes; bool layer_hidden[256]; unsigned char pal[256][4]; Mesh3D *m; int nv, ni, nv0, ni0; bool count; } Vox;
static void vox_rotation(int r, float R[9]) {      // (_r: a row's 1 at bits 0-1, 2-3; the third the one left; signs at bits 4, 5, 6)
  int i0 = r & 3, i1 = (r >> 2) & 3, i2 = 3 - i0 - i1;
  SDL_memset(R, 0, sizeof(float) * 9);
  if (i0 > 2 || i1 > 2 || i2 < 0 || i2 > 2 || i0 == i1) { R[0] = R[4] = R[8] = 1; return; }
  R[0 * 3 + i0] = (r & 16) ? -1.f : 1.f; R[1 * 3 + i1] = (r & 32) ? -1.f : 1.f; R[2 * 3 + i2] = (r & 64) ? -1.f : 1.f;   // (rows)
}
static void vox_emit(Vox *X, const VoxModel *md, const float W[16]) {
  static const int D[6][3] = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } };
  float det = W[0] * (W[5] * W[10] - W[9] * W[6]) - W[4] * (W[1] * W[10] - W[9] * W[2]) + W[8] * (W[1] * W[6] - W[5] * W[2]);
  int hx = md->sx / 2, hy = md->sy / 2, hz = md->sz / 2;   // (it turns round its middle)
  for (int z = 0; z < md->sz; z++) for (int y = 0; y < md->sy; y++) for (int x = 0; x < md->sx; x++) {
    int c = md->v[x + y * md->sx + z * md->sx * md->sy];
    if (!c) continue;
    for (int f = 0; f < 6; f++) {
      int nx = x + D[f][0], ny = y + D[f][1], nz = z + D[f][2];
      if (nx >= 0 && ny >= 0 && nz >= 0 && nx < md->sx && ny < md->sy && nz < md->sz && md->v[nx + ny * md->sx + nz * md->sx * md->sy]) continue;
      if (X->count) { X->nv += 4; X->ni += 6; continue; }
      Mesh3D *m = X->m;
      int b = X->nv;
      // the face's corners, counter-clockwise from outside: u, v span it (u x v = its normal)
      int a = f / 2, s = D[f][a];
      int ua = (a + 1) % 3, va = (a + 2) % 3;
      float o[3] = { (float)(x - hx), (float)(y - hy), (float)(z - hz) };
      if (s > 0) o[a] += 1;
      float cs[4][3];
      for (int k = 0; k < 4; k++) {
        float uu = (k == 1 || k == 2) ? 1.f : 0.f, vv = (k >= 2) ? 1.f : 0.f;
        if (s < 0) { float t = uu; uu = vv; vv = t; }   // (the far side: the other way round)
        cs[k][0] = o[0]; cs[k][1] = o[1]; cs[k][2] = o[2];
        cs[k][ua] += uu; cs[k][va] += vv;
      }
      float n3[3] = { (float)D[f][0], (float)D[f][1], (float)D[f][2] }, wn[3];
      for (int r = 0; r < 3; r++) wn[r] = W[r] * n3[0] + W[4 + r] * n3[1] + W[8 + r] * n3[2];
      for (int k = 0; k < 4; k++) {
        float q[3];
        for (int r = 0; r < 3; r++) q[r] = W[r] * cs[k][0] + W[4 + r] * cs[k][1] + W[8 + r] * cs[k][2] + W[12 + r];
        float *P = &m->pos[(b + k) * 3], *N = &m->nrm[(b + k) * 3];
        P[0] = q[0] * 0.1f; P[1] = q[2] * 0.1f; P[2] = -q[1] * 0.1f;   // (z up -> y up: x, z, -y; 10 cm)
        N[0] = wn[0]; N[1] = wn[2]; N[2] = -wn[1];
        SDL_memcpy(&m->col[(b + k) * 4], X->pal[c - 1], 4);
        m->col[(b + k) * 4 + 3] = 255;
      }
      unsigned *ix = &m->idx[X->ni], B = (unsigned)b;
      if (det >= 0) { ix[0] = B; ix[1] = B + 1; ix[2] = B + 2; ix[3] = B; ix[4] = B + 2; ix[5] = B + 3; }
      else { ix[0] = B; ix[1] = B + 2; ix[2] = B + 1; ix[3] = B; ix[4] = B + 3; ix[5] = B + 2; }   // (a mirroring turn: the other way round)
      X->nv += 4; X->ni += 6;
    }
  }
}
static void vox_walk(Vox *X, int id, const float parent[16], int depth) {
  if (id < 0 || id >= X->nnodes || depth > 64) return;
  VoxNode *N = &X->nodes[id];
  if (N->hidden || (N->layer >= 0 && N->layer < 256 && X->layer_hidden[N->layer])) return;
  float W[16];
  m4_mul_cm(parent, N->M, W);
  if (N->type == 1) vox_walk(X, N->child, W, depth + 1);
  else if (N->type == 2) for (int k = 0; k < N->nkids; k++) vox_walk(X, N->kids[k], W, depth + 1);
  else if (N->type == 3) for (int k = 0; k < N->nmodels; k++) if (N->model[k] >= 0 && N->model[k] < X->nmodels) vox_emit(X, &X->models[N->model[k]], W);
}
static bool mesh3d_vox(Mesh3D *m, const char *path) {
  size_t len = 0;
  unsigned char *buf = SDL_LoadFile(path, &len);
  if (!buf) { SDL_snprintf(m->err, sizeof m->err, "can't read it"); return false; }
  Vox X;
  SDL_zero(X);
  X.m = m;
  for (int i = 0; i < 256; i++) { X.pal[i][0] = X.pal[i][1] = X.pal[i][2] = (unsigned char)(255 - i); X.pal[i][3] = 255; }   // (no RGBA chunk: greys)
  VoxIn in = { buf, buf + len, false };
  bool ok = len >= 8 && !SDL_memcmp(buf, "VOX ", 4);
  in.p += 8;
  int sx = 0, sy = 0, sz = 0;
  while (ok && !in.bad && in.end - in.p >= 12) {
    char id[5] = { 0 };
    SDL_memcpy(id, in.p, 4); in.p += 4;
    int n = vox_i32(&in); vox_i32(&in);            // (its content's size; its children's: read as they come)
    if (n < 0 || in.end - in.p < n) break;
    VoxIn c = { in.p, in.p + n, false };
    if (!strcmp(id, "MAIN")) continue;             // (its children follow)
    in.p += n;
    if (!strcmp(id, "SIZE")) { sx = vox_i32(&c); sy = vox_i32(&c); sz = vox_i32(&c); }
    else if (!strcmp(id, "XYZI") && sx > 0 && sy > 0 && sz > 0 && sx <= 2048 && sy <= 2048 && sz <= 2048) {
      VoxModel *mm = SDL_realloc(X.models, sizeof *mm * (size_t)(X.nmodels + 1));
      if (!mm) break;
      X.models = mm;
      VoxModel *md = &X.models[X.nmodels];
      md->sx = sx; md->sy = sy; md->sz = sz;
      md->v = SDL_calloc((size_t)sx * sy * sz, 1);
      if (!md->v) break;
      X.nmodels++;
      int cnt = vox_i32(&c);
      for (int i = 0; i < cnt && c.end - c.p >= 4; i++, c.p += 4)
        if (c.p[0] < sx && c.p[1] < sy && c.p[2] < sz) md->v[c.p[0] + c.p[1] * sx + c.p[2] * sx * sy] = c.p[3];
    } else if (!strcmp(id, "RGBA")) {
      for (int i = 0; i < 255 && c.end - c.p >= 4; i++, c.p += 4) SDL_memcpy(X.pal[i], c.p, 4);   // (index i + 1's colour)
    } else if (!strcmp(id, "nTRN") || !strcmp(id, "nGRP") || !strcmp(id, "nSHP") || !strcmp(id, "LAYR")) {
      int nid = vox_i32(&c);
      static const char *K[3] = { "_hidden", "_t", "_r" };
      char V[3][64];
      vox_dict(&c, K, V, 3);
      if (!strcmp(id, "LAYR")) { if (nid >= 0 && nid < 256) X.layer_hidden[nid] = V[0][0] == '1'; continue; }
      if (nid < 0 || nid > 65535) continue;
      if (nid >= X.nnodes) {
        VoxNode *nn = SDL_realloc(X.nodes, sizeof *nn * (size_t)(nid + 1));
        if (!nn) break;
        SDL_memset(nn + X.nnodes, 0, sizeof *nn * (size_t)(nid + 1 - X.nnodes));
        X.nodes = nn; X.nnodes = nid + 1;
      }
      VoxNode *N = &X.nodes[nid];
      N->hidden = V[0][0] == '1'; N->layer = -1;
      m4_identity_cm(N->M);
      if (!strcmp(id, "nTRN")) {
        N->type = 1;
        N->child = vox_i32(&c); vox_i32(&c); N->layer = vox_i32(&c);
        int frames = vox_i32(&c);
        if (frames > 0) {
          vox_dict(&c, K, V, 3);
          int t[3] = { 0, 0, 0 };
          if (V[1][0]) SDL_sscanf(V[1], "%d %d %d", &t[0], &t[1], &t[2]);
          float R[9];
          vox_rotation(V[2][0] ? SDL_atoi(V[2]) : 4, R);   // (4: none, rows x, y, z)
          for (int r = 0; r < 3; r++) for (int col = 0; col < 3; col++) N->M[col * 4 + r] = R[r * 3 + col];
          N->M[12] = (float)t[0]; N->M[13] = (float)t[1]; N->M[14] = (float)t[2];
        }
      } else if (!strcmp(id, "nGRP")) {
        N->type = 2;
        int k = vox_i32(&c);
        if (k > 0 && k < 65536) { N->kids = SDL_calloc((size_t)k, sizeof(int)); if (N->kids) { N->nkids = k; for (int i = 0; i < k; i++) N->kids[i] = vox_i32(&c); } }
      } else {
        N->type = 3;
        int k = vox_i32(&c);
        for (int i = 0; i < k && !c.bad; i++) { int mid = vox_i32(&c); char d0[3][64]; vox_dict(&c, K, d0, 0); if (N->nmodels < 8) N->model[N->nmodels++] = mid; }
      }
    }
  }
  SDL_free(buf);
  if (!ok || !X.nmodels) SDL_snprintf(m->err, sizeof m->err, ok ? "no voxels in it" : "not a MagicaVoxel file");
  ok = ok && X.nmodels;
  float I[16];
  m4_identity_cm(I);
  for (int pass = 0; ok && pass < 2; pass++) {    // (count, then fill)
    X.count = pass == 0; X.nv = X.ni = 0;
    if (pass == 1 && !mesh3d_alloc(m, X.nv0, X.ni0)) { ok = false; break; }
    if (X.nnodes && X.nodes[0].type == 1) vox_walk(&X, 0, I, 0);
    else for (int k = 0; k < X.nmodels; k++) vox_emit(&X, &X.models[k], I);   // (no scene: each model at the middle)
    if (pass == 0) { X.nv0 = X.nv; X.ni0 = X.ni; if (!X.nv) { SDL_snprintf(m->err, sizeof m->err, "no voxels shown"); ok = false; } }
  }
  if (ok) {
    mesh3d_one_part(m);
    mesh3d_bounds(m);
    float dx = (m->bmin[0] + m->bmax[0]) / 2, dy = m->bmin[1], dz = (m->bmin[2] + m->bmax[2]) / 2;
    for (int v = 0; v < m->nv; v++) { m->pos[v * 3] -= dx; m->pos[v * 3 + 1] -= dy; m->pos[v * 3 + 2] -= dz; }
  }
  for (int k = 0; k < X.nmodels; k++) SDL_free(X.models[k].v);
  for (int k = 0; k < X.nnodes; k++) SDL_free(X.nodes[k].kids);
  SDL_free(X.models); SDL_free(X.nodes);
  return ok;
}

// sub-clips: "<file>@animlist.txt", and "animlist.txt" beside it; a line "frame: 66-85 Run (Loop)": frames of the
// first clip (fps: the file's; glTF has none: 30)
static void mesh3d_animlist(Mesh3D *m, const char *file, float fps) {
  if (!m->nclips || (!m->njoints && !m->nmorphs)) return;
  char dir[1024], lists[2][1100];
  SDL_strlcpy(dir, file, sizeof dir);
  char *sl = SDL_strrchr(dir, '/'), *bs = SDL_strrchr(dir, '\\');
  if (bs > sl) sl = bs;
  if (sl) sl[1] = 0; else dir[0] = 0;
  SDL_snprintf(lists[0], sizeof lists[0], "%s@animlist.txt", file);
  SDL_snprintf(lists[1], sizeof lists[1], "%sanimlist.txt", dir);
  for (int f = 0; f < 2; f++) {
    size_t len = 0;
    char *txt = SDL_LoadFile(lists[f], &len);
    if (!txt) continue;
    for (char *line = txt; line && *line; ) {
      char *next = SDL_strchr(line, '\n');
      if (next) *next++ = 0;
      int a = 0, b = 0, used = 0;
      char *fr = SDL_strstr(line, "frame:");
      if (fr && SDL_sscanf(fr + 6, " %d - %d %n", &a, &b, &used) >= 2 && used > 0 && b >= a) {
        char name[64];
        SDL_strlcpy(name, fr + 6 + used, sizeof name);
        size_t n = SDL_strlen(name);
        while (n && (name[n - 1] == '\r' || name[n - 1] == ' ' || name[n - 1] == '\t')) name[--n] = 0;
        bool loops = false;
        if (n > 7 && !SDL_strcasecmp(name + n - 6, "(loop)")) { loops = true; name[n - 6] = 0; n -= 6; while (n && name[n - 1] == ' ') name[--n] = 0; }
        bool dup = !name[0];
        for (int c = 0; c < m->nclips && !dup; c++) if (!strcmp(m->clips[c].name, name)) dup = true;
        if (!dup && a == 0 && b / fps >= m->clips[0].duration - 1e-3f && m->clips[0].src < 0) dup = true;   // (the whole take again)
        if (!dup) {
          Clip3D *cl = SDL_realloc(m->clips, sizeof *cl * (size_t)(m->nclips + 1));
          if (cl) {
            m->clips = cl;
            Clip3D *C = &m->clips[m->nclips++];
            SDL_zerop(C);
            SDL_strlcpy(C->name, name, sizeof C->name);
            C->src = 0; C->start = a / fps; C->duration = (b - a) / fps; C->loops = loops;
          }
        }
      }
      line = next;
    }
    SDL_free(txt);
  }
}

static Mesh3D meshes3d[64];
static int nmeshes3d;
static Mesh3D *mesh3d_get(Viewer *V, const char *name) {
  if (!name || !name[0]) return NULL;
  static const char *BUILTIN[] = { "cube", "plane", "sphere", "grass", "tree", "pine", "bush", "grid", "gridaxis", "cylinder", "cone", "capsule", "triangle", "line" };   // (from "grass" on: "name:N", another of the kind)
  int bk = -1;
  unsigned variant = 1;
  for (int k = 0; k < (int)SDL_arraysize(BUILTIN) && bk < 0; k++) {
    size_t n = SDL_strlen(BUILTIN[k]);
    if (!SDL_strncmp(name, BUILTIN[k], n) && (!name[n] || (name[n] == ':' && k >= 3 && k <= 6))) { bk = k; if (name[n]) variant = (unsigned)SDL_clamp(SDL_atoi(name + n + 1), 1, 1000); }
  }
  bool builtin = bk >= 0;
  char file[1024];
  if (builtin) SDL_snprintf(file, sizeof file, "builtin:%s", name);
  else if (!SDL_strncmp(name, "file:", 5)) SDL_strlcpy(file, name + 5, sizeof file);   // (a file anywhere: the model viewer's)
  else tex_file(V, name, file, sizeof file);
  Mesh3D *m = NULL;
  for (int i = 0; i < nmeshes3d && !m; i++) if (!strcmp(meshes3d[i].file, file)) m = &meshes3d[i];
  if (!m) {
    if (nmeshes3d == (int)SDL_arraysize(meshes3d)) { for (int i = 0; i < nmeshes3d; i++) mesh3d_free(&meshes3d[i]); nmeshes3d = 0; }
    m = &meshes3d[nmeshes3d++];
    SDL_zerop(m);
    SDL_strlcpy(m->file, file, sizeof m->file);
    m->mtime = -1;                                 // (not looked at yet: a missing file says so too)
  }
  if (builtin) {
    if (!m->ok) {
      if (bk == 0) mesh3d_cube(m); else if (bk == 1) mesh3d_plane(m); else if (bk == 2) mesh3d_sphere(m);
      else if (bk == 3) mesh3d_grass(m, variant); else if (bk >= 9) mesh3d_shape(m, bk - 9); else if (bk >= 7) mesh3d_gridlines(m, bk == 8); else mesh3d_plant(m, bk - 4, variant);
      m->ok = m->nv > 0; mesh3d_bounds(m);
    }
    return m->ok ? m : NULL;
  }
  Uint64 now = SDL_GetTicks();
  if (!m->checked || now - m->checked > 1000) {    // its file changed (or appeared): read it again
    m->checked = now;
    SDL_PathInfo pi;
    SDL_Time t = SDL_GetPathInfo(file, &pi) ? pi.modify_time : 0;
    if (t != m->mtime) {
      m->mtime = t;
      mesh3d_free(m);
      m->err[0] = 0;
      size_t n = SDL_strlen(file);
      bool gl = (n > 5 && !SDL_strcasecmp(file + n - 5, ".gltf")) || (n > 4 && !SDL_strcasecmp(file + n - 4, ".glb"));
      bool fbx = n > 4 && !SDL_strcasecmp(file + n - 4, ".fbx"), vox = n > 4 && !SDL_strcasecmp(file + n - 4, ".vox");
      float fps = 30;
      if (!t) SDL_snprintf(m->err, sizeof m->err, "no such file");
      else if (gl) m->ok = mesh3d_gltf(m, file);
      else if (fbx) m->ok = mesh3d_fbx(m, file, &fps);
      else if (vox) m->ok = mesh3d_vox(m, file);
      else SDL_snprintf(m->err, sizeof m->err, "not a model it reads (.gltf, .glb, .fbx, .vox)");
      if (m->ok) mesh3d_animlist(m, file, fps);
      if (!m->ok) mesh3d_free(m);
      else mesh3d_bounds(m);
    }
  }
  return m->ok ? m : NULL;
}

// skinning (phase 5): a clip sampled at t, the joints' world matrices, the vertices moved by them
static void q_slerp(const float a[4], const float b0[4], float t, float o[4]) {
  float b[4] = { b0[0], b0[1], b0[2], b0[3] }, d = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
  if (d < 0) { d = -d; for (int k = 0; k < 4; k++) b[k] = -b[k]; }   // (the short way round)
  float ka = 1 - t, kb = t;
  if (d < 0.9995f) { float th = acosf(d), s = sinf(th); ka = sinf((1 - t) * th) / s; kb = sinf(t * th) / s; }
  float l = 0;
  for (int k = 0; k < 4; k++) { o[k] = a[k] * ka + b[k] * kb; l += o[k] * o[k]; }
  l = l > 1e-12f ? 1 / sqrtf(l) : 1;
  for (int k = 0; k < 4; k++) o[k] *= l;
}
static void m4_from_trs(const float t[3], const float q[4], const float s[3], float o[16]) {
  float x = q[0], y = q[1], z = q[2], w = q[3];
  float R[9] = { 1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w),     // (columns)
                 2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w),
                 2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y) };
  float m[16] = { R[0] * s[0], R[1] * s[0], R[2] * s[0], 0, R[3] * s[1], R[4] * s[1], R[5] * s[1], 0,
                  R[6] * s[2], R[7] * s[2], R[8] * s[2], 0, t[0], t[1], t[2], 1 };
  SDL_memcpy(o, m, sizeof m);
}
static void m4_mul_cm(const float a[16], const float b[16], float o[16]) {   // (column-major a * b; raster3d.h's m4_mul comes later)
  float r[16];
  for (int c = 0; c < 4; c++) for (int k = 0; k < 4; k++)
    r[c * 4 + k] = a[k] * b[c * 4] + a[4 + k] * b[c * 4 + 1] + a[8 + k] * b[c * 4 + 2] + a[12 + k] * b[c * 4 + 3];
  SDL_memcpy(o, r, sizeof r);
}
static void chan_sample(const Chan3D *K, float t, float *out) {
  int comp = K->path == 1 ? 4 : K->path == 3 ? 1 : 3;
  if (t <= K->times[0] || K->n == 1) { SDL_memcpy(out, K->vals, sizeof(float) * comp); return; }
  if (t >= K->times[K->n - 1]) { SDL_memcpy(out, &K->vals[(K->n - 1) * comp], sizeof(float) * comp); return; }
  int k = 0;
  while (k + 1 < K->n && K->times[k + 1] <= t) k++;
  const float *a = &K->vals[k * comp], *b = &K->vals[(k + 1) * comp];
  float span = K->times[k + 1] - K->times[k], u = span > 1e-9f ? (t - K->times[k]) / span : 0;
  if (K->step) u = 0;
  if (comp == 4) q_slerp(a, b, u, out);
  else for (int c = 0; c < 3; c++) out[c] = a[c] + (b[c] - a[c]) * u;
}
// the skin's matrices (a bind's joint in the world * its inverse bind; mats: 16 floats a bind) for clip (0-based; -1: the rest pose) at t seconds
// a second clip blended over the first (animator.blend = { clip, t, w }: w 0 the first alone, 1 the second):
// set before a pose (pose3d_get, mesh3d_pose, mesh3d_weights), cleared after (w = 0)
static struct { int clip; float t, w; bool loop; } pose_blend;
static const Clip3D *clip_at(const Mesh3D *m, int clip, float *t, bool loop) {   // (a sub-clip: its source, its time there)
  if (clip < 0 || clip >= m->nclips) return NULL;
  const Clip3D *C = &m->clips[clip];
  if (loop && C->duration > 0) { *t = SDL_fmodf(*t, C->duration); if (*t < 0) *t += C->duration; }
  if (C->src >= 0 && C->src < m->nclips) { *t = C->start + SDL_clamp(*t, 0, C->duration); C = &m->clips[C->src]; }
  return C;
}
static void pose_sample(const Mesh3D *m, int clip, float t, bool loop, float *T, unsigned char *moved) {   // T: the rest pose in, the clip's out (10 floats a joint)
  int n = m->njoints;
  for (int j = 0; j < n; j++) { SDL_memcpy(&T[j * 10], m->joints[j].t, 12); SDL_memcpy(&T[j * 10 + 3], m->joints[j].r, 16); SDL_memcpy(&T[j * 10 + 7], m->joints[j].s, 12); }
  const Clip3D *C = clip_at(m, clip, &t, loop);
  for (int k = 0; C && k < C->nchan; k++) {
    const Chan3D *K = &C->chan[k];
    if (K->path == 3 || K->joint < 0 || K->joint >= n) continue;   // (a morph's: mesh3d_weights)
    chan_sample(K, t, &T[K->joint * 10 + (K->path == 0 ? 0 : K->path == 1 ? 3 : 7)]);
    moved[K->joint] = 1;
  }
}
static bool mesh3d_pose(const Mesh3D *m, int clip, float t, bool loop, float *mats, float *world) {   // world: the joints' (16 floats each; NULL: not wanted)
  if (!m->njoints) return false;
  int n = m->njoints;
  float *T = SDL_malloc(sizeof(float) * 10 * n), *G = SDL_malloc(sizeof(float) * 16 * n);
  unsigned char *done = SDL_calloc((size_t)n, 1), *moved = SDL_calloc((size_t)n, 1);
  if (!T || !G || !done || !moved) { SDL_free(T); SDL_free(G); SDL_free(done); SDL_free(moved); return false; }
  pose_sample(m, clip, t, loop, T, moved);
  if (pose_blend.w > 0) {                          // (a second clip: translation and scale mixed, rotation slerped)
    float *T2 = SDL_malloc(sizeof(float) * 10 * n);
    if (T2) {
      pose_sample(m, pose_blend.clip, pose_blend.t, pose_blend.loop, T2, moved);
      float w = SDL_min(pose_blend.w, 1);
      for (int j = 0; j < n; j++) {
        float *a = &T[j * 10], *b = &T2[j * 10];
        for (int k = 0; k < 3; k++) { a[k] += (b[k] - a[k]) * w; a[7 + k] += (b[7 + k] - a[7 + k]) * w; }
        float q[4];
        q_slerp(&a[3], &b[3], w, q);
        SDL_memcpy(&a[3], q, 16);
      }
      SDL_free(T2);
    }
  }
  for (int pass = 0; pass < n; pass++) {           // (parents first, in any order they come)
    bool any = false;
    for (int j = 0; j < n; j++) {
      if (done[j]) continue;
      int p = m->joints[j].parent;
      if (p >= 0 && !done[p]) { any = true; continue; }
      float L[16];
      if (m->joints[j].has_matrix && !(moved && moved[j])) SDL_memcpy(L, m->joints[j].matrix, sizeof L);
      else m4_from_trs(&T[j * 10], &T[j * 10 + 3], &T[j * 10 + 7], L);
      m4_mul_cm(p >= 0 ? &G[p * 16] : m->joints[j].base, L, &G[j * 16]);
      done[j] = 1;
    }
    if (!any) break;
  }
  if (world) SDL_memcpy(world, G, sizeof(float) * 16 * (size_t)n);
  for (int b = 0; b < m->nbinds; b++) m4_mul_cm(&G[SDL_clamp(m->bind_joint[b], 0, n - 1) * 16], &m->ibm[b * 16], &mats[b * 16]);
  SDL_free(T); SDL_free(G); SDL_free(done); SDL_free(moved);
  return true;
}
// its vertices moved by the skin's matrices (4 joints each, weighted); none of them: as they are
// the blend shapes' weights for clip at t (their defaults, then the clip's, then `set`: NaN leaves one as it is)
static void weights_sample(const Mesh3D *m, int clip, float t, bool loop, float *w) {
  for (int k = 0; k < m->nmorphs; k++) w[k] = m->morphs[k].def;
  const Clip3D *C = clip_at(m, clip, &t, loop);
  for (int k = 0; C && k < C->nchan; k++) if (C->chan[k].path == 3 && C->chan[k].joint >= 0 && C->chan[k].joint < m->nmorphs) chan_sample(&C->chan[k], t, &w[C->chan[k].joint]);
}
static void mesh3d_weights(const Mesh3D *m, int clip, float t, bool loop, const float *set, float *w) {
  weights_sample(m, clip, t, loop, w);
  if (pose_blend.w > 0) {                          // (the second clip's: mixed in)
    float w2[256];
    weights_sample(m, pose_blend.clip, pose_blend.t, pose_blend.loop, w2);
    float k2 = SDL_min(pose_blend.w, 1);
    for (int k = 0; k < m->nmorphs && k < 256; k++) w[k] += (w2[k] - w[k]) * k2;
  }
  if (set) for (int k = 0; k < m->nmorphs; k++) if (set[k] == set[k]) w[k] = set[k];
}
// the blend shapes into pos, nrm (copies of the base's): weighted offsets
static void mesh3d_morph(const Mesh3D *m, const float *w, float *pos, float *nrm) {
  for (int k = 0; k < m->nmorphs; k++) {
    const Morph3D *M = &m->morphs[k];
    if (w[k] == 0 || M->first < 0 || M->first + M->count > m->nv) continue;
    for (int i = 0; i < M->count * 3; i++) pos[M->first * 3 + i] += M->dpos[i] * w[k];
    if (M->dnrm) for (int i = 0; i < M->count * 3; i++) nrm[M->first * 3 + i] += M->dnrm[i] * w[k];
  }
}
static int mesh3d_morph_index(const Mesh3D *m, const char *name) {   // by its name, or what's after its last '_' ("Face01_mouthO": "mouthO")
  for (int k = 0; k < m->nmorphs; k++) {
    const char *n = m->morphs[k].name, *u = SDL_strrchr(n, '_');
    if (!strcmp(n, name) || (u && !strcmp(u + 1, name))) return k;
  }
  return -1;
}
static void mesh3d_skin(const Mesh3D *m, const float *mats, const float *src_pos, const float *src_nrm, float *pos, float *nrm) {
  for (int i = 0; i < m->nv; i++) {
    float P[3] = { src_pos[i * 3], src_pos[i * 3 + 1], src_pos[i * 3 + 2] }, N[3] = { src_nrm[i * 3], src_nrm[i * 3 + 1], src_nrm[i * 3 + 2] };   // (copies: src may be pos)
    const float *w = &m->wgt[i * 4];
    const unsigned short *j = &m->jnt[i * 4];
    float M[12] = { 0 }, sum = w[0] + w[1] + w[2] + w[3];
    if (sum < 1e-6f) {                             // (no weights: as it is; its normal whole, a blend shape may have moved it)
      float l = sqrtf(N[0] * N[0] + N[1] * N[1] + N[2] * N[2]);
      if (l > 1e-12f) { N[0] /= l; N[1] /= l; N[2] /= l; }
      SDL_memcpy(&pos[i * 3], P, 12); SDL_memcpy(&nrm[i * 3], N, 12); continue;
    }
    for (int k = 0; k < 4; k++) {
      if (w[k] == 0) continue;
      const float *A = &mats[j[k] * 16];
      for (int c = 0; c < 3; c++) for (int r = 0; r < 3; r++) M[c * 3 + r] += A[c * 4 + r] * w[k];
      for (int r = 0; r < 3; r++) M[9 + r] += A[12 + r] * w[k];
    }
    float *o = &pos[i * 3], *on = &nrm[i * 3];
    for (int r = 0; r < 3; r++) o[r] = M[r] * P[0] + M[3 + r] * P[1] + M[6 + r] * P[2] + M[9 + r];
    for (int r = 0; r < 3; r++) on[r] = M[r] * N[0] + M[3 + r] * N[1] + M[6 + r] * N[2];   // (no shear in a skeleton: the matrix itself, normalized)
    float l = sqrtf(on[0] * on[0] + on[1] * on[1] + on[2] * on[2]);
    if (l > 1e-12f) for (int r = 0; r < 3; r++) on[r] /= l;
  }
}
static int mesh3d_clip(const Mesh3D *m, const char *name) {   // a clip by name (or "1", "2": its number) -> 0-based | -1
  if (!name) return -1;
  for (int c = 0; c < m->nclips; c++) if (!strcmp(m->clips[c].name, name)) return c;
  int k = SDL_atoi(name);
  return k >= 1 && k <= m->nclips ? k - 1 : -1;
}
// posed copies (skin and / or blend shapes): one a key (a node's path, a lite view), the base's arrays shared but pos and nrm; drawn
// like any mesh (the GPU's copy is read again when its version moves: render3d.h)
typedef struct { char key[300]; Mesh3D m; float *pos, *nrm, *mats; int cap, mcap; Uint64 used; } Pose3D;
static Pose3D poses3d[256];
static unsigned pose3d_ver;
static bool pose3d_gpu;                            // (set by the caller: the GPU can skin it, render3d.h's skin_pipe; nothing on the CPU needs its vertices now)
static Mesh3D *pose3d_get(const char *key, const Mesh3D *base, int clip, float t, bool loop, const float *morph_set);
// a copy the GPU skins, its vertices posed on the CPU after all (picking it, its outline): from its matrices
static void pose3d_cpu(Mesh3D *m) {
  if (!m || !m->cpu_pending || !m->gpu_base || !m->pose) return;
  Pose3D *P = m->pose;
  const Mesh3D *base = m->gpu_base;
  if (P->cap < base->nv) {
    SDL_free(P->pos); SDL_free(P->nrm);
    P->pos = SDL_malloc(sizeof(float) * 3 * (size_t)base->nv); P->nrm = SDL_malloc(sizeof(float) * 3 * (size_t)base->nv);
    P->cap = P->pos && P->nrm ? base->nv : 0;
    if (!P->cap) return;
  }
  mesh3d_skin(base, m->gpu_mats, base->pos, base->nrm, P->pos, P->nrm);
  m->pos = P->pos; m->nrm = P->nrm;
  m->cpu_pending = false;
  mesh3d_bounds(m);
}
static Mesh3D *pose3d_get(const char *key, const Mesh3D *base, int clip, float t, bool loop, const float *morph_set) {
  if (!base || !((base->njoints && base->jnt) || base->nmorphs)) return NULL;
  Pose3D *P = NULL, *old = &poses3d[0];
  for (int i = 0; i < (int)SDL_arraysize(poses3d) && !P; i++) if (poses3d[i].used && !strcmp(poses3d[i].key, key)) P = &poses3d[i];
  if (!P) {
    for (int i = 0; i < (int)SDL_arraysize(poses3d); i++) if (poses3d[i].used < old->used) old = &poses3d[i];
    P = old;
    SDL_strlcpy(P->key, key, sizeof P->key);
  }
  P->used = SDL_GetTicks() + 1;
  if (pose3d_gpu && base->njoints && base->jnt && base->nbinds && base->nbinds <= 256) {   // the GPU skins it: the matrices alone here
    bool morphed = false;                          // (a blend shape weighted: the CPU does it all, as before)
    if (base->nmorphs) {
      float w[256];
      mesh3d_weights(base, clip, t, loop, morph_set, w);
      for (int k = 0; k < base->nmorphs && k < 256; k++) if (w[k] != 0) morphed = true;
    }
    if (!morphed) {
      if (P->mcap < base->nbinds) {
        SDL_free(P->mats);
        P->mats = SDL_malloc(sizeof(float) * 16 * (size_t)base->nbinds);
        P->mcap = P->mats ? base->nbinds : 0;
        if (!P->mcap) return NULL;
      }
      if (!mesh3d_pose(base, clip, t, loop, P->mats, NULL)) return NULL;
      P->m = *base;                                // (its vertices: the base's, unskinned; its bounds: the base's)
      P->m.posed = true;
      P->m.gpu_mats = P->mats; P->m.gpu_base = base; P->m.pose = P; P->m.cpu_pending = true;
      SDL_snprintf(P->m.file, sizeof P->m.file, "pose:%s", key);
      return &P->m;
    }
  }
  if (P->cap < base->nv) {
    SDL_free(P->pos); SDL_free(P->nrm);
    P->pos = SDL_malloc(sizeof(float) * 3 * (size_t)base->nv); P->nrm = SDL_malloc(sizeof(float) * 3 * (size_t)base->nv);
    P->cap = P->pos && P->nrm ? base->nv : 0;
    if (!P->cap) return NULL;
  }
  if (base->nbinds && P->mcap < base->nbinds) {
    SDL_free(P->mats);
    P->mats = SDL_malloc(sizeof(float) * 16 * (size_t)base->nbinds);
    P->mcap = P->mats ? base->nbinds : 0;
    if (!P->mcap) return NULL;
  }
  const float *sp = base->pos, *sn = base->nrm;
  if (base->nmorphs) {                             // (blend shapes first, then the skin moves the result)
    float w[256];
    mesh3d_weights(base, clip, t, loop, morph_set, w);
    SDL_memcpy(P->pos, base->pos, sizeof(float) * 3 * (size_t)base->nv);
    SDL_memcpy(P->nrm, base->nrm, sizeof(float) * 3 * (size_t)base->nv);
    mesh3d_morph(base, w, P->pos, P->nrm);
    sp = P->pos; sn = P->nrm;
  }
  if (base->njoints && base->jnt) {
    if (!mesh3d_pose(base, clip, t, loop, P->mats, NULL)) return NULL;
    mesh3d_skin(base, P->mats, sp, sn, P->pos, P->nrm);
  } else for (int i = 0; i < base->nv; i++) {      // (no skin: the normals made whole again)
    float *N = &P->nrm[i * 3], l = sqrtf(N[0] * N[0] + N[1] * N[1] + N[2] * N[2]);
    if (l > 1e-12f) { N[0] /= l; N[1] /= l; N[2] /= l; }
  }
  P->m = *base;
  P->m.pos = P->pos; P->m.nrm = P->nrm;
  P->m.posed = true;
  P->m.gpu_mats = NULL; P->m.gpu_base = NULL; P->m.pose = P; P->m.cpu_pending = false;
  P->m.version = ++pose3d_ver;
  SDL_snprintf(P->m.file, sizeof P->m.file, "pose:%s", key);
  mesh3d_bounds(&P->m);
  return &P->m;
}
