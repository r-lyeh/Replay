// editor/tgizmo.h - the transform gizmo (move / rotate / scale) on the selected node, in the game view.
// Part of replay.c: included once, after render.h.
//
// The whole selection moves with it (each by the same move, turn and scale, round its own place: boot.lua
// viewer_move_with). One gizmo, worked out in 3D: a 3D node (transform3d, under a camera3d) gets arrows, rings and boxes along
// the world's x, y, z (scale: along its own axes), dragged by rays through the camera's picture (the
// same math as picking); a 2D node (transform) gets the same gizmo seen from the front, orthographic: the z
// arrow and the x and y rings left out, the ray the mouse point itself, y down. W / E / R (the game view
// focused) or its three buttons pick the mode. Beside them (stopped or paused only): World / Local (the axes it
// moves and turns along: the world's or the node's own; scale is always its own), Snap (a click: the next step,
// past the biggest off; on: always; CTRL flips it; the wheel over it: the step too, 3D 0.1 / 0.25 / 0.5 / 1 m, 2D 2 / 8 / 16 / 32, 5 / 15 / 30 / 45 degrees,
// x0.05 / 0.1 / 0.25 / 0.5) and # (a grid on the ground, y = 0, under a camera3d: 1 m, every 5th brighter).
// Stopped or paused, never standalone; one undo level per drag (boot.lua: viewer_move_*, viewer_move3d_*).
#pragma once

enum { TG_MOVE, TG_ROTATE, TG_SCALE };
enum { TG_NONE, TG_X, TG_Y, TG_Z, TG_FREE, TG_VIEW, TG_PX, TG_PY, TG_PZ, TG_BTN_MOVE, TG_BTN_ROTATE, TG_BTN_SCALE, TG_BTN_SPACE, TG_BTN_SNAP, TG_BTN_GRID };   // (TG_VIEW: the outer ring, about the line to the camera; TG_Pn: the plane square facing axis n)
static struct {
  int mode, hot, active;
  bool on2d, on3d;                                 // (the selection, as last drawn: a 2D node / a 3D one)
  Mat M2;                                          // 2D: its screen place (game-view points)
  float M3[16], P3[16];                            // 3D: its world matrix, its parent's
  int cam;                                         // 3D: the camera3d it's under (cams3d)
  char path[256];
  // a drag
  float gx0, gy0, gx, gy;                          // where it began, where it is (game-view points)
  float applied[3];                                // 2D: what's been applied so far (dx, dy | dr | ds): snapping applies totals
  float S[9];                                      // 3D: x, y, z, rx, ry, rz, sx, sy, sz at the start
  float O0[3], D0[3], P0[3];                       // 3D: the first ray, the node's place
  float vax[3];                                    // 3D: the outer ring's axis (from the node to the camera)
  bool dragging;
  float by;                                        // the mode buttons' top (the game view's bottom left)
  bool local, snap, grid;                          // the overlay's toggles: own axes, snapping, the ground grid
  int snap_i;                                      // the snap step: 0..3 (TG_SNAP_*)
} tg = { TG_MOVE, .grid = true, .snap_i = 1 };
static const float TG_SNAP_M3[4] = { 0.1f, 0.25f, 0.5f, 1 }, TG_SNAP_M2[4] = { 2, 8, 16, 32 }, TG_SNAP_DEG[4] = { 5, 15, 30, 45 }, TG_SNAP_S[4] = { 0.05f, 0.1f, 0.25f, 0.5f };
static const SDL_FRect TG_BTNS[6] = { { 6, 0, 22, 20 }, { 30, 0, 22, 20 }, { 54, 0, 22, 20 }, { 84, 0, 46, 20 }, { 134, 0, 64, 20 }, { 202, 0, 22, 20 } };

static const float TG_LEN = 70, TG_RING = 55, TG_BOX = 5, TG_VRING = 1.25f, TG_SBOX = 8;   // (points; the outer ring, a ratio of the rings'; scale's middle box, half its side)
static const float TG_P0 = 0.22f, TG_P1 = 0.42f;   // (the plane squares: from / to, along both their axes)

static Viewer *tg_V;
static void push_selection(lua_State *L, Viewer *V);   // (ui.h: the selection, primary first)
static void sel_toggle(Viewer *V, const char *p);      // (ui.h: CTRL+click's)
static int drop_to_ground(Viewer *V);              // (replay.c: End)
static SDL_FRect tg_gv;
static bool tg_lite_shown;                         // (lite's picture composed this frame: host_gizmo("dock")'s 6th)                            // (the game view's rect this frame, window points: host_gizmo("dock"))
static void tg_frame_begin(Viewer *V) { tg.on2d = tg.on3d = false; tg_V = V; }
static void tg_note_2d(const char *path, Mat M) {   // (render.h draw_node: the selection's place)
  if (tg.on3d) return;                             // (a 3D node: its camera's walk saw it first)
  tg.on2d = true; tg.M2 = M;
  SDL_strlcpy(tg.path, path, sizeof tg.path);
}
static void tg_note_3d(const char *path, const float M[16], const float parent[16], int cam) {   // (draw3d_node)
  tg.on3d = true; tg.on2d = false;
  SDL_memcpy(tg.M3, M, sizeof tg.M3); SDL_memcpy(tg.P3, parent, sizeof tg.P3); tg.cam = cam;
  SDL_strlcpy(tg.path, path, sizeof tg.path);
}

