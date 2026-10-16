// raster3d.h - the CPU rasterizer (docs/3D.md: the fallback and the tests'
// reference): Mesh3D triangles into an RGBA buffer with a depth buffer.
// Part of replay.c: included once, after mesh3d.h.
//
// Matrices are column-major (m[col * 4 + row]), right-handed, y up; clip
// depth 0..1 (as SDL_gpu's). Per vertex: Lambert from one sun, plus ambient,
// times its colour, the part's base colour and the node's tint (Gouraud); per
// pixel: times the texture (nearest, repeating), perspective-correct, alpha
// tested at 0.5. Triangles facing away are skipped (a two-sided part: not).
// Shadows (phase 4): the sun's depth first (r3_shadow_draw: an orthographic
// view, L->lvp), then per pixel the sun's share is taken away where something
// is nearer the sun: PCF 3x3, the same test as editor/shaders/mesh.frag.
#pragma once

typedef struct { int w, h; unsigned char *rgba; float *depth; int tris; } R3Target;   // tris: drawn since r3_begin
typedef struct {
  float ambient[3], sun_dir[3], sun_col[3];       // colours 0..1; sun_dir: where it shines (normalized)
  bool shadows; int shadow_size;                   // shadows: the sun's depth map, shadow_size^2 texels
  float lvp[16], bias, normal_offset;              // the sun's view-projection (world -> its clip space); bias: in its depth; normal_offset: m
  const float *shadow;                             // the CPU's depth map (r3_draw's test; NULL: no shadows)
} R3Light;

static void m4_mul(const float a[16], const float b[16], float o[16]) {
  float r[16];
  for (int c = 0; c < 4; c++) for (int k = 0; k < 4; k++)
    r[c * 4 + k] = a[k] * b[c * 4] + a[4 + k] * b[c * 4 + 1] + a[8 + k] * b[c * 4 + 2] + a[12 + k] * b[c * 4 + 3];
  SDL_memcpy(o, r, sizeof r);
}
static void m4_identity(float o[16]) { SDL_memset(o, 0, sizeof(float) * 16); o[0] = o[5] = o[10] = o[15] = 1; }
static void v3_norm(float v[3]) { float l = sqrtf(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]); if (l > 1e-12f) { v[0] /= l; v[1] /= l; v[2] /= l; } }
// the view and the projection: eye looking at `at`, `up`; fov_y degrees; depth 0..1
static void m4_look_at(const float eye[3], const float at[3], const float up[3], float o[16]) {
  float f[3] = { at[0] - eye[0], at[1] - eye[1], at[2] - eye[2] };
  v3_norm(f);
  float s[3] = { f[1] * up[2] - f[2] * up[1], f[2] * up[0] - f[0] * up[2], f[0] * up[1] - f[1] * up[0] };
  v3_norm(s);
  float u[3] = { s[1] * f[2] - s[2] * f[1], s[2] * f[0] - s[0] * f[2], s[0] * f[1] - s[1] * f[0] };
  float m[16] = { s[0], u[0], -f[0], 0, s[1], u[1], -f[1], 0, s[2], u[2], -f[2], 0,
                  -(s[0] * eye[0] + s[1] * eye[1] + s[2] * eye[2]), -(u[0] * eye[0] + u[1] * eye[1] + u[2] * eye[2]),
                  f[0] * eye[0] + f[1] * eye[1] + f[2] * eye[2], 1 };
  SDL_memcpy(o, m, sizeof m);
}
static void m4_perspective(float fov_y_deg, float aspect, float zn, float zf, float o[16]) {
  float t = tanf(fov_y_deg * 3.14159265f / 360.0f);
  float m[16] = { 1 / (aspect * t), 0, 0, 0, 0, 1 / t, 0, 0, 0, 0, zf / (zn - zf), -1, 0, 0, -(zf * zn) / (zf - zn), 0 };
  SDL_memcpy(o, m, sizeof m);
}
// a node's transform3d: x, y, z (m), rx, ry, rz (radians: y, then x, then z), s or sx, sy, sz
static void m4_trs(float x, float y, float z, float rx, float ry, float rz, float sx, float sy, float sz, float o[16]) {
  float cx = cosf(rx), sxr = sinf(rx), cy = cosf(ry), syr = sinf(ry), cz = cosf(rz), szr = sinf(rz);
  // R = Ry * Rx * Rz
  float r00 = cy * cz + syr * sxr * szr, r01 = -cy * szr + syr * sxr * cz, r02 = syr * cx;
  float r10 = cx * szr, r11 = cx * cz, r12 = -sxr;
  float r20 = -syr * cz + cy * sxr * szr, r21 = syr * szr + cy * sxr * cz, r22 = cy * cx;
  float m[16] = { r00 * sx, r10 * sx, r20 * sx, 0, r01 * sy, r11 * sy, r21 * sy, 0, r02 * sz, r12 * sz, r22 * sz, 0, x, y, z, 1 };
  SDL_memcpy(o, m, sizeof m);
}
// its normals' matrix (row-major 3x3): the upper 3x3's inverse transpose
static void m4_normal3(const float W[16], float Nm[9]) {
  float a = W[0], b = W[4], c = W[8], d = W[1], e = W[5], f = W[9], g = W[2], h = W[6], i = W[10];
  float C00 = e * i - f * h, C01 = -(d * i - f * g), C02 = d * h - e * g;
  float C10 = -(b * i - c * h), C11 = a * i - c * g, C12 = -(a * h - b * g);
  float C20 = b * f - c * e, C21 = -(a * f - c * d), C22 = a * e - b * d;
  float det = a * C00 + b * C01 + c * C02;
  float k = fabsf(det) < 1e-12f ? 1 : 1 / det;
  float m[9] = { C00 * k, C01 * k, C02 * k, C10 * k, C11 * k, C12 * k, C20 * k, C21 * k, C22 * k };
  SDL_memcpy(Nm, m, sizeof m);
}