// 3D helpers: a world point onto the game view (through its camera's picture), the mouse's ray
static bool tg_proj(const Cam3D *c, const float p[3], SDL_FPoint *out) {
  const float *V = c->pvp;
  float x = V[0] * p[0] + V[4] * p[1] + V[8] * p[2] + V[12], y = V[1] * p[0] + V[5] * p[1] + V[9] * p[2] + V[13];
  float w = V[3] * p[0] + V[7] * p[1] + V[11] * p[2] + V[15];
  if (w < 1e-4f) return false;
  *out = xf(c->pM, x / w * 0.5f * c->pw2, -y / w * 0.5f * c->ph2);
  return true;
}
static bool tg_ray(const Cam3D *c, float gx, float gy, float O[3], float D[3]) {
  Mat M = c->pM;
  float det = M.a * M.d - M.b * M.c, inv[16];
  if (fabsf(det) < 1e-12f || !m4_invert(c->pvp, inv)) return false;
  float px = gx - M.tx, py = gy - M.ty;
  float lx = (M.d * px - M.c * py) / det, ly = (-M.b * px + M.a * py) / det;
  float nx = lx / (c->pw2 * 0.5f), ny = -ly / (c->ph2 * 0.5f);
  float a4[4] = { nx, ny, 0, 1 }, b4[4] = { nx, ny, 1, 1 }, A[4], B[4];
  for (int r = 0; r < 4; r++) { A[r] = inv[r] * a4[0] + inv[4 + r] * a4[1] + inv[8 + r] * a4[2] + inv[12 + r]; B[r] = inv[r] * b4[0] + inv[4 + r] * b4[1] + inv[8 + r] * b4[2] + inv[12 + r]; }
  if (fabsf(A[3]) < 1e-12f || fabsf(B[3]) < 1e-12f) return false;
  for (int k = 0; k < 3; k++) { O[k] = A[k] / A[3]; D[k] = B[k] / B[3] - O[k]; }
  v3_norm(D);
  return true;
}
// the gizmo's place and its axes on screen: origin o; axis k's unit direction on screen (dir[k]), its length
// there (len[k]: 0 when seen end-on, or the axis 2D leaves out); for 3D, its world direction too
typedef struct { SDL_FPoint o; float dir[3][2], len[3]; float wax[3][3]; float ppm, dist, g; bool ok; } TGView;  // (g: its size, 1, smaller where it'd reach the camera)
static TGView tg_view(void) {
  TGView v;
  SDL_zero(v);
  if (tg.on3d) {
    const Cam3D *c = &cams3d[tg.cam];
    float P[3] = { tg.M3[12], tg.M3[13], tg.M3[14] };
    if (!tg_proj(c, P, &v.o)) return v;
    float O[3], D[3];                              // (a step across the view, there: points a meter)
    if (!tg_ray(c, v.o.x, v.o.y, O, D)) return v;
    float dist = sqrtf((P[0] - O[0]) * (P[0] - O[0]) + (P[1] - O[1]) * (P[1] - O[1]) + (P[2] - O[2]) * (P[2] - O[2]));
    float k = SDL_max(dist * 0.05f, 1e-3f);
    v.dist = dist;
    float up[3] = { 0, 1, 0 }, side[3] = { D[1] * up[2] - D[2] * up[1], D[2] * up[0] - D[0] * up[2], D[0] * up[1] - D[1] * up[0] };
    if (side[0] * side[0] + side[1] * side[1] + side[2] * side[2] < 1e-8f) side[0] = 1;
    v3_norm(side);
    float Q[3] = { P[0] + side[0] * k, P[1] + side[1] * k, P[2] + side[2] * k };
    SDL_FPoint s;
    if (!tg_proj(c, Q, &s)) return v;
    v.ppm = sqrtf((s.x - v.o.x) * (s.x - v.o.x) + (s.y - v.o.y) * (s.y - v.o.y)) / k;
    if (v.ppm < 1e-6f) return v;
    v.g = SDL_min(1.f, dist * 0.4f * v.ppm / TG_RING);
    for (int a = 0; a < 3; a++) {
      float ax[3] = { 0, 0, 0 };
      if (tg.mode == TG_SCALE || tg.local) { ax[0] = tg.M3[a * 4]; ax[1] = tg.M3[a * 4 + 1]; ax[2] = tg.M3[a * 4 + 2]; v3_norm(ax); }   // (scale, or Local: its own axes)
      else ax[a] = 1;
      SDL_memcpy(v.wax[a], ax, sizeof ax);
      float R[3] = { P[0] + ax[0] * k, P[1] + ax[1] * k, P[2] + ax[2] * k };
      if (!tg_proj(c, R, &s)) continue;
      float dx = s.x - v.o.x, dy = s.y - v.o.y, l = sqrtf(dx * dx + dy * dy);
      if (l < 1e-4f) continue;
      v.dir[a][0] = dx / l; v.dir[a][1] = dy / l;
      v.len[a] = SDL_min(1.f, l / (v.ppm * k)) * v.g;   // (end-on: shorter)
    }
    v.ok = true;
  } else if (tg.on2d) {
    v.o = xf(tg.M2, 0, 0);
    if (tg.mode == TG_SCALE || tg.local) {         // (scale, or Local: its own axes, turned with it)
      float ax = tg.M2.a, ay = tg.M2.b, bx = tg.M2.c, by = tg.M2.d;
      float la = sqrtf(ax * ax + ay * ay), lb = sqrtf(bx * bx + by * by);
      if (la > 1e-6f) { v.dir[0][0] = ax / la; v.dir[0][1] = ay / la; }
      if (lb > 1e-6f) { v.dir[1][0] = bx / lb; v.dir[1][1] = by / lb; }
    } else { v.dir[0][0] = 1; v.dir[1][1] = 1; }   // (move, rotate: the world's x right, y down)
    v.len[0] = v.len[1] = 1;
    v.g = 1;
    v.ok = true;
  }
  return v;
}

static float seg_d(float px, float py, float ax, float ay, float bx, float by) {
  float dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
  float t = l2 > 0 ? ((px - ax) * dx + (py - ay) * dy) / l2 : 0;
  t = SDL_clamp(t, 0, 1);
  float qx = ax + dx * t - px, qy = ay + dy * t - py;
  return sqrtf(qx * qx + qy * qy);
}
// a 3D ring (axis a's), on screen: n points; front[i]: that point on the half toward the camera (a semicircle is
// drawn and grabbed: the far half would only be in the way; the one dragged: whole)
static int tg_ring3d(const TGView *v, int a, SDL_FPoint *out, int n, bool *front) {
  const Cam3D *c = &cams3d[tg.cam];
  float P[3] = { tg.M3[12], tg.M3[13], tg.M3[14] }, u[3], w[3], O[3], D[3] = { 0, 0, 0 };
  SDL_memcpy(u, v->wax[(a + 1) % 3], sizeof u); SDL_memcpy(w, v->wax[(a + 2) % 3], sizeof w);   // (its plane: the world's, or its own)
  float r = TG_RING * v->g / SDL_max(v->ppm, 1e-6f);   // (constant on screen; never round the camera itself)
  bool dir = tg_ray(c, v->o.x, v->o.y, O, D);      // (the camera, from it: -D)
  int k = 0;
  for (int i = 0; i < n; i++) {
    float t = i * 6.2831853f / (n - 1), Q[3];
    for (int q = 0; q < 3; q++) Q[q] = P[q] + r * (cosf(t) * u[q] + sinf(t) * w[q]);
    if (!tg_proj(c, Q, &out[k])) continue;
    if (front) front[k] = !dir || -((Q[0] - P[0]) * D[0] + (Q[1] - P[1]) * D[1] + (Q[2] - P[2]) * D[2]) >= -0.02f * r;
    k++;
  }
  return k;
}
// the plane square facing axis n: where gx, gy falls, in its two axes' lengths (s, t); false when seen edge-on
static bool tg_plane_at(const TGView *v, int n, float gx, float gy, float *s_, float *t_) {
  int a = (n + 1) % 3, b = (n + 2) % 3;
  float ux = v->dir[a][0] * TG_LEN * v->len[a], uy = v->dir[a][1] * TG_LEN * v->len[a];
  float wx = v->dir[b][0] * TG_LEN * v->len[b], wy = v->dir[b][1] * TG_LEN * v->len[b];
  float det = ux * wy - uy * wx;
  if (fabsf(det) < 0.12f * TG_LEN * TG_LEN * v->g * v->g) return false;
  float px = gx - v->o.x, py = gy - v->o.y;
  *s_ = (px * wy - py * wx) / det; *t_ = (ux * py - uy * px) / det;
  return true;
}
static int tg_hit(const TGView *v, float gx, float gy) {
  if (gy >= tg.by && gy < tg.by + 20)               // (the buttons: the game view's bottom left)
    for (int i = 0; i < 6; i++) if (gx >= TG_BTNS[i].x && gx < TG_BTNS[i].x + TG_BTNS[i].w) return TG_BTN_MOVE + i;
  if (!v->ok) return TG_NONE;
  float ox = v->o.x, oy = v->o.y;
  int naxes = tg.on3d ? 3 : 2;
  if (tg.mode == TG_ROTATE) {
    if (tg.on3d) {
      SDL_FPoint pts[49];
      int best = TG_NONE; float bd = 7;
      float d = sqrtf((gx - ox) * (gx - ox) + (gy - oy) * (gy - oy));
      if (fabsf(d - TG_RING * TG_VRING * v->g) < 6) return TG_VIEW;   // (the outer ring)
      bool fr[49];
      for (int a = 0; a < 3; a++) {
        int n = tg_ring3d(v, a, pts, 49, fr);
        for (int i = 0; i + 1 < n; i++) {
          if (!fr[i] || !fr[i + 1]) continue;      // (the near half only)
          float e = seg_d(gx, gy, pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y); if (e < bd) { bd = e; best = TG_X + a; }
        }
      }
      return best;
    }
    float d = sqrtf((gx - ox) * (gx - ox) + (gy - oy) * (gy - oy));
    return fabsf(d - TG_RING) < 7 ? TG_Z : TG_NONE;
  }
  float hb = (tg.mode == TG_SCALE ? TG_SBOX : TG_BOX) + 3;
  if (fabsf(gx - ox) <= hb && fabsf(gy - oy) <= hb) return TG_FREE;
  if (tg.on3d && tg.mode == TG_MOVE)                // (the plane squares, between two axes)
    for (int n = 0; n < 3; n++) {
      float s_, t_;
      if (tg_plane_at(v, n, gx, gy, &s_, &t_) && s_ >= TG_P0 && s_ <= TG_P1 && t_ >= TG_P0 && t_ <= TG_P1) return TG_PX + n;
    }
  int best = TG_NONE; float bd = 7;
  for (int a = 0; a < naxes; a++) {
    if (v->len[a] < 0.15f) continue;               // (end-on: not grabbed)
    float L = TG_LEN * v->len[a];
    float d = seg_d(gx, gy, ox, oy, ox + v->dir[a][0] * L, oy + v->dir[a][1] * L);
    if (d < bd) { bd = d; best = TG_X + a; }
  }
  return best;
}