static bool r3_begin(R3Target *T, int w, int h, const unsigned char clear[4]) {
  if (w <= 0 || h <= 0 || w > 4096 || h > 4096) return false;
  if (T->w != w || T->h != h || !T->rgba) {
    SDL_free(T->rgba); SDL_free(T->depth);
    T->rgba = SDL_malloc((size_t)w * h * 4);
    T->depth = SDL_malloc((size_t)w * h * sizeof(float));
    T->w = w; T->h = h;
    if (!T->rgba || !T->depth) { T->w = T->h = 0; return false; }
  }
  for (int i = 0; i < w * h; i++) { SDL_memcpy(&T->rgba[i * 4], clear, 4); T->depth[i] = 1; }
  T->tris = 0;
  return true;
}

typedef struct { float x, y, z, w; float r, g, b, a; float u, v; float sr, sg, sb; float lx, ly, lz; } R3V;   // clip space, lit colour, uv; the sun's share of it, where it is in the sun's view
static R3V r3_lerp(const R3V *a, const R3V *b, float t) {
  R3V o;
  const float *pa = &a->x, *pb = &b->x;
  float *po = &o.x;
  for (int k = 0; k < (int)(sizeof(R3V) / sizeof(float)); k++) po[k] = pa[k] + (pb[k] - pa[k]) * t;
  return o;
}
// how much of the sun reaches a point at (x, y, z) of the sun's clip space: 0..1, 9 texels (PCF 3x3)
static float r3_shadow_at(const R3Light *L, float x, float y, float z) {
  int S = L->shadow_size;
  if (!L->shadow || S <= 0 || x < -1 || x > 1 || y < -1 || y > 1 || z > 1) return 1;
  int ix = (int)SDL_floorf((x * 0.5f + 0.5f) * S), iy = (int)SDL_floorf((0.5f - y * 0.5f) * S);
  int lit = 0;
  for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
    int tx = SDL_clamp(ix + dx, 0, S - 1), ty = SDL_clamp(iy + dy, 0, S - 1);
    if (z - L->bias <= L->shadow[(size_t)ty * S + tx]) lit++;
  }
  return lit / 9.0f;
}
static void r3_tri(R3Target *T, const R3V *v0, const R3V *v1, const R3V *v2, const Tex3D *tx, bool two_sided, const R3Light *L) {
  float W = (float)T->w, H = (float)T->h;
  float sx[3], sy[3], sz[3], iw[3];
  const R3V *v[3] = { v0, v1, v2 };
  for (int k = 0; k < 3; k++) {
    iw[k] = 1 / v[k]->w;
    sx[k] = (v[k]->x * iw[k] * 0.5f + 0.5f) * W;
    sy[k] = (0.5f - v[k]->y * iw[k] * 0.5f) * H;
    sz[k] = v[k]->z * iw[k];
  }
  float area = (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0]);
  if (area == 0) return;
  if (area > 0 && !two_sided) return;              // (facing away: counter-clockwise in y-up space is clockwise on screen)
  int x0 = (int)SDL_floorf(SDL_min(sx[0], SDL_min(sx[1], sx[2]))), x1 = (int)SDL_ceilf(SDL_max(sx[0], SDL_max(sx[1], sx[2])));
  int y0 = (int)SDL_floorf(SDL_min(sy[0], SDL_min(sy[1], sy[2]))), y1 = (int)SDL_ceilf(SDL_max(sy[0], SDL_max(sy[1], sy[2])));
  if (x0 < 0) x0 = 0; if (y0 < 0) y0 = 0; if (x1 > T->w) x1 = T->w; if (y1 > T->h) y1 = T->h;
  if (x0 >= x1 || y0 >= y1) return;
  T->tris++;
  float inv = 1 / area;
  for (int py = y0; py < y1; py++) {
    float cy = py + 0.5f;
    for (int px = x0; px < x1; px++) {
      float cx = px + 0.5f;
      float l0 = ((sx[1] - cx) * (sy[2] - cy) - (sx[2] - cx) * (sy[1] - cy)) * inv;
      float l1 = ((sx[2] - cx) * (sy[0] - cy) - (sx[0] - cx) * (sy[2] - cy)) * inv;
      float l2 = 1 - l0 - l1;
      if (l0 < 0 || l1 < 0 || l2 < 0) continue;
      float z = l0 * sz[0] + l1 * sz[1] + l2 * sz[2];
      if (z < 0 || z > 1) continue;
      size_t at = (size_t)py * T->w + px;
      if (z >= T->depth[at]) continue;
      float q0 = l0 * iw[0], q1 = l1 * iw[1], q2 = l2 * iw[2], qs = 1 / (q0 + q1 + q2);   // (perspective-correct)
      q0 *= qs; q1 *= qs; q2 *= qs;
      float r = v0->r * q0 + v1->r * q1 + v2->r * q2, g = v0->g * q0 + v1->g * q1 + v2->g * q2;
      float b = v0->b * q0 + v1->b * q1 + v2->b * q2, a = v0->a * q0 + v1->a * q1 + v2->a * q2;
      if (L && L->shadow) {                        // (in shadow: the sun's share taken away)
        float lit = r3_shadow_at(L, v0->lx * q0 + v1->lx * q1 + v2->lx * q2, v0->ly * q0 + v1->ly * q1 + v2->ly * q2, v0->lz * q0 + v1->lz * q1 + v2->lz * q2);
        if (lit < 1) {
          float k = 1 - lit;
          r -= (v0->sr * q0 + v1->sr * q1 + v2->sr * q2) * k;
          g -= (v0->sg * q0 + v1->sg * q1 + v2->sg * q2) * k;
          b -= (v0->sb * q0 + v1->sb * q1 + v2->sb * q2) * k;
        }
      }
      if (tx && tx->rgba) {
        float u = v0->u * q0 + v1->u * q1 + v2->u * q2, vv = v0->v * q0 + v1->v * q1 + v2->v * q2;
        int tu = (int)SDL_floorf((u - SDL_floorf(u)) * tx->w), tv = (int)SDL_floorf((vv - SDL_floorf(vv)) * tx->h);
        if (tu >= tx->w) tu = tx->w - 1;
        if (tv >= tx->h) tv = tx->h - 1;
        const unsigned char *t = &tx->rgba[((size_t)tv * tx->w + tu) * 4];
        r *= t[0] / 255.f; g *= t[1] / 255.f; b *= t[2] / 255.f; a *= t[3] / 255.f;
      }
      if (a < 0.5f) continue;                      // (alpha tested: foliage, cut-outs)
      T->depth[at] = z;
      unsigned char *o = &T->rgba[at * 4];
      o[0] = (unsigned char)(SDL_clamp(r, 0, 1) * 255 + .5f);
      o[1] = (unsigned char)(SDL_clamp(g, 0, 1) * 255 + .5f);
      o[2] = (unsigned char)(SDL_clamp(b, 0, 1) * 255 + .5f);
      o[3] = 255;
    }
  }
}
// a triangle clipped against the near plane (z >= 0 in clip space), then drawn
static void r3_clip_tri(R3Target *T, const R3V *a, const R3V *b, const R3V *c, const Tex3D *tx, bool two_sided, const R3Light *L) {
  const R3V *in[3] = { a, b, c };
  R3V out[4];
  int n = 0;
  for (int k = 0; k < 3; k++) {
    const R3V *p = in[k], *q = in[(k + 1) % 3];
    bool pin = p->z >= 0 && p->w > 1e-6f, qin = q->z >= 0 && q->w > 1e-6f;
    if (pin) out[n++] = *p;
    if (pin != qin) {
      float t = p->z / (p->z - q->z);
      if (n < 4) out[n++] = r3_lerp(p, q, t);
    }
  }
  for (int k = 1; k + 1 < n; k++) r3_tri(T, &out[0], &out[k], &out[k + 1], tx, two_sided, L);
}