static void tg_line(SDL_Renderer *r, float x1, float y1, float x2, float y2, float wpx) {   // (a thick line: offsets)
  float dx = x2 - x1, dy = y2 - y1, l = sqrtf(dx * dx + dy * dy);
  if (l < 1e-4f) return;
  float nx = -dy / l, ny = dx / l;
  for (float k = -(wpx - 1) / 2; k <= (wpx - 1) / 2 + 0.01f; k += 1) SDL_RenderLine(r, x1 + nx * k, y1 + ny * k, x2 + nx * k, y2 + ny * k);
}
// the ground grid (y = 0), for a view the CPU draws (the GPU's has it in the scene: render.h g3_grid), under the camera3d the selection is under (else the last one drawn): 1 m lines round where
// the camera looks, every 5th brighter, fading out by 12 m; inside that camera's picture only
static void tg_grid(Viewer *V, float ox, float oy) {
  (void)V;
  const Cam3D *c = NULL;
  Uint64 best = 0;
  if (tg.on3d) c = &cams3d[tg.cam];
  else for (int i = 0; i < (int)SDL_arraysize(cams3d); i++) if (cams3d[i].used > best && cams3d[i].pw2 > 0) { best = cams3d[i].used; c = &cams3d[i]; }
  if (!c || c->pw2 <= 0 || c->rect.w < 2 || c->gpu) return;   // (drawn by the GPU: the grid is in its picture, depth tested: render.h)
  if (SDL_GetTicks() + 1 > c->used + 500) return;  // (not drawn lately: none)
  SDL_Renderer *r = V->ren;
  SDL_Rect clip = { (int)(ox + c->rect.x), (int)(oy + c->rect.y), (int)c->rect.w, (int)c->rect.h }, old;
  bool had = SDL_RenderClipEnabled(r);
  if (had) SDL_GetRenderClipRect(r, &old);
  SDL_SetRenderClipRect(r, &clip);
  enum { N = 12 };
  float cx = SDL_floorf(c->gat[0] + 0.5f), cz = SDL_floorf(c->gat[2] + 0.5f);
  for (int axis = 0; axis < 2; axis++) for (int i = -N; i <= N; i++) {
    bool major = ((int)(axis ? cz : cx) + i) % 5 == 0;
    for (int sgm = -N; sgm < N; sgm++) {           // (in pieces: a line partly behind the camera, and the fade)
      float A[3], B[3];
      if (!axis) { A[0] = B[0] = cx + i; A[2] = cz + sgm; B[2] = cz + sgm + 1; }
      else { A[2] = B[2] = cz + i; A[0] = cx + sgm; B[0] = cx + sgm + 1; }
      A[1] = B[1] = 0;
      float d = SDL_max(fabsf((float)i), fabsf(sgm + 0.5f)) / N;
      int a = (int)((major ? 150 : 70) * (1 - d * d));
      SDL_FPoint p, q;
      if (a <= 4 || !tg_proj(c, A, &p) || !tg_proj(c, B, &q)) continue;
      bool xa = !axis && fabsf(cx + i) < 0.5f, za = axis && fabsf(cz + i) < 0.5f;   // (the axes: z's line blue, x's red)
      SDL_SetRenderDrawColor(r, za ? 235 : xa ? 70 : 255, za ? 60 : xa ? 120 : 255, za ? 60 : 255, (Uint8)a);
      SDL_RenderLine(r, ox + p.x, oy + p.y, ox + q.x, oy + q.y);
    }
  }
  SDL_SetRenderClipRect(r, had ? &old : NULL);
}
static bool tg_wheel(Viewer *V, float gx, float gy, float dy) {   // (over Snap: its step) -> taken
  if (V->standalone || !ed_editing(V) || dy == 0) return false;
  TGView v = tg_view();
  if (tg_hit(&v, gx, gy) != TG_BTN_SNAP) return false;
  tg.snap_i = SDL_clamp(tg.snap_i + (dy > 0 ? 1 : -1), 0, 3);
  return true;
}
static void tg_draw(Viewer *V, float ox, float oy, float h) {   // ox, oy: the game view's corner, h: its height
  tg.by = h - 26;
  if (V->standalone || !ed_editing(V) || V->world == LUA_NOREF) return;
  SDL_Renderer *r = V->ren;
  SDL_SetRenderDrawBlendMode(r, SDL_BLENDMODE_BLEND);
  if (tg.grid) tg_grid(V, ox, oy);
  char snap_t[16];                                 // the buttons: W E R, World / Local, Snap and its step, the grid
  if (!tg.snap) SDL_strlcpy(snap_t, "S off", sizeof snap_t);
  else if (tg.mode == TG_ROTATE) SDL_snprintf(snap_t, sizeof snap_t, "S %gdeg", TG_SNAP_DEG[tg.snap_i]);
  else if (tg.mode == TG_SCALE) SDL_snprintf(snap_t, sizeof snap_t, "S x%g", TG_SNAP_S[tg.snap_i]);
  else if (tg.on2d) SDL_snprintf(snap_t, sizeof snap_t, "S %g", TG_SNAP_M2[tg.snap_i]);
  else SDL_snprintf(snap_t, sizeof snap_t, "S %gm", TG_SNAP_M3[tg.snap_i]);
  const char *labels[6] = { "W", "E", "R", tg.local ? "Local" : "World", snap_t, "#" };
  for (int i = 0; i < 6; i++) {
    SDL_FRect b = { ox + TG_BTNS[i].x, oy + tg.by, TG_BTNS[i].w, TG_BTNS[i].h };
    bool on = i < 3 ? tg.mode == i : i == 3 ? tg.local : i == 4 ? tg.snap : tg.grid, hot = tg.hot == TG_BTN_MOVE + i;
    SDL_SetRenderDrawColor(r, on ? 255 : 40, on ? 200 : 44, on ? 40 : 52, 220);
    SDL_RenderFillRect(r, &b);
    SDL_SetRenderDrawColor(r, hot ? 255 : 150, hot ? 255 : 150, hot ? 255 : 160, 255);
    SDL_RenderRect(r, &b);
    SDL_SetRenderDrawColor(r, on ? 20 : 220, on ? 20 : 220, on ? 20 : 230, 255);
    SDL_RenderDebugText(r, b.x + (b.w - 8 * (float)SDL_strlen(labels[i])) / 2, b.y + 6, labels[i]);
  }
  if (tg.hot >= TG_BTN_MOVE && !tg.dragging) {     // (its tooltip, over the row)
    static const char *tips[6] = { "Move (W; Space: the next mode)", "Rotate (E)", "Scale (R)",
                                   "Axes: the world's or the node's own (click: switch)",
                                   "Snap: a click, the next step (past the last: off); wheel: the step; Ctrl while dragging: flips it",
                                   "The ground grid in 3D views: on / off" };
    const char *t = tips[tg.hot - TG_BTN_MOVE];
    float tw = 8 * (float)SDL_strlen(t) + 8, tx = SDL_max(2.f, ox + TG_BTNS[tg.hot - TG_BTN_MOVE].x);
    SDL_FRect bx = { tx, oy + tg.by - 16, tw, 14 };
    SDL_SetRenderDrawColor(r, 20, 22, 28, 235); SDL_RenderFillRect(r, &bx);
    SDL_SetRenderDrawColor(r, 150, 150, 160, 255); SDL_RenderRect(r, &bx);
    SDL_SetRenderDrawColor(r, 235, 235, 240, 255); SDL_RenderDebugText(r, bx.x + 4, bx.y + 3, t);
  }
  TGView v = tg_view();
  if (!v.ok) return;
  float cx = ox + v.o.x, cy = oy + v.o.y;
  static const Uint8 col[3][3] = { { 235, 60, 60 }, { 80, 210, 80 }, { 70, 120, 255 } };
  int naxes = tg.on3d ? 3 : 2;
  int lit = tg.dragging ? tg.active : tg.hot;
  if (tg.mode == TG_ROTATE) {
    if (tg.on3d) {
      SDL_FPoint pts[49];
      bool fr[49];
      for (int a = 0; a < 3; a++) {
        int n = tg_ring3d(&v, a, pts, 49, fr);
        bool h = lit == TG_X + a, whole = tg.dragging && tg.active == TG_X + a;   // (semicircles; the one dragged whole)
        SDL_SetRenderDrawColor(r, h ? 255 : col[a][0], h ? 230 : col[a][1], h ? 60 : col[a][2], 255);
        for (int i = 0; i + 1 < n; i++) if (whole || (fr[i] && fr[i + 1])) tg_line(r, ox + pts[i].x, oy + pts[i].y, ox + pts[i + 1].x, oy + pts[i + 1].y, h ? 3 : 2);
      }
      bool h = lit == TG_VIEW;                     // (the outer ring, orange: about the line to the camera)
      float R = TG_RING * TG_VRING * v.g;
      SDL_SetRenderDrawColor(r, 255, h ? 230 : 150, h ? 60 : 30, 255);
      for (int i = 0; i < 64; i++) {
        float t0 = i * 6.2831853f / 64, t1 = (i + 1) * 6.2831853f / 64;
        tg_line(r, cx + cosf(t0) * R, cy + sinf(t0) * R, cx + cosf(t1) * R, cy + sinf(t1) * R, h ? 3 : 2);
      }
    } else {
      bool h = lit == TG_Z;
      SDL_SetRenderDrawColor(r, h ? 255 : col[2][0], h ? 230 : col[2][1], h ? 60 : col[2][2], 255);
      for (int i = 0; i < 64; i++) {
        float t0 = i * 6.2831853f / 64, t1 = (i + 1) * 6.2831853f / 64;
        tg_line(r, cx + cosf(t0) * TG_RING, cy + sinf(t0) * TG_RING, cx + cosf(t1) * TG_RING, cy + sinf(t1) * TG_RING, h ? 3 : 2);
      }
    }
  } else {
    for (int a = 0; a < naxes; a++) {
      if (v.len[a] < 0.15f) continue;
      bool h = lit == TG_X + a;
      float L = TG_LEN * v.len[a], ex = cx + v.dir[a][0] * L, ey = cy + v.dir[a][1] * L;
      SDL_SetRenderDrawColor(r, h ? 255 : col[a][0], h ? 230 : col[a][1], h ? 60 : col[a][2], 255);
      tg_line(r, cx, cy, ex, ey, h ? 3 : 2);
      if (tg.mode == TG_MOVE) {                    // (an arrow head)
        float bx = -v.dir[a][0], by = -v.dir[a][1], px = -by, py = bx;
        for (int k = 0; k < 9; k++) tg_line(r, ex, ey, ex + bx * 10 + px * (k - 4), ey + by * 10 + py * (k - 4), 1);
      } else {                                     // (a box)
        SDL_FRect b = { ex - TG_BOX, ey - TG_BOX, TG_BOX * 2, TG_BOX * 2 };
        SDL_RenderFillRect(r, &b);
      }
    }
    if (tg.on3d && tg.mode == TG_MOVE)             // (the plane squares: the colour of the axis they face)
      for (int n = 0; n < 3; n++) {
        int a = (n + 1) % 3, b = (n + 2) % 3;
        float sq;
        if (!tg_plane_at(&v, n, v.o.x, v.o.y, &sq, &sq)) continue;
        bool h = lit == TG_PX + n;
        float ux = v.dir[a][0] * TG_LEN * v.len[a], uy = v.dir[a][1] * TG_LEN * v.len[a];
        float wx = v.dir[b][0] * TG_LEN * v.len[b], wy = v.dir[b][1] * TG_LEN * v.len[b];
        SDL_FPoint q[4] = { { cx + ux * TG_P0 + wx * TG_P0, cy + uy * TG_P0 + wy * TG_P0 }, { cx + ux * TG_P1 + wx * TG_P0, cy + uy * TG_P1 + wy * TG_P0 },
                            { cx + ux * TG_P1 + wx * TG_P1, cy + uy * TG_P1 + wy * TG_P1 }, { cx + ux * TG_P0 + wx * TG_P1, cy + uy * TG_P0 + wy * TG_P1 } };
        SDL_FColor fc = { h ? 1.f : col[n][0] / 255.f, h ? 0.9f : col[n][1] / 255.f, h ? 0.25f : col[n][2] / 255.f, h ? 0.75f : 0.4f };
        SDL_Vertex vx[4];
        for (int k = 0; k < 4; k++) { vx[k].position = q[k]; vx[k].color = fc; vx[k].tex_coord = (SDL_FPoint){ 0, 0 }; }
        static const int idx[6] = { 0, 1, 2, 0, 2, 3 };
        SDL_RenderGeometry(r, NULL, vx, 4, idx, 6);
        SDL_SetRenderDrawColor(r, h ? 255 : col[n][0], h ? 230 : col[n][1], h ? 60 : col[n][2], 255);
        for (int k = 0; k < 4; k++) SDL_RenderLine(r, q[k].x, q[k].y, q[(k + 1) % 4].x, q[(k + 1) % 4].y);
      }
    bool h = lit == TG_FREE;
    float hb = tg.mode == TG_SCALE ? TG_SBOX : TG_BOX;   // (scale: a bigger, white box: the whole size, evenly)
    SDL_FRect b = { cx - hb, cy - hb, hb * 2, hb * 2 };
    if (tg.mode == TG_SCALE) SDL_SetRenderDrawColor(r, 255, 255, h ? 120 : 255, 255);
    else SDL_SetRenderDrawColor(r, 255, h ? 255 : 220, h ? 120 : 60, 255);
    SDL_RenderFillRect(r, &b);
    if (tg.mode == TG_SCALE) { SDL_SetRenderDrawColor(r, 40, 40, 40, 255); SDL_RenderRect(r, &b); }
  }
}

// Lua: the drag's begin, steps, end (boot.lua)
static bool tg_call(Viewer *V, const char *fn, const float *v, int n, float *out, int nout) {
  lua_State *L = V->L;
  int base = lua_gettop(L);
  lua_getglobal(L, fn);
  lua_rawgeti(L, LUA_REGISTRYINDEX, V->world);
  int args = 1;
  if (!v) { lua_pushstring(L, tg.path); args++; }
  for (int i = 0; v && i < n; i++) { lua_pushnumber(L, v[i]); args++; }
  bool ok = false;
  if (lua_pcall(L, args, nout ? nout : 1, 0) != 0) ov_log(OV_ERROR, "gizmo: %s", lua_tostring(L, -1));
  else {
    ok = lua_toboolean(L, base + 1) || (nout && lua_isnumber(L, base + 1));
    for (int i = 0; i < nout; i++) out[i] = (float)lua_tonumber(L, base + 1 + i);
  }
  lua_settop(L, base);
  return ok;
}
static float tg_snap(float v, float q) { return SDL_floorf(v / q + 0.5f) * q; }

static bool tg_press(Viewer *V, float gx, float gy) {   // (an LMB press in the game view, picking's coordinates) -> taken
  if (V->standalone || !ed_editing(V) || V->world == LUA_NOREF) return false;
  TGView v = tg_view();
  int h = tg_hit(&v, gx, gy);
  if (h >= TG_BTN_MOVE && h <= TG_BTN_SCALE) { tg.mode = h - TG_BTN_MOVE; return true; }
  if (h == TG_BTN_SPACE) { tg.local = !tg.local; return true; }
  if (h == TG_BTN_SNAP) {                         // (a click: the next step; past the biggest, off; off: the smallest)
    if (!tg.snap) { tg.snap = true; tg.snap_i = 0; } else if (tg.snap_i < 3) tg.snap_i++; else tg.snap = false;
    return true;
  }
  if (h == TG_BTN_GRID) { tg.grid = !tg.grid; return true; }
  if (h == TG_NONE) return false;
  if (tg.on3d) {
    float out[9];
    if (!tg_call(V, "viewer_move3d_begin", NULL, 0, out, 9)) return false;
    SDL_memcpy(tg.S, out, sizeof tg.S);
    const Cam3D *c = &cams3d[tg.cam];
    if (!tg_ray(c, gx, gy, tg.O0, tg.D0)) return false;
    tg.P0[0] = tg.M3[12]; tg.P0[1] = tg.M3[13]; tg.P0[2] = tg.M3[14];
    float O[3], D[3];                              // (the outer ring's axis: from the node to the camera)
    if (tg_ray(c, v.o.x, v.o.y, O, D)) { tg.vax[0] = -D[0]; tg.vax[1] = -D[1]; tg.vax[2] = -D[2]; }
    else { tg.vax[0] = -tg.D0[0]; tg.vax[1] = -tg.D0[1]; tg.vax[2] = -tg.D0[2]; }
  } else {
    lua_State *L = V->L;                           // (2D: the same as dragging a node, viewer_move_*)
    int base = lua_gettop(L);
    lua_getglobal(L, "viewer_move_begin");
    lua_rawgeti(L, LUA_REGISTRYINDEX, V->world);
    lua_pushstring(L, tg.path);
    bool ok = lua_pcall(L, 2, 1, 0) == 0 && lua_toboolean(L, -1);
    lua_settop(L, base);
    if (!ok) return false;
  }
  if (V->selected[0]) {                            // (more selected: they move with it, boot.lua viewer_move_with)
    lua_State *L = V->L;
    int base = lua_gettop(L);
    lua_getglobal(L, "viewer_move_with");
    lua_rawgeti(L, LUA_REGISTRYINDEX, V->world);
    push_selection(L, V);
    if (lua_pcall(L, 2, 0, 0) != 0) ov_log(OV_ERROR, "gizmo: %s", lua_tostring(L, -1));
    lua_settop(L, base);
  }
  tg.active = h; tg.dragging = true;
  tg.gx0 = tg.gx = gx; tg.gy0 = tg.gy = gy;
  tg.applied[0] = tg.applied[1] = 0; tg.applied[2] = tg.mode == TG_SCALE ? 1 : 0;
  return true;
}
static void tg_hover(float gx, float gy) { if (!tg.dragging) { TGView v = tg_view(); tg.hot = tg_hit(&v, gx, gy); } }