// a mesh at `model`, seen through `vp` (proj * view); tint 0..1; tex: in place of its parts' textures (NULL: theirs)
static void r3_draw(R3Target *T, const Mesh3D *m, const float model[16], const float vp[16], const float tint[4],
                    const R3Light *L, const Tex3D *tex) {
  if (!m || !m->ok || !T->rgba) return;
  float mvp[16], Nm[9];
  m4_mul(vp, model, mvp);
  m4_normal3(model, Nm);
  R3V *vs = SDL_malloc(sizeof(R3V) * (size_t)m->nv);
  if (!vs) return;
  for (int p = 0; p < m->nparts; p++) {
    const Part3D *pt = &m->parts[p];
    const Tex3D *tx = tex ? tex : (pt->tex >= 0 && pt->tex < m->ntex ? &m->tex[pt->tex] : NULL);
    float base[4] = { pt->base[0] * tint[0], pt->base[1] * tint[1], pt->base[2] * tint[2], pt->base[3] * tint[3] };
    // (its vertices: once a part; parts share none in practice)
    for (int q = pt->first; q < pt->first + pt->count; q++) {
      unsigned i = m->idx[q];
      if (i >= (unsigned)m->nv) continue;
      const float *P = &m->pos[i * 3], *N = &m->nrm[i * 3];
      R3V *o = &vs[i];
      o->x = mvp[0] * P[0] + mvp[4] * P[1] + mvp[8] * P[2] + mvp[12];
      o->y = mvp[1] * P[0] + mvp[5] * P[1] + mvp[9] * P[2] + mvp[13];
      o->z = mvp[2] * P[0] + mvp[6] * P[1] + mvp[10] * P[2] + mvp[14];
      o->w = mvp[3] * P[0] + mvp[7] * P[1] + mvp[11] * P[2] + mvp[15];
      float n[3] = { Nm[0] * N[0] + Nm[1] * N[1] + Nm[2] * N[2], Nm[3] * N[0] + Nm[4] * N[1] + Nm[5] * N[2], Nm[6] * N[0] + Nm[7] * N[1] + Nm[8] * N[2] };
      v3_norm(n);
      float lam = -(n[0] * L->sun_dir[0] + n[1] * L->sun_dir[1] + n[2] * L->sun_dir[2]);
      if (lam < 0) lam = 0;
      const unsigned char *c = &m->col[i * 4];
      o->r = c[0] / 255.f * base[0] * (L->ambient[0] + L->sun_col[0] * lam);
      o->g = c[1] / 255.f * base[1] * (L->ambient[1] + L->sun_col[1] * lam);
      o->b = c[2] / 255.f * base[2] * (L->ambient[2] + L->sun_col[2] * lam);
      o->sr = c[0] / 255.f * base[0] * L->sun_col[0] * lam;
      o->sg = c[1] / 255.f * base[1] * L->sun_col[1] * lam;
      o->sb = c[2] / 255.f * base[2] * L->sun_col[2] * lam;
      float wp[3];                                 // (in the world, pushed off its surface: no acne)
      for (int k = 0; k < 3; k++) wp[k] = model[k] * P[0] + model[4 + k] * P[1] + model[8 + k] * P[2] + model[12 + k] + n[k] * L->normal_offset;
      const float *lv = L->lvp;
      o->lx = lv[0] * wp[0] + lv[4] * wp[1] + lv[8] * wp[2] + lv[12];   // (orthographic: w is 1)
      o->ly = lv[1] * wp[0] + lv[5] * wp[1] + lv[9] * wp[2] + lv[13];
      o->lz = lv[2] * wp[0] + lv[6] * wp[1] + lv[10] * wp[2] + lv[14];
      o->a = c[3] / 255.f * base[3];
      o->u = m->uv[i * 2]; o->v = m->uv[i * 2 + 1];
    }
    for (int q = pt->first; q + 2 < pt->first + pt->count; q += 3) {
      unsigned a = m->idx[q], b = m->idx[q + 1], c = m->idx[q + 2];
      if (a >= (unsigned)m->nv || b >= (unsigned)m->nv || c >= (unsigned)m->nv) continue;
      const R3V *A = &vs[a], *B = &vs[b], *C = &vs[c];
      bool all_in = A->z >= 0 && B->z >= 0 && C->z >= 0 && A->w > 1e-6f && B->w > 1e-6f && C->w > 1e-6f;
      if (A->z > A->w && B->z > B->w && C->z > C->w) continue;   // (all past the far plane)
      if (all_in) r3_tri(T, A, B, C, tx, false, L);
      else r3_clip_tri(T, A, B, C, tx, false, L);
    }
  }
  SDL_free(vs);
}

// the sun's view: orthographic, depth 0..1 (a box: l..r, b..t, n..f in front of the eye)
static void m4_ortho(float l, float r, float b, float t, float n, float f, float o[16]) {
  float m[16] = { 2 / (r - l), 0, 0, 0, 0, 2 / (t - b), 0, 0, 0, 0, -1 / (f - n), 0, -(r + l) / (r - l), -(t + b) / (t - b), -n / (f - n), 1 };
  SDL_memcpy(o, m, sizeof m);
}
// the sun's view-projection for a sphere (centre c, radius r) and its depth bias (a texel and a half)
static void r3_sun_fit(R3Light *L, const float c[3], float r) {
  if (r < 1e-3f) r = 1e-3f;
  float eye[3] = { c[0] - L->sun_dir[0] * r * 2, c[1] - L->sun_dir[1] * r * 2, c[2] - L->sun_dir[2] * r * 2 };
  float up[3] = { 0, 1, 0 };
  if (fabsf(L->sun_dir[1]) > 0.99f) { up[1] = 0; up[2] = -1; }   // (straight down: up is -z, north)
  float view[16], proj[16];
  m4_look_at(eye, c, up, view);
  m4_ortho(-r, r, -r, r, r * 0.5f, r * 3.5f, proj);   // (r * 2 in front: the sphere, with a margin)
  m4_mul(proj, view, L->lvp);
  int S = L->shadow_size > 0 ? L->shadow_size : 1024;
  L->bias = (2 * r / S) * 1.0f / (r * 3);          // (a texel of the map, in its depth's units)
  L->normal_offset = (2 * r / S) * 1.5f;           // (and a texel and a half off the surface, along its normal)
}
// the sun's depth of a mesh into `depth` (S x S, cleared to 1): both faces, no alpha test
static void r3_shadow_draw(float *depth, int S, const Mesh3D *m, const float model[16], const float lvp[16]) {
  if (!m || !m->ok || !depth) return;
  float lm[16];
  m4_mul(lvp, model, lm);
  float *xs = SDL_malloc(sizeof(float) * 3 * (size_t)m->nv);
  if (!xs) return;
  for (int i = 0; i < m->nv; i++) {
    const float *P = &m->pos[i * 3];
    float x = lm[0] * P[0] + lm[4] * P[1] + lm[8] * P[2] + lm[12], y = lm[1] * P[0] + lm[5] * P[1] + lm[9] * P[2] + lm[13];
    xs[i * 3] = (x * 0.5f + 0.5f) * S; xs[i * 3 + 1] = (0.5f - y * 0.5f) * S;
    xs[i * 3 + 2] = lm[2] * P[0] + lm[6] * P[1] + lm[10] * P[2] + lm[14];
  }
  for (int q = 0; q + 2 < m->ni; q += 3) {
    unsigned ia = m->idx[q], ib = m->idx[q + 1], ic = m->idx[q + 2];
    if (ia >= (unsigned)m->nv || ib >= (unsigned)m->nv || ic >= (unsigned)m->nv) continue;
    const float *a = &xs[ia * 3], *b = &xs[ib * 3], *c = &xs[ic * 3];
    float area = (b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1]);
    if (area == 0) continue;
    int x0 = (int)SDL_floorf(SDL_min(a[0], SDL_min(b[0], c[0]))), x1 = (int)SDL_ceilf(SDL_max(a[0], SDL_max(b[0], c[0])));
    int y0 = (int)SDL_floorf(SDL_min(a[1], SDL_min(b[1], c[1]))), y1 = (int)SDL_ceilf(SDL_max(a[1], SDL_max(b[1], c[1])));
    if (x0 < 0) x0 = 0; if (y0 < 0) y0 = 0; if (x1 > S) x1 = S; if (y1 > S) y1 = S;
    float inv = 1 / area;
    for (int py = y0; py < y1; py++) {
      float cy = py + 0.5f;
      for (int px = x0; px < x1; px++) {
        float cx = px + 0.5f;
        float l0 = ((b[0] - cx) * (c[1] - cy) - (c[0] - cx) * (b[1] - cy)) * inv;
        float l1 = ((c[0] - cx) * (a[1] - cy) - (a[0] - cx) * (c[1] - cy)) * inv;
        float l2 = 1 - l0 - l1;
        if (l0 < 0 || l1 < 0 || l2 < 0) continue;
        float z = l0 * a[2] + l1 * b[2] + l2 * c[2];
        if (z < 0 || z > 1) continue;
        float *d = &depth[(size_t)py * S + px];
        if (z < *d) *d = z;
      }
    }
  }
  SDL_free(xs);
}