static void tg_drag(Viewer *V, float gx, float gy, float zoom) {   // zoom: game-view points a world unit (2D)
  if (!tg.dragging) return;
  tg.gx = gx; tg.gy = gy;
  bool snap = ((SDL_GetModState() & SDL_KMOD_CTRL) != 0) != tg.snap;   // (Snap on: always; CTRL flips it)
  float q_m3 = TG_SNAP_M3[tg.snap_i], q_m2 = TG_SNAP_M2[tg.snap_i], q_a = TG_SNAP_DEG[tg.snap_i] * SDL_PI_F / 180, q_s = TG_SNAP_S[tg.snap_i];
  TGView v = tg_view();
  float mx = gx - tg.gx0, my = gy - tg.gy0;
  if (!tg.on3d) {
    float dx = 0, dy = 0, dr = 0, ds = 1, dsx = 1, dsy = 1;
    if (tg.mode == TG_MOVE) {
      float wx = mx / zoom, wy = my / zoom;
      if ((tg.active == TG_X || tg.active == TG_Y) && tg.local) {   // (Local: along its own axis)
        const float *d = v.dir[tg.active - TG_X];
        float t = wx * d[0] + wy * d[1];
        if (snap) t = tg_snap(t, q_m2);
        wx = t * d[0]; wy = t * d[1];
      } else {
        if (tg.active == TG_X) wy = 0; else if (tg.active == TG_Y) wx = 0;
        if (snap) { wx = tg_snap(wx, q_m2); wy = tg_snap(wy, q_m2); }
      }
      dx = wx - tg.applied[0]; dy = wy - tg.applied[1];
      tg.applied[0] = wx; tg.applied[1] = wy;
    } else if (tg.mode == TG_ROTATE) {
      float a0 = atan2f(tg.gy0 - v.o.y, tg.gx0 - v.o.x), a1 = atan2f(gy - v.o.y, gx - v.o.x), a = a1 - a0;
      while (a > SDL_PI_F) a -= 2 * SDL_PI_F;
      while (a < -SDL_PI_F) a += 2 * SDL_PI_F;
      if (snap) a = tg_snap(a, q_a);
      dr = a - tg.applied[2]; tg.applied[2] = a;
    } else {
      float f;
      if (tg.active == TG_FREE) f = 1 + (mx - my) / (TG_LEN * 2);
      else { int a = tg.active - TG_X; f = 1 + (mx * v.dir[a][0] + my * v.dir[a][1]) / TG_LEN; }
      f = SDL_max(f, 0.01f);
      if (snap) f = SDL_max(q_s, tg_snap(f, q_s));
      float k = f / tg.applied[2];
      tg.applied[2] = f;
      if (tg.active == TG_FREE) ds = k; else if (tg.active == TG_X) dsx = k; else dsy = k;
    }
    lua_State *L = V->L;
    int base = lua_gettop(L);
    lua_getglobal(L, "viewer_move_by");
    lua_rawgeti(L, LUA_REGISTRYINDEX, V->world);
    lua_pushnumber(L, dx); lua_pushnumber(L, dy); lua_pushnumber(L, dr); lua_pushnumber(L, ds); lua_pushnumber(L, dsx); lua_pushnumber(L, dsy);
    if (lua_pcall(L, 7, 1, 0) != 0) ov_log(OV_ERROR, "gizmo: %s", lua_tostring(L, -1));
    lua_settop(L, base);
    return;
  }
  // 3D: totals since the press, set (boot.lua viewer_move3d_set): place, turn, size in its parent's space
  const Cam3D *c = &cams3d[tg.cam];
  float O[3], D[3];
  if (!tg_ray(c, gx, gy, O, D)) return;
  float T[9];
  SDL_memcpy(T, tg.S, sizeof T);
  float Pinv[16];
  if (!m4_invert(tg.P3, Pinv)) m4_identity(Pinv);
  if (tg.mode == TG_MOVE) {
    float dw[3] = { 0, 0, 0 };
    if (tg.active == TG_FREE || tg.active >= TG_PX) {   // (in a plane through where it was: facing the camera, or a square's)
      float n[3] = { tg.D0[0], tg.D0[1], tg.D0[2] };
      if (tg.active >= TG_PX) SDL_memcpy(n, v.wax[tg.active - TG_PX], sizeof n);
      float n0 = tg.D0[0] * n[0] + tg.D0[1] * n[1] + tg.D0[2] * n[2];
      if (fabsf(n0) < 1e-6f) return;
      float h0[3], h1[3];
      float t0 = ((tg.P0[0] - tg.O0[0]) * n[0] + (tg.P0[1] - tg.O0[1]) * n[1] + (tg.P0[2] - tg.O0[2]) * n[2]) / n0;
      float d1 = D[0] * n[0] + D[1] * n[1] + D[2] * n[2];
      if (fabsf(d1) < 1e-6f) return;
      float t1 = ((tg.P0[0] - O[0]) * n[0] + (tg.P0[1] - O[1]) * n[1] + (tg.P0[2] - O[2]) * n[2]) / d1;
      for (int k = 0; k < 3; k++) { h0[k] = tg.O0[k] + tg.D0[k] * t0; h1[k] = O[k] + D[k] * t1; dw[k] = h1[k] - h0[k]; }
    } else {                                       // (along the axis: its nearest point to each ray)
      int a = tg.active - TG_X;
      const float *ax = v.wax[a];
      float s[2];
      const float *Os[2] = { tg.O0, O }, *Ds[2] = { tg.D0, D };
      for (int q = 0; q < 2; q++) {
        float w0[3] = { tg.P0[0] - Os[q][0], tg.P0[1] - Os[q][1], tg.P0[2] - Os[q][2] };
        float b = ax[0] * Ds[q][0] + ax[1] * Ds[q][1] + ax[2] * Ds[q][2];
        float d = ax[0] * w0[0] + ax[1] * w0[1] + ax[2] * w0[2], e = Ds[q][0] * w0[0] + Ds[q][1] * w0[1] + Ds[q][2] * w0[2];
        float den = 1 - b * b;
        if (fabsf(den) < 1e-6f) return;
        s[q] = (b * e - d) / den;
      }
      float ds_ = s[1] - s[0];
      if (snap) ds_ = tg_snap(ds_, q_m3);
      for (int k = 0; k < 3; k++) dw[k] = ax[k] * ds_;
    }
    if (snap && (tg.active == TG_FREE || tg.active >= TG_PX)) for (int k = 0; k < 3; k++) dw[k] = tg_snap(dw[k], q_m3);
    float dp[3];
    m4_point(Pinv, dw, 0, dp);                     // (into its parent's space)
    T[0] += dp[0]; T[1] += dp[1]; T[2] += dp[2];
  } else if (tg.mode == TG_ROTATE) {
    float a0 = atan2f(tg.gy0 - v.o.y, tg.gx0 - v.o.x), a1 = atan2f(gy - v.o.y, gx - v.o.x), ang = a1 - a0;
    while (ang > SDL_PI_F) ang -= 2 * SDL_PI_F;
    while (ang < -SDL_PI_F) ang += 2 * SDL_PI_F;
    float to_eye[3] = { -tg.D0[0], -tg.D0[1], -tg.D0[2] };   // (the axis toward the camera: clockwise on screen is negative)
    float wa[3] = { 0, 0, 0 };
    if (tg.active == TG_VIEW) SDL_memcpy(wa, tg.vax, sizeof wa); else SDL_memcpy(wa, v.wax[tg.active - TG_X], sizeof wa);   // (the world's axis, or its own)
    if (wa[0] * to_eye[0] + wa[1] * to_eye[1] + wa[2] * to_eye[2] > 0) ang = -ang;
    if (snap) ang = tg_snap(ang, q_a);
    float pa[3];                                   // (the axis in its parent's space)
    m4_point(Pinv, wa, 0, pa);
    v3_norm(pa);
    float R0[16], RA[16], R1[16];
    m4_trs(0, 0, 0, tg.S[3], tg.S[4], tg.S[5], 1, 1, 1, R0);
    float c_ = cosf(ang), s_ = sinf(ang), t_ = 1 - c_, x = pa[0], y = pa[1], z = pa[2];   // (Rodrigues)
    float m[16] = { t_ * x * x + c_, t_ * x * y + s_ * z, t_ * x * z - s_ * y, 0,
                    t_ * x * y - s_ * z, t_ * y * y + c_, t_ * y * z + s_ * x, 0,
                    t_ * x * z + s_ * y, t_ * y * z - s_ * x, t_ * z * z + c_, 0, 0, 0, 0, 1 };
    SDL_memcpy(RA, m, sizeof m);
    m4_mul(RA, R0, R1);
    // back to transform3d's angles: R = Ry * Rx * Rz (raster3d.h m4_trs): r12 = -sin(rx), r02 / r22 = tan(ry), r10 / r11 = tan(rz)
    float r02 = R1[8], r12 = R1[9], r22 = R1[10], r10 = R1[1], r11 = R1[5];
    float r00 = R1[0], r20 = R1[2];
    float A[3], B[3];
    A[0] = asinf(SDL_clamp(-r12, -1, 1));
    if (fabsf(r12) > 0.99999f) { A[1] = atan2f(-r20, r00); A[2] = 0; }   // (gimbal lock: rx = +-90 degrees, ry and rz turn the same way: all in ry)
    else { A[1] = atan2f(r02, r22); A[2] = atan2f(r10, r11); }
    B[0] = SDL_PI_F - A[0]; B[1] = A[1] + SDL_PI_F; B[2] = A[2] + SDL_PI_F;   // (the same turn, the other way round)
    float da = 0, db = 0;                          // (the one nearer the angles it had: no flips)
    for (int k = 0; k < 3; k++) {
      for (float *X = A; X; X = X == A ? B : NULL) {
        while (X[k] - tg.S[3 + k] > SDL_PI_F) X[k] -= 2 * SDL_PI_F;
        while (X[k] - tg.S[3 + k] < -SDL_PI_F) X[k] += 2 * SDL_PI_F;
      }
      da += fabsf(A[k] - tg.S[3 + k]); db += fabsf(B[k] - tg.S[3 + k]);
    }
    SDL_memcpy(&T[3], db < da - 1e-4f ? B : A, sizeof A);
  } else {
    float f;
    float gl = TG_LEN * SDL_max(v.g, 0.1f);
    if (tg.active == TG_FREE) f = 1 + (mx - my) / (gl * 2);
    else { int a = tg.active - TG_X; f = 1 + (mx * v.dir[a][0] + my * v.dir[a][1]) / gl; }
    f = SDL_max(f, 0.01f);
    if (snap) f = SDL_max(q_s, tg_snap(f, q_s));
    if (tg.active == TG_FREE) { T[6] *= f; T[7] *= f; T[8] *= f; }
    else T[6 + tg.active - TG_X] *= f;
  }
  tg_call(V, "viewer_move3d_set", T, 9, NULL, 0);
}
static void tg_release(Viewer *V) {
  if (!tg.dragging) return;
  tg.dragging = false;
  lua_State *L = V->L;
  int base = lua_gettop(L);
  lua_getglobal(L, "viewer_move_end");
  lua_rawgeti(L, LUA_REGISTRYINDEX, V->world);
  if (lua_pcall(L, 1, 1, 0) != 0) ov_log(OV_ERROR, "gizmo: %s", lua_tostring(L, -1));
  lua_settop(L, base);
}
static bool tg_key(SDL_Keycode k) {                 // W / E / R / Space: the mode (the game view focused, not playing)
  if (k != SDLK_W && k != SDLK_E && k != SDLK_R && k != SDLK_SPACE) return false;
  if (tg.dragging) return true;                    // (not in the middle of a drag)
  if (k == SDLK_W) tg.mode = TG_MOVE; else if (k == SDLK_E) tg.mode = TG_ROTATE; else if (k == SDLK_R) tg.mode = TG_SCALE;
  else tg.mode = (tg.mode + 1) % 3;                // (Space: the next one: move, rotate, scale)
  tg.hot = TG_NONE;
  return true;
}
// host_gizmo(op, ...) (tests): "info" -> mode, kind ("2d" | "3d" | "none"), x, y (its middle), each axis' end, the rings' radius;
// "mode", m; "opts" [, local, snap, grid, step] -> them; "select", path; "selected" -> path; "time" -> the playhead; "dock" -> docked?, x, y, w, h, lite shown?; "pause"; "players", mask; "toggle", path (in / out of the selection); "drop" -> how many (End); "show"; "press" / "drag" / "release" at game-view points
static int l_host_gizmo(lua_State *L) {
  Viewer *V = tg_V;
  const char *op = luaL_checkstring(L, 1);
  if (!strcmp(op, "mode")) { tg.mode = (int)luaL_checkinteger(L, 2); return 0; }
  if (!strcmp(op, "opts")) {                       // (tests) [local, snap, grid, step 0..3] -> them
    if (lua_gettop(L) >= 2) { tg.local = lua_toboolean(L, 2); tg.snap = lua_toboolean(L, 3); tg.grid = lua_toboolean(L, 4); tg.snap_i = SDL_clamp((int)luaL_optinteger(L, 5, tg.snap_i), 0, 3); }
    lua_pushboolean(L, tg.local); lua_pushboolean(L, tg.snap); lua_pushboolean(L, tg.grid); lua_pushinteger(L, tg.snap_i);
    return 4;
  }
  if (!strcmp(op, "info")) {
    TGView v = tg_view();
    lua_pushinteger(L, tg.mode);
    lua_pushstring(L, tg.on3d ? "3d" : tg.on2d ? "2d" : "none");
    lua_pushnumber(L, v.o.x); lua_pushnumber(L, v.o.y);
    lua_createtable(L, 3, 0);
    for (int a = 0; a < 3; a++) {
      lua_createtable(L, 2, 0);
      lua_pushnumber(L, v.o.x + v.dir[a][0] * TG_LEN * v.len[a]); lua_rawseti(L, -2, 1);
      lua_pushnumber(L, v.o.y + v.dir[a][1] * TG_LEN * v.len[a]); lua_rawseti(L, -2, 2);
      lua_rawseti(L, -2, a + 1);
    }
    lua_pushnumber(L, TG_RING * v.g);              // (the rings' radius on screen)
    return 6;
  }
  if (!V) return 0;
  if (!strcmp(op, "dock")) {                       // (tests) -> docked?, the game view's x, y, w, h
    lua_pushboolean(L, g_dock.on); lua_pushnumber(L, tg_gv.x); lua_pushnumber(L, tg_gv.y); lua_pushnumber(L, tg_gv.w); lua_pushnumber(L, tg_gv.h);
    lua_pushboolean(L, tg_lite_shown);
    return 6;
  }
  if (!strcmp(op, "time")) { lua_pushnumber(L, V->gtime); return 1; }   // (tests: the timeline's playhead, seconds)
  if (!strcmp(op, "selected")) { lua_pushstring(L, V->selected); return 1; }   // (tests: what's selected)
  if (!strcmp(op, "pause")) { if (!V->stopped) V->paused = true; return 0; }   // (tests: picking needs it paused)
  if (!strcmp(op, "players")) { V->pmask = (int)luaL_checkinteger(L, 2) & 15; if (!V->pmask) V->pmask = 1; return 0; }   // (tests: who's in, as the Players button)
  if (!strcmp(op, "show")) { V->af.on = false; V->fade = 1; return 0; }   // (the game view in front: its picture, for a test's shot)
  if (!strcmp(op, "select")) { SDL_strlcpy(V->selected, luaL_checkstring(L, 2), sizeof V->selected); V->via[0] = 0; return 0; }
  if (!strcmp(op, "toggle")) { sel_toggle(V, luaL_checkstring(L, 2)); return 0; }   // (tests: CTRL+click's, more than one selected)
  if (!strcmp(op, "drop")) { lua_pushinteger(L, drop_to_ground(V)); return 1; }   // (tests: End's, the selection onto the ground)
  float x = (float)luaL_optnumber(L, 2, 0), y = (float)luaL_optnumber(L, 3, 0);
  if (!strcmp(op, "press")) { lua_pushboolean(L, tg_press(V, x, y)); return 1; }
  if (!strcmp(op, "drag")) { tg_drag(V, x, y, (float)luaL_optnumber(L, 4, 1)); return 0; }
  if (!strcmp(op, "release")) { tg_release(V); return 0; }
  return 0;
}
