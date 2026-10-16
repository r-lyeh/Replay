// editor/render.h - drawing the world: render components and the node tree walk.
// Part of replay.c: included once, in order, from there (one compilation unit).

// ---------------------------------------------------------------------------
// Lua helpers (all take absolute stack indices)
// ---------------------------------------------------------------------------

static bool gizmo_wanted(Viewer *V, const char *path);   // (ui.h: under a selected node?)
static int absidx(lua_State *L, int i) {
  return (i > 0 || i <= LUA_REGISTRYINDEX) ? i : lua_gettop(L) + i + 1;
}

static double fnum(lua_State *L, int t, const char *k, double def) {
  lua_getfield(L, t, k);
  double v = lua_isnumber(L, -1) ? lua_tonumber(L, -1) : def;
  lua_pop(L, 1);
  return v;
}

static bool fbool(lua_State *L, int t, const char *k) {
  lua_getfield(L, t, k);
  bool v = lua_toboolean(L, -1);
  lua_pop(L, 1);
  return v;
}

static double inum(lua_State *L, int t, int i, double def) {
  lua_rawgeti(L, t, i);
  double v = lua_isnumber(L, -1) ? lua_tonumber(L, -1) : def;
  lua_pop(L, 1);
  return v;
}

// read a color table at index t: {r,g,b,a} or {r=,g=,b=,a=}
static Col read_color(lua_State *L, int t, Col def) {
  if (!lua_istable(L, t)) return def;
  Col c;
  c.r = (Uint8)inum(L, t, 1, fnum(L, t, "r", def.r));
  c.g = (Uint8)inum(L, t, 2, fnum(L, t, "g", def.g));
  c.b = (Uint8)inum(L, t, 3, fnum(L, t, "b", def.b));
  c.a = (Uint8)inum(L, t, 4, fnum(L, t, "a", 255));
  return c;
}

static float g_alpha = 1.f;                        // everything drawn this much (a ghost: faint)

static void set_color(Viewer *V, Col c) {
  SDL_SetRenderDrawColor(V->ren, c.r, c.g, c.b, (Uint8)(c.a * g_alpha));
}

// call world:method(arg at index argi) -> leaves 1 result on the stack
static bool world_call(Viewer *V, const char *method, int argi, const char *sarg) {
  lua_State *L = V->L;
  lua_rawgeti(L, LUA_REGISTRYINDEX, V->world);
  lua_getfield(L, -1, method);
  lua_pushvalue(L, -2);
  if (sarg) lua_pushstring(L, sarg); else lua_pushvalue(L, argi);
  lua_remove(L, -4);                               // drop the world copy
  if (lua_pcall(L, 2, 1, 0) != 0) {
    SDL_snprintf(V->err, sizeof V->err, "%s", lua_tostring(L, -1));
    lua_pop(L, 1);
    lua_pushnil(L);
    return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// drawing the recognised components
// ---------------------------------------------------------------------------

#define MAXPTS 4096
static SDL_FPoint pts[MAXPTS];
static SDL_Vertex verts[MAXPTS * 3];

static SDL_FColor fcol(Col c) {
  SDL_FColor f = { c.r / 255.f, c.g / 255.f, c.b / 255.f, c.a / 255.f * g_alpha };
  return f;
}

static void draw_poly(Viewer *V, int n, bool fill, Col col) {
  if (n < 2) return;
  if (fill && n >= 3) {                            // fan from the first point
    int nv = 0;
    SDL_FColor fc = fcol(col);
    for (int i = 1; i + 1 < n && nv + 3 <= MAXPTS * 3; i++) {
      SDL_FPoint tri[3] = { pts[0], pts[i], pts[i + 1] };
      for (int k = 0; k < 3; k++) {
        verts[nv].position = tri[k]; verts[nv].color = fc;
        verts[nv].tex_coord.x = verts[nv].tex_coord.y = 0; nv++;
      }
    }
    SDL_RenderGeometry(V->ren, NULL, verts, nv, NULL, 0);
    acc_solid = true;
  } else {
    set_color(V, col);
    SDL_RenderLines(V->ren, pts, n);
    acc_stroke(pts, n);
  }
}

static void draw_lines(Viewer *V, int t, Mat M, Col col) {
  lua_State *L = V->L;
  int len = (int)objlen(L, t), n = 0;
  for (int i = 1; i + 1 <= len && n < MAXPTS - 1; i += 2)
    pts[n++] = xfa(M, (float)inum(L, t, i, 0), (float)inum(L, t, i + 1, 0));
  if (fbool(L, t, "loop") && n > 2) pts[n++] = pts[0];
  draw_poly(V, n, false, col);
}

static void draw_tris(Viewer *V, int t, Mat M, Col col) {
  lua_State *L = V->L;
  int len = (int)objlen(L, t), nv = 0;
  SDL_FColor fc = fcol(col);
  for (int i = 1; i + 5 <= len && nv + 3 <= MAXPTS * 3; i += 6) {
    for (int k = 0; k < 3; k++) {
      verts[nv].position = xfa(M, (float)inum(L, t, i + k * 2, 0), (float)inum(L, t, i + k * 2 + 1, 0));
      verts[nv].color = fc;
      verts[nv].tex_coord.x = verts[nv].tex_coord.y = 0;
      nv++;
    }
  }
  if (nv) SDL_RenderGeometry(V->ren, NULL, verts, nv, NULL, 0);
  acc_solid = true;
}

static void draw_rect(Viewer *V, int t, Mat M, Col col) {
  float w = (float)fnum(V->L, t, "w", 10) / 2, h = (float)fnum(V->L, t, "h", 10) / 2;
  pts[0] = xfa(M, -w, -h); pts[1] = xfa(M, w, -h);
  pts[2] = xfa(M, w, h);   pts[3] = xfa(M, -w, h); pts[4] = pts[0];
  bool fill = fbool(V->L, t, "fill");
  draw_poly(V, fill ? 4 : 5, fill, col);
}

static void draw_circle(Viewer *V, int t, Mat M, Col col) {
  float r = (float)fnum(V->L, t, "r", 10);
  int n = (int)fnum(V->L, t, "n", 24);
  if (n < 3) n = 3;
  if (n > MAXPTS - 2) n = MAXPTS - 2;
  for (int i = 0; i <= n; i++) {
    float a = (float)i / n * 6.2831853f;
    pts[i] = xfa(M, r * cosf(a), r * sinf(a));
  }
  bool fill = fbool(V->L, t, "fill");
  draw_poly(V, fill ? n : n + 1, fill, col);
}

static bool ttf_draw(Viewer *V, int t, Mat M, Col col, const char *s);   // (below: text = { ..., font = "x.ttf" })
static void draw_text(Viewer *V, int t, Mat M, Col col) {
  lua_State *L = V->L;
  const char *s = NULL;
  if (lua_type(L, t) == LUA_TSTRING) s = lua_tostring(L, t);
  else if (lua_istable(L, t)) {
    lua_rawgeti(L, t, 1);
    s = lua_tostring(L, -1);
    lua_pop(L, 1);                 // string stays alive: it lives in the table
  }
  if (!s) return;
  if (lua_istable(L, t) && ttf_draw(V, t, M, col, s)) return;   // (a TrueType font: its own way)
  float k = 1;                                     // text = { "big", size = 4 }: scaled
  if (lua_istable(L, t)) {                         // font, also by the transform/zoom
    double size = fnum(L, t, "size", 0);
    if (size > 0) k = (float)(size * SDL_sqrt(M.a * M.a + M.b * M.b));
    if (k < 0.25f) k = 0.25f;
  }
  SDL_FPoint p = xfa(M, 0, 0);
  acc_add(p.x, p.y);
  acc_add(p.x + 8.f * k * (float)strlen(s), p.y + 8.f * k);  // debug font is 8x8
  acc_solid = true;
  set_color(V, col);
  if (k == 1) { SDL_RenderDebugText(V->ren, p.x, p.y, s); return; }
  SDL_Rect clip;                                   // (a clip rect scales too: a player's view, players.h)
  bool clipped = SDL_RenderClipEnabled(V->ren) && SDL_GetRenderClipRect(V->ren, &clip);
  float s0x = 1, s0y = 1;                          // (on top of the scale already set: retina)
  SDL_GetRenderScale(V->ren, &s0x, &s0y);
  SDL_SetRenderScale(V->ren, k * s0x, k * s0y);
  if (clipped) {
    SDL_Rect c = { (int)SDL_floorf(clip.x / k), (int)SDL_floorf(clip.y / k), (int)SDL_ceilf(clip.w / k), (int)SDL_ceilf(clip.h / k) };
    SDL_SetRenderClipRect(V->ren, &c);
  }
  SDL_RenderDebugText(V->ren, p.x / k, p.y / k, s);
  SDL_SetRenderScale(V->ren, s0x, s0y);
  if (clipped) SDL_SetRenderClipRect(V->ren, &clip);
}

// sprite = { "row", "row", ..., palette = { ["#"] = {r,g,b,a} }, px = 1 }
static void draw_sprite(Viewer *V, int t, Mat M, Col col) {
  lua_State *L = V->L;
  int rows = (int)objlen(L, t), nv = 0;
  float px = (float)fnum(L, t, "px", 1);
  lua_getfield(L, t, "palette");
  int pal = lua_gettop(L);
  int cols = 0;
  for (int y = 1; y <= rows; y++) {
    lua_rawgeti(L, t, y);
    size_t w = 0;
    lua_tolstring(L, -1, &w);
    if ((int)w > cols) cols = (int)w;
    lua_pop(L, 1);
  }
  float ox = -cols * px / 2, oy = -rows * px / 2;
  for (int y = 0; y < rows; y++) {
    lua_rawgeti(L, t, y + 1);
    size_t w = 0;
    const char *row = lua_tolstring(L, -1, &w);
    for (int x = 0; row && x < (int)w; x++) {
      char ch = row[x];
      if (ch == '.' || ch == ' ') continue;
      Col c = col;
      if (lua_istable(L, pal)) {
        char key[2] = { ch, 0 };
        lua_getfield(L, pal, key);
        c = read_color(L, lua_gettop(L), col);
        lua_pop(L, 1);
      }
      if (nv + 6 > MAXPTS * 3) break;
      float x0 = ox + x * px, y0 = oy + y * px;
      SDL_FPoint q[4] = { xfa(M, x0, y0), xfa(M, x0 + px, y0),
                          xfa(M, x0 + px, y0 + px), xfa(M, x0, y0 + px) };
      int idx[6] = { 0, 1, 2, 0, 2, 3 };
      SDL_FColor fc = fcol(c);
      for (int k = 0; k < 6; k++) {
        verts[nv].position = q[idx[k]]; verts[nv].color = fc;
        verts[nv].tex_coord.x = verts[nv].tex_coord.y = 0; nv++;
      }
    }
    lua_pop(L, 1);
  }
  lua_pop(L, 1);                   // palette
  if (nv) SDL_RenderGeometry(V->ren, NULL, verts, nv, NULL, 0);
  acc_solid = true;
}

// image = "/assets/ship.png"  or  { "/assets/ship.png", w = 32, h = 32,
//          color = { r, g, b, a }, smooth = false, src = { x, y, w, h }, ax =, ay =,
//          outline1 = { r, g, b, a }, outline2 = { r, g, b, a } }
//          or { "/assets/ui.atlas.lua", frame = "ship" } (atlas_get, below)
// A picture from the game's assets/ folder (a folder world's; a script's: the
// common/ folder beside it, shared by the single-file games), centred on the node, w x h world units (default: its
// size in pixels), turning and scaling with the transform. `color` tints it
// (default: as it is; the node's colour doesn't). smooth = false: crisp
// pixels when scaled. Read again when its file changes on disk. outline1: a
// 1 px outline round its opaque pixels (the picture's pixels), outline2 one
// more px round that (runtime/anim.lua's frames carry them: a:image).
typedef struct { int x, y, w, h, r; SDL_Texture *t; } TexOutline;   // (an outline of a part of it, r px: tex_outline)
typedef struct { char file[1024]; SDL_Texture *tex; int w, h; SDL_Time mtime; Uint64 checked; bool smooth;
                 unsigned char *px; TexOutline ol[32]; int nol; } Tex;
static Tex texs[256];
static int ntexs;

static SDL_Texture *g_dot_tex;                     // (bullets' soft dot: draw_bullets)
static void tex_reset(void) {                      // (the renderer lost its textures: read them again)
  if (g_dot_tex) { SDL_DestroyTexture(g_dot_tex); g_dot_tex = NULL; }
  for (int i = 0; i < ntexs; i++) {
    if (texs[i].tex) SDL_DestroyTexture(texs[i].tex);
    for (int k = 0; k < texs[i].nol; k++) if (texs[i].ol[k].t) SDL_DestroyTexture(texs[i].ol[k].t);
    SDL_free(texs[i].px);
  }
  ntexs = 0;
}

static char g_export_root[1024];                 // (export.h's: where runtime/ and plugins/ are)
// "plugin:tiles.png" (a tile map's tileset: plugins/tilemap's own) -> <root>plugins/tilemap/tiles.png
static void tex_file(Viewer *V, const char *name, char *out, size_t size) {
  if (!strncmp(name, "plugin:", 7)) { SDL_snprintf(out, size, "%splugins/tilemap/%s", g_export_root, name + 7); return; }
  char dir[1024];
  SDL_strlcpy(dir, V->path, sizeof dir);
  if (!V->isdir) {                                 // (a script: its folder)
    char *a = SDL_strrchr(dir, '/'), *b = SDL_strrchr(dir, '\\');
    char *e = a > b ? a : b;
    if (e) *e = 0;
  }
  if (!strncmp(name, "/assets/", 8)) name += 8;
  else if (name[0] == '/') name++;
  SDL_snprintf(out, size, "%s/%s/%s", dir, V->isdir ? "assets" : "common", name);   // (a script's: common/ beside it, shared)
}

// TrueType text (SDL3_ttf): text = { "Hello 🙂", font = "/assets/x.ttf" | "sans" |
// "sans-bold" | "mono", size = 24 (pixels), align = "left" | "center" | "right",
// width = 200 (wrapped to it, in the node's units; "\n" breaks a line too; the
// lines aligned in it), shear = 0.2 (slanted: its top leans right by that much
// of its height, a cursive; negative: left), fallback = "/assets/emoji.ttf"
// (glyphs the font lacks: emoji...), shadow = true (or its colour: a dark copy
// under it, to read over anything) }. Drawn from the node's place (its top
// left; centre / right: that edge there) with the node's whole transform:
// moved, turned, scaled, sheared (transform.shear) like any drawing; rendered at
// the size it shows (the scale and the zoom: sharp), a texture cached per
// text, font, size, width and colour. Built-in fonts: runtime/fonts/
// (Roboto, Roboto Mono: Apache 2.0). Colour emoji need a colour emoji font
// (Noto Color Emoji, Twemoji...) and a FreeType that reads it. No font, or
// it can't be read: the 8 x 8 font, as without `font`.
typedef struct { char file[1024], fb[1024]; int px; TTF_Font *f, *ff; Uint64 used; } TFont;
typedef struct { TFont *font; int px, wrap, align; Uint32 rgb; char *s; SDL_Texture *tex; int w, h; SDL_Renderer *ren; Uint64 used; } TText;
static TFont tfonts[16];
static TText ttexts[256];
static void ttf_text_free(TText *x) { if (x->tex) SDL_DestroyTexture(x->tex); SDL_free(x->s); SDL_zerop(x); }
static void ttf_reset(void) { for (int i = 0; i < (int)SDL_arraysize(ttexts); i++) if (ttexts[i].s) ttf_text_free(&ttexts[i]); }   // (the GPU lost its textures: made again)
static void font_file(Viewer *V, const char *name, char *out, size_t n) {
  if (!SDL_strcmp(name, "sans") || !SDL_strcmp(name, "sans-bold") || !SDL_strcmp(name, "mono")) {
    SDL_snprintf(out, n, "%sruntime/fonts/%s.ttf", g_export_root, name);
    return;
  }
  tex_file(V, name, out, n);
}
static TTF_Font *font_get(Viewer *V, const char *name, const char *fallback, int px, TFont **slot) {
  if (!TTF_WasInit()) return NULL;
  char file[1024], fb[1024] = { 0 };
  font_file(V, name, file, sizeof file);
  if (fallback) font_file(V, fallback, fb, sizeof fb);
  TFont *best = NULL, *old = &tfonts[0];
  for (int i = 0; i < (int)SDL_arraysize(tfonts); i++) {
    TFont *f = &tfonts[i];
    if (f->f && f->px == px && !SDL_strcmp(f->file, file) && !SDL_strcmp(f->fb, fb)) { best = f; break; }
    if (!f->f) { old = f; if (old->used == 0) break; }
    else if (f->used < old->used) old = f;
  }
  if (!best) {
    if (old->f) {                                  // (the least used: closed, its texts with it)
      for (int i = 0; i < (int)SDL_arraysize(ttexts); i++)
        if (ttexts[i].font == old && ttexts[i].s) ttf_text_free(&ttexts[i]);
      TTF_CloseFont(old->f);
      if (old->ff) TTF_CloseFont(old->ff);
    }
    SDL_zerop(old);
    old->f = TTF_OpenFont(file, (float)px);
    if (!old->f) return NULL;
    if (fb[0]) { old->ff = TTF_OpenFont(fb, (float)px); if (old->ff) TTF_AddFallbackFont(old->f, old->ff); }   // (kept open with it, closed with it)
    SDL_strlcpy(old->file, file, sizeof old->file);
    SDL_strlcpy(old->fb, fb, sizeof old->fb);
    old->px = px;
    best = old;
  }
  best->used = SDL_GetTicksNS();
  if (slot) *slot = best;
  return best->f;
}
// a text's texture (white on clear for the shadow: its colour then; else in its colour)
static TText *ttf_text(Viewer *V, TFont *tf, TTF_Font *f, int px, int wrap, int align, SDL_Color c, const char *s) {
  Uint32 rgb = ((Uint32)c.r << 16) | ((Uint32)c.g << 8) | c.b;
  TText *tt = NULL, *old = &ttexts[0];
  for (int i = 0; i < (int)SDL_arraysize(ttexts); i++) {
    TText *x = &ttexts[i];
    if (x->s && x->font == tf && x->px == px && x->wrap == wrap && x->align == align && x->rgb == rgb && x->ren == V->ren && !SDL_strcmp(x->s, s)) { tt = x; break; }
    if (!x->s) { old = x; if (old->used == 0) break; }
    else if (x->used < old->used) old = x;
  }
  if (!tt) {                                       // (made once, kept while it's drawn: a score changing makes a new one)
    if (old->s) ttf_text_free(old);
    TTF_SetFontWrapAlignment(f, align == 1 ? TTF_HORIZONTAL_ALIGN_CENTER : align == 2 ? TTF_HORIZONTAL_ALIGN_RIGHT : TTF_HORIZONTAL_ALIGN_LEFT);
    SDL_Surface *sf = TTF_RenderText_Blended_Wrapped(f, s, 0, (SDL_Color){ c.r, c.g, c.b, 255 }, wrap);
    if (!sf) return NULL;
    old->tex = SDL_CreateTextureFromSurface(V->ren, sf);
    old->w = sf->w; old->h = sf->h;
    SDL_DestroySurface(sf);
    if (!old->tex) return NULL;
    SDL_SetTextureBlendMode(old->tex, SDL_BLENDMODE_BLEND);
    SDL_SetTextureScaleMode(old->tex, SDL_SCALEMODE_LINEAR);
    old->font = tf; old->px = px; old->wrap = wrap; old->align = align; old->rgb = rgb; old->ren = V->ren; old->s = SDL_strdup(s);
    tt = old;
  }
  tt->used = SDL_GetTicksNS();
  return tt;
}
// its quad: in the node's units (the texture's pixels / k), from x0, its top leaning `shear`
static void ttf_quad(Viewer *V, Mat M, TText *tt, float k, float x0, float y0, float shear, Uint8 alpha, bool pick) {
  float w = tt->w / k, h = tt->h / k;
  SDL_FPoint q[4] = { xfa(M, x0 + shear * h, y0), xfa(M, x0 + w + shear * h, y0), xfa(M, x0 + w, y0 + h), xfa(M, x0, y0 + h) };
  static const float uv[4][2] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } };
  SDL_Vertex v[4];
  for (int i = 0; i < 4; i++) {
    v[i].position = q[i]; v[i].color = (SDL_FColor){ 1, 1, 1, alpha / 255.f };
    v[i].tex_coord.x = uv[i][0]; v[i].tex_coord.y = uv[i][1];
    if (pick) acc_add(q[i].x, q[i].y);
  }
  static const int idx[6] = { 0, 1, 2, 0, 2, 3 };
  SDL_RenderGeometry(V->ren, tt->tex, v, 4, idx, 6);
}
static bool ttf_draw(Viewer *V, int t, Mat M, Col col, const char *s) {
  lua_State *L = V->L;
  lua_getfield(L, t, "font");
  const char *fname = lua_tostring(L, -1);
  lua_pop(L, 1);                                   // (it lives in the table)
  if (!fname) return false;
  lua_getfield(L, t, "fallback");
  const char *fb = lua_tostring(L, -1);
  lua_pop(L, 1);
  lua_getfield(L, t, "align");
  const char *align = lua_tostring(L, -1);
  lua_pop(L, 1);
  int al = align && !SDL_strcmp(align, "center") ? 1 : align && !SDL_strcmp(align, "right") ? 2 : 0;
  float scale = SDL_sqrtf(SDL_fabsf(M.a * M.d - M.b * M.c));   // (the area's scale: turned, sheared or not, the size it shows)
  if (scale <= 0) return true;
  int px = (int)SDL_roundf((float)fnum(L, t, "size", 16) * scale);
  if (px < 4) px = 4;
  if (px > 512) px = 512;
  float k = px / (float)fnum(L, t, "size", 16);    // (texture pixels per node unit)
  if (k <= 0) k = 1;
  float width = (float)fnum(L, t, "width", 0);
  int wrap = width > 0 ? (int)SDL_roundf(width * k) : 0;
  float shear = (float)fnum(L, t, "shear", 0);
  TFont *tf = NULL;
  TTF_Font *f = font_get(V, fname, fb, px, &tf);
  if (!f) return false;
  TText *tt = ttf_text(V, tf, f, px, wrap, al, (SDL_Color){ col.r, col.g, col.b, 255 }, s);
  if (!tt) return false;
  float w = tt->w / k;
  float box = wrap > 0 ? width : w;                // (wrapped: aligned in its width; else at the node)
  float x0 = al == 1 ? -box / 2 : al == 2 ? -box : 0;
  if (wrap > 0 && al == 1) x0 += (box - w) / 2;   // (a wrapped text narrower than its width: its lines centred / right in it)
  else if (wrap > 0 && al == 2) x0 += box - w;
  acc_solid = true;
  lua_getfield(L, t, "shadow");                    // (shadow = true: a dark copy under it, down right; or its colour { r, g, b [, a] })
  if (lua_toboolean(L, -1)) {
    int sc[4] = { 0, 0, 0, col.a * 3 / 4 };
    if (lua_istable(L, -1))
      for (int i = 0; i < 4; i++) { lua_rawgeti(L, -1, i + 1); if (lua_isnumber(L, -1)) sc[i] = (int)lua_tonumber(L, -1); lua_pop(L, 1); }
    TText *sh = ttf_text(V, tf, f, px, wrap, al, (SDL_Color){ (Uint8)SDL_clamp(sc[0], 0, 255), (Uint8)SDL_clamp(sc[1], 0, 255), (Uint8)SDL_clamp(sc[2], 0, 255), 255 }, s);
    float d = px / 14.f < 1 ? 1 : px / 14.f;
    if (sh) ttf_quad(V, M, sh, k, x0 + d / k, d / k, shear, (Uint8)SDL_clamp(sc[3], 0, 255), false);
  }
  lua_pop(L, 1);
  ttf_quad(V, M, tt, k, x0, 0, shear, col.a, true);
  return true;
}
// host_text_size(text, font, size [, width]) -> w, h (pixels at that size, wrapped to width px; nil: no such font). w:text_size.
static Viewer *g_font_viewer;
static int l_text_size(lua_State *L) {            // host_text_size(text, font, size [, width]) -> w, h (wrapped to width: the lines' box)
  const char *s = luaL_checkstring(L, 1), *fname = luaL_optstring(L, 2, "sans");
  int px = (int)luaL_optnumber(L, 3, 16);
  int wrap = (int)luaL_optnumber(L, 4, 0);
  if (!g_font_viewer || px < 1) return 0;
  TTF_Font *f = font_get(g_font_viewer, fname, NULL, px, NULL);
  if (!f) return 0;
  int w = 0, h = 0;
  if (!TTF_GetStringSizeWrapped(f, s, 0, wrap > 0 ? wrap : 0, &w, &h)) return 0;
  lua_pushinteger(L, w); lua_pushinteger(L, h);
  return 2;
}
static void fonts_register(lua_State *L, Viewer *V) { g_font_viewer = V; lua_register(L, "host_text_size", l_text_size); }

static void tex_load(Viewer *V, Tex *t) {
  if (t->tex) { SDL_DestroyTexture(t->tex); t->tex = NULL; }
  for (int k = 0; k < t->nol; k++) if (t->ol[k].t) SDL_DestroyTexture(t->ol[k].t);
  t->nol = 0;
  SDL_free(t->px); t->px = NULL;
  size_t len = 0;
  void *data = SDL_LoadFile(t->file, &len);
  if (!data) return;
  int w = 0, h = 0;
  unsigned char *px = editor_image_decode(data, (int)len, &w, &h);
  SDL_free(data);
  if (!px) return;
  t->tex = SDL_CreateTexture(V->ren, SDL_PIXELFORMAT_RGBA32, SDL_TEXTUREACCESS_STATIC, w, h);
  if (t->tex) {
    SDL_UpdateTexture(t->tex, NULL, px, w * 4);
    SDL_SetTextureBlendMode(t->tex, SDL_BLENDMODE_BLEND);
    t->w = w; t->h = h;
  }
  editor_image_free(px);
}

// its pixels (RGBA): read once, kept while it's the same file (outlines, 3D textures)
static bool tex_pixels(Tex *t) {
  if (t->px) return true;
  if (!t->tex) return false;
  size_t len = 0;
  void *data = SDL_LoadFile(t->file, &len);
  if (!data) return false;
  int iw = 0, ih = 0;
  unsigned char *px = editor_image_decode(data, (int)len, &iw, &ih);
  SDL_free(data);
  if (!px) return false;
  if (iw != t->w || ih != t->h) { editor_image_free(px); return false; }
  t->px = SDL_malloc((size_t)iw * ih * 4);
  if (t->px) SDL_memcpy(t->px, px, (size_t)iw * ih * 4);
  editor_image_free(px);
  return t->px != NULL;
}
// the outline of a part of a picture (x, y, w, h): (w + 2r) x (h + 2r), white
// where its pixel isn't solid (alpha under 128) but one within r px is (8
// ways): drawn with a colour, a solid outline, r px thick (its own pixels only:
// not its neighbours' in a sheet). Cached a part and r.
static SDL_Texture *tex_outline(Viewer *V, Tex *t, int x0, int y0, int w, int h, int r) {
  if (!t->tex || w <= 0 || h <= 0 || w > 4096 || h > 4096) return NULL;
  for (int k = 0; k < t->nol; k++) {
    TexOutline *o = &t->ol[k];
    if (o->x == x0 && o->y == y0 && o->w == w && o->h == h && o->r == r) return o->t;
  }
  if (!tex_pixels(t)) return NULL;
  int W = w + 2 * r, H = h + 2 * r;
  Uint32 *out = SDL_calloc((size_t)W * H, 4);
  if (!out) return NULL;
  #define SOLID(px_, py_) ((px_) >= 0 && (py_) >= 0 && (px_) < w && (py_) < h && x0 + (px_) >= 0 && y0 + (py_) >= 0 && x0 + (px_) < t->w && y0 + (py_) < t->h \
                           && t->px[((size_t)(y0 + (py_)) * t->w + x0 + (px_)) * 4 + 3] >= 128)
  for (int j = 0; j < H; j++) for (int i = 0; i < W; i++) {
    int px = i - r, py = j - r;
    if (SOLID(px, py)) continue;
    bool on = false;
    for (int dy = -r; dy <= r && !on; dy++) for (int dx = -r; dx <= r && !on; dx++) if (SOLID(px + dx, py + dy)) on = true;
    if (on) out[(size_t)j * W + i] = 0xFFFFFFFFu;
  }
  #undef SOLID
  SDL_Texture *tx = SDL_CreateTexture(V->ren, SDL_PIXELFORMAT_RGBA32, SDL_TEXTUREACCESS_STATIC, W, H);
  if (tx) {
    SDL_UpdateTexture(tx, NULL, out, W * 4);
    SDL_SetTextureBlendMode(tx, SDL_BLENDMODE_BLEND);
    SDL_SetTextureScaleMode(tx, SDL_SCALEMODE_NEAREST);
  }
  SDL_free(out);
  if (t->nol == (int)SDL_arraysize(t->ol)) {       // (full: start over)
    for (int k = 0; k < t->nol; k++) if (t->ol[k].t) SDL_DestroyTexture(t->ol[k].t);
    t->nol = 0;
  }
  t->ol[t->nol++] = (TexOutline){ x0, y0, w, h, r, tx };
  return tx;
}

static Tex *tex_get(Viewer *V, const char *name) {
  char file[1024];
  tex_file(V, name, file, sizeof file);
  Tex *t = NULL;
  for (int i = 0; i < ntexs && !t; i++) if (!strcmp(texs[i].file, file)) t = &texs[i];
  if (!t) {
    if (ntexs == (int)(sizeof texs / sizeof texs[0])) tex_reset();   // (full: start over)
    t = &texs[ntexs++];
    SDL_zerop(t);
    SDL_strlcpy(t->file, file, sizeof t->file);
    t->smooth = true;
  }
  Uint64 now = SDL_GetTicks();
  if (!t->checked || now - t->checked > 1000) {    // its file changed (or appeared): read it again
    t->checked = now;
    SDL_PathInfo pi;
    SDL_Time m = SDL_GetPathInfo(file, &pi) ? pi.modify_time : 0;
    if (m != t->mtime || (!t->tex && m)) { t->mtime = m; tex_load(V, t); }
  }
  return t;
}

// image = { "/assets/ui.atlas.lua", frame = "ship" }: a frame of an atlas
// (plugins/atlaspacker). Its file is plain data (read in a Lua state of its own,
// no libraries; again when it changes): { image = "/assets/ui.png", frames =
// { { path = "/assets/ship.png", x, y, w, h, deg }... } }. `frame` is a
// frame's name (a cut atlas's: `name = "man1"`), its path, or its path's end
// without the extension ("ship", "rocks/big"). deg = 90: kept turned a
// quarter clockwise in the sheet (w x h: its own size).
// at = "sheet": drawn where it is in the sheet, the sheet centred on the node
// (a Game & Watch screen: every segment's node at the same place, each one
// lit where it belongs); with `src` too.
typedef struct { char path[256], name[64]; float x, y, w, h; int deg; } AtlFrame;
typedef struct { char file[1024], image[512]; AtlFrame *f; int n; SDL_Time mtime; Uint64 checked; } Atl;
static Atl atls[32];
static int natls;

static Atl *atlas_get(Viewer *V, const char *name) {
  char file[1024];
  tex_file(V, name, file, sizeof file);
  Atl *a = NULL;
  for (int i = 0; i < natls && !a; i++) if (!strcmp(atls[i].file, file)) a = &atls[i];
  if (!a) {
    if (natls == (int)(sizeof atls / sizeof atls[0])) { for (int i = 0; i < natls; i++) SDL_free(atls[i].f); natls = 0; }
    a = &atls[natls++];
    SDL_zerop(a);
    SDL_strlcpy(a->file, file, sizeof a->file);
  }
  Uint64 now = SDL_GetTicks();
  if (a->checked && now - a->checked < 1000) return a;
  a->checked = now;
  SDL_PathInfo pi;
  SDL_Time m = SDL_GetPathInfo(file, &pi) ? pi.modify_time : 0;
  if (m == a->mtime && a->f) return a;
  a->mtime = m;
  SDL_free(a->f); a->f = NULL; a->n = 0; a->image[0] = 0;
  lua_State *L = luaL_newstate();                  // (no libraries: data only)
  if (L && luaL_loadfilex(L, file, "t") == LUA_OK && lua_pcall(L, 0, 1, 0) == LUA_OK && lua_istable(L, -1)) {
    lua_getfield(L, -1, "image");
    if (lua_type(L, -1) == LUA_TSTRING) SDL_strlcpy(a->image, lua_tostring(L, -1), sizeof a->image);
    lua_pop(L, 1);
    lua_getfield(L, -1, "frames");
    int n = lua_istable(L, -1) ? (int)objlen(L, -1) : 0;
    if (n > 0) a->f = SDL_calloc(n, sizeof *a->f);
    for (int i = 1; a->f && i <= n; i++) {
      lua_rawgeti(L, -1, i);
      if (lua_istable(L, -1)) {
        int ft = lua_gettop(L);
        AtlFrame *f = &a->f[a->n++];
        lua_getfield(L, ft, "path");
        if (lua_type(L, -1) == LUA_TSTRING) SDL_strlcpy(f->path, lua_tostring(L, -1), sizeof f->path);
        lua_pop(L, 1);
        lua_getfield(L, ft, "name");
        if (lua_type(L, -1) == LUA_TSTRING) SDL_strlcpy(f->name, lua_tostring(L, -1), sizeof f->name);
        lua_pop(L, 1);
        f->x = (float)fnum(L, ft, "x", 0); f->y = (float)fnum(L, ft, "y", 0);
        f->w = (float)fnum(L, ft, "w", 0); f->h = (float)fnum(L, ft, "h", 0);
        f->deg = (int)fnum(L, ft, "deg", 0);
      }
      lua_pop(L, 1);
    }
  }
  if (L) lua_close(L);
  return a;
}

static const AtlFrame *atlas_find(const Atl *a, const char *frame) {
  size_t fl = SDL_strlen(frame);
  for (int i = 0; i < a->n; i++) if (a->f[i].name[0] && !strcmp(a->f[i].name, frame)) return &a->f[i];
  for (int i = 0; i < a->n; i++) if (!strcmp(a->f[i].path, frame)) return &a->f[i];
  for (int i = 0; i < a->n; i++) {                 // ("ship": ".../ship.png")
    const char *p = a->f[i].path, *dot = SDL_strrchr(p, '.'), *sl = SDL_strrchr(p, '/');
    size_t pl = dot && (!sl || dot > sl) ? (size_t)(dot - p) : SDL_strlen(p);
    if (pl >= fl && !strncmp(p + pl - fl, frame, fl) && (pl == fl || p[pl - fl - 1] == '/')) return &a->f[i];
  }
  return NULL;
}

static void draw_image(Viewer *V, int t, Mat M, Col col) {
  lua_State *L = V->L;
  (void)col;
  const char *name = NULL;
  if (lua_type(L, t) == LUA_TSTRING) name = lua_tostring(L, t);
  else if (lua_istable(L, t)) { lua_rawgeti(L, t, 1); name = lua_tostring(L, -1); lua_pop(L, 1); }
  if (!name) return;
  bool tab = lua_istable(L, t);
  const AtlFrame *fr = NULL;                       // a frame of an atlas
  char sheet[512];
  if (tab) {
    lua_getfield(L, t, "frame");
    const char *fname = lua_tostring(L, -1);
    size_t nl = SDL_strlen(name);
    if (fname && nl > 4 && !SDL_strcasecmp(name + nl - 4, ".lua")) {
      Atl *a = atlas_get(V, name);
      fr = a && a->image[0] ? atlas_find(a, fname) : NULL;
      if (fr) { SDL_strlcpy(sheet, a->image, sizeof sheet); name = sheet; }
    }
    lua_pop(L, 1);
  }
  Tex *tx = tex_get(V, name);
  float sx = 0, sy = 0, sw = tx->tex ? (float)tx->w : 16, sh = tx->tex ? (float)tx->h : 16;   // src: a part of the picture, px
  bool part = false;
  if (fr) { sx = fr->x; sy = fr->y; sw = fr->w; sh = fr->h; part = true; }
  if (tab && !fr) {                                       // src = { x, y, w, h } (an atlas's frame: plugins/atlaspacker)
    lua_getfield(L, t, "src");
    if (lua_istable(L, -1)) {
      int s = lua_gettop(L);
      for (int k = 0; k < 4; k++) {
        lua_rawgeti(L, s, k + 1);
        if (lua_isnumber(L, -1)) { float v = (float)lua_tonumber(L, -1); if (k == 0) sx = v; else if (k == 1) sy = v; else if (k == 2) sw = v; else sh = v; part = true; }
        lua_pop(L, 1);
      }
      sx = (float)fnum(L, s, "x", sx); sy = (float)fnum(L, s, "y", sy); sw = (float)fnum(L, s, "w", sw); sh = (float)fnum(L, s, "h", sh);
      part = true;
    }
    lua_pop(L, 1);
  }
  float w = tab ? (float)fnum(L, t, "w", sw) : sw;
  float h = tab ? (float)fnum(L, t, "h", sh) : sh;
  float ox = 0, oy = 0;                            // at = "sheet": where the part is in the whole picture, centred on the node
  bool turned0 = fr && ((fr->deg % 360 + 360) % 360) == 90;
  if (tab && part && tx->tex) {
    lua_getfield(L, t, "at");
    const char *at = lua_tostring(L, -1);
    if (at && !strcmp(at, "sheet")) {
      float ow = turned0 ? sh : sw, oh = turned0 ? sw : sh;   // (what it takes in the sheet)
      ox = sx + ow / 2 - tx->w / 2.f; oy = sy + oh / 2 - tx->h / 2.f;
    }
    lua_pop(L, 1);
  }
  if (tab) {                                       // ax, ay: the point of the picture (its part's pixels) on the node; default its middle (runtime/anim.lua's anchor)
    lua_getfield(L, t, "ax");
    if (lua_isnumber(L, -1) && sw > 0) ox += w / 2 - (float)lua_tonumber(L, -1) * (w / sw);
    lua_pop(L, 1);
    lua_getfield(L, t, "ay");
    if (lua_isnumber(L, -1) && sh > 0) oy += h / 2 - (float)lua_tonumber(L, -1) * (h / sh);
    lua_pop(L, 1);
  }
  SDL_FPoint q[4] = { xfa(M, ox - w / 2, oy - h / 2), xfa(M, ox + w / 2, oy - h / 2), xfa(M, ox + w / 2, oy + h / 2), xfa(M, ox - w / 2, oy + h / 2) };
  if (!tx->tex) {                                  // not there (or not an image): a magenta box where it would be
    for (int i = 0; i < 4; i++) pts[i] = q[i];
    pts[4] = q[0];
    draw_poly(V, 5, false, (Col){ 255, 0, 255, 255 });
    return;
  }
  Col tint = { 255, 255, 255, 255 };
  if (tab) {
    lua_getfield(L, t, "color");
    tint = read_color(L, lua_gettop(L), tint);
    lua_pop(L, 1);
  }
  bool smooth = true;
  if (tab) { lua_getfield(L, t, "smooth"); smooth = lua_isnil(L, -1) || lua_toboolean(L, -1); lua_pop(L, 1); }
  if (smooth != tx->smooth) {
    SDL_SetTextureScaleMode(tx->tex, smooth ? SDL_SCALEMODE_LINEAR : SDL_SCALEMODE_NEAREST);
    tx->smooth = smooth;
  }
  SDL_FColor fc = fcol(tint);
  float u0 = 0, v0 = 0, u1 = 1, v1 = 1;
  bool turned = fr && ((fr->deg % 360 + 360) % 360) == 90;   // (kept turned: it takes sh x sw there)
  if (part && tx->w > 0 && tx->h > 0) { u0 = sx / tx->w; v0 = sy / tx->h; u1 = (sx + (turned ? sh : sw)) / tx->w; v1 = (sy + (turned ? sw : sh)) / tx->h; }
  float uv[4][2] = { { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } };
  if (turned) {                                    // its top left is the sheet's top right, and so on round
    float r[4][2] = { { u1, v0 }, { u1, v1 }, { u0, v1 }, { u0, v0 } };
    SDL_memcpy(uv, r, sizeof uv);
  }
  SDL_Vertex v[4];
  for (int i = 0; i < 4; i++) {
    v[i].position = q[i]; v[i].color = fc;
    v[i].tex_coord.x = uv[i][0]; v[i].tex_coord.y = uv[i][1];
    acc_add(q[i].x, q[i].y);
  }
  static const int idx[6] = { 0, 1, 2, 0, 2, 3 };
  if (tab && !turned) {                            // outline2 (2 px round it), then outline1 over its inner px: baked, solid (tex_outline)
    for (int k = 0; k < 2; k++) {
      lua_getfield(L, t, k == 0 ? "outline2" : "outline1");
      bool has = lua_istable(L, -1);
      Col oc = has ? read_color(L, lua_gettop(L), (Col){ 0, 0, 0, 255 }) : (Col){ 0 };
      lua_pop(L, 1);
      if (!has) continue;
      int r = k == 0 ? 2 : 1;
      int px0 = (int)SDL_floorf(sx), py0 = (int)SDL_floorf(sy), pw0 = (int)SDL_ceilf(sw), ph0 = (int)SDL_ceilf(sh);
      SDL_Texture *ot = tex_outline(V, tx, px0, py0, pw0, ph0, r);
      if (!ot) continue;
      float pw = sw > 0 ? w / sw : 1, ph = sh > 0 ? h / sh : 1;   // (one of its pixels, in world units)
      float ex = r * pw, ey = r * ph;
      SDL_FPoint qq[4] = { xfa(M, ox - w / 2 - ex, oy - h / 2 - ey), xfa(M, ox + w / 2 + ex, oy - h / 2 - ey),
                           xfa(M, ox + w / 2 + ex, oy + h / 2 + ey), xfa(M, ox - w / 2 - ex, oy + h / 2 + ey) };
      SDL_FColor c = fcol(oc);
      c.a *= fc.a;                                 // (a faded picture: its outline too)
      static const float ouv[4][2] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } };
      SDL_Vertex ov[4];
      for (int i = 0; i < 4; i++) { ov[i].position = qq[i]; ov[i].color = c; ov[i].tex_coord.x = ouv[i][0]; ov[i].tex_coord.y = ouv[i][1]; }
      SDL_RenderGeometry(V->ren, ot, ov, 4, idx, 6);
    }
  }
  SDL_RenderGeometry(V->ren, tx->tex, v, 4, idx, 6);
  acc_solid = true;
}

// bullets = { "/assets/spark.png", size = 10, xy = { x1, y1, x2, y2, ... },
//   s = { size1, ... }, rgb = { 0xRRGGBB, ... }, a = { angle1, ... }, o = { 0..1, ... }, color = {...} }:
// many small pictures in one batch (a bullet-hell's bullets: runtime/bullets.lua).
// No picture: soft round dots. s / rgb / a are optional, one a bullet (size,
// tint, turn in radians, opacity); color tints them all. Not pickable one by one.
static SDL_Texture *dot_texture(Viewer *V) {       // a white disc with a soft edge, 32 x 32
  if (g_dot_tex) return g_dot_tex;
  Uint32 px[32 * 32];
  for (int y = 0; y < 32; y++) for (int x = 0; x < 32; x++) {
    float dx = x + 0.5f - 16, dy = y + 0.5f - 16, d = SDL_sqrtf(dx * dx + dy * dy);
    float a = d < 13 ? 1.f : d < 16 ? (16 - d) / 3.f : 0.f;
    px[y * 32 + x] = ((Uint32)(a * 255) << 24) | 0xFFFFFF;
  }
  g_dot_tex = SDL_CreateTexture(V->ren, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STATIC, 32, 32);
  if (g_dot_tex) { SDL_UpdateTexture(g_dot_tex, NULL, px, 32 * 4); SDL_SetTextureBlendMode(g_dot_tex, SDL_BLENDMODE_BLEND); }
  return g_dot_tex;
}
static void draw_bullets(Viewer *V, int t, Mat M, Col col) {
  lua_State *L = V->L;
  if (!lua_istable(L, t)) return;
  lua_rawgeti(L, t, 1);
  const char *name = lua_tostring(L, -1);
  lua_pop(L, 1);
  SDL_Texture *tex = NULL;
  if (name) { Tex *tx = tex_get(V, name); tex = tx->tex; }
  if (!tex) tex = dot_texture(V);
  if (!tex) return;
  float size = (float)fnum(L, t, "size", 8);
  float k = SDL_sqrtf(SDL_fabsf(M.a * M.d - M.b * M.c));   // (the node's and the camera's scale)
  lua_getfield(L, t, "color");
  Col tint = read_color(L, lua_gettop(L), col);
  lua_pop(L, 1);
  lua_getfield(L, t, "xy"); int xy = lua_gettop(L);
  lua_getfield(L, t, "s"); int ss = lua_istable(L, -1) ? lua_gettop(L) : 0;
  lua_getfield(L, t, "rgb"); int rgb = lua_istable(L, -1) ? lua_gettop(L) : 0;
  lua_getfield(L, t, "a"); int an = lua_istable(L, -1) ? lua_gettop(L) : 0;
  lua_getfield(L, t, "o"); int op = lua_istable(L, -1) ? lua_gettop(L) : 0;
  int n = lua_istable(L, xy) ? (int)objlen(L, xy) / 2 : 0;
  enum { CHUNK = 512 };                             // (drawn in batches of 512)
  static SDL_Vertex v[CHUNK * 4];
  static int idx[CHUNK * 6];
  static bool idx_made;
  if (!idx_made) {
    for (int i = 0; i < CHUNK; i++) {
      int b = i * 4;
      idx[i * 6] = b; idx[i * 6 + 1] = b + 1; idx[i * 6 + 2] = b + 2;
      idx[i * 6 + 3] = b; idx[i * 6 + 4] = b + 2; idx[i * 6 + 5] = b + 3;
    }
    idx_made = true;
  }
  int m = 0;
  float x0 = 1e30f, y0 = 1e30f, x1 = -1e30f, y1 = -1e30f;
  for (int i = 0; i < n; i++) {
    lua_rawgeti(L, xy, i * 2 + 1); lua_rawgeti(L, xy, i * 2 + 2);
    float x = (float)lua_tonumber(L, -2), y = (float)lua_tonumber(L, -1);
    lua_pop(L, 2);
    float sz = size, ang = 0;
    Col c = tint;
    if (ss) { lua_rawgeti(L, ss, i + 1); if (lua_isnumber(L, -1)) sz = (float)lua_tonumber(L, -1); lua_pop(L, 1); }
    if (an) { lua_rawgeti(L, an, i + 1); if (lua_isnumber(L, -1)) ang = (float)lua_tonumber(L, -1); lua_pop(L, 1); }
    if (op) {
      lua_rawgeti(L, op, i + 1);
      if (lua_isnumber(L, -1)) { float o = (float)lua_tonumber(L, -1); c.a = (Uint8)(c.a * (o < 0 ? 0 : o > 1 ? 1 : o)); }
      lua_pop(L, 1);
    }
    if (rgb) {
      lua_rawgeti(L, rgb, i + 1);
      if (lua_isnumber(L, -1)) {
        Uint32 h = (Uint32)lua_tonumber(L, -1);
        c.r = (Uint8)((((h >> 16) & 255) * tint.r) / 255); c.g = (Uint8)((((h >> 8) & 255) * tint.g) / 255); c.b = (Uint8)(((h & 255) * tint.b) / 255);
      }
      lua_pop(L, 1);
    }
    SDL_FPoint p = xf(M, x, y);
    float hs = sz * k / 2, ca = SDL_cosf(ang) * hs, sa = SDL_sinf(ang) * hs;
    SDL_FColor fc = fcol(c);
    SDL_FPoint q[4] = { { p.x - ca + sa, p.y - sa - ca }, { p.x + ca + sa, p.y + sa - ca },
                        { p.x + ca - sa, p.y + sa + ca }, { p.x - ca - sa, p.y - sa + ca } };
    static const float UV[4][2] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } };
    for (int j = 0; j < 4; j++) {
      SDL_Vertex *vv = &v[m * 4 + j];
      vv->position = q[j]; vv->color = fc; vv->tex_coord.x = UV[j][0]; vv->tex_coord.y = UV[j][1];
    }
    if (p.x < x0) x0 = p.x;
    if (p.y < y0) y0 = p.y;
    if (p.x > x1) x1 = p.x;
    if (p.y > y1) y1 = p.y;
    if (++m == CHUNK) { SDL_RenderGeometry(V->ren, tex, v, m * 4, idx, m * 6); m = 0; }
  }
  if (m) SDL_RenderGeometry(V->ren, tex, v, m * 4, idx, m * 6);
  lua_settop(L, xy - 1);
  (void)x0; (void)y0; (void)x1; (void)y1;          // (not pickable: a bullet isn't something to select)
}

// tilemap = { "/assets/level.tmap", layer = "ground", size = 16, color = {...} }:
// a layer of a tile map (plugins/tilemap: its .tmap file, plain data read in a
// Lua state of its own, again when it changes: edit the map, the game shows
// it). layer: its name or its index (default: the first). Drawn from the
// node's origin, a cell `size` world units (default: the tile's px), its
// tileset beside the .tmap ("tiles.png" -> assets/<the map's folder>/tiles.png),
// or the tilemap plugin's ("plugin:tiles.png": plugins/tilemap/tiles.png, exported with the game).
// layer = "*": every layer, in z order. A decals layer (kind = "decals"):
// its pictures placed freely (a tile of the tileset, or an image beside the
// map; x, y their middle, turned deg, scale, flip).
typedef struct { int tile; char image[256]; float x, y, deg, scale; bool flip; } TmDecal;
typedef struct { char name[64]; Uint16 *cells; float z; TmDecal *d; int nd; } TmLayer;
typedef struct { char file[1024], tileset[512]; int tile, w, h, n; TmLayer *l; SDL_Time mtime; Uint64 checked; } Tmap;
static Tmap tmaps[16];
static int ntmaps;

static void tmap_free(Tmap *m) {
  for (int i = 0; i < m->n; i++) { SDL_free(m->l[i].cells); SDL_free(m->l[i].d); }
  SDL_free(m->l); m->l = NULL; m->n = 0;
}
static Tmap *tmap_get(Viewer *V, const char *name) {
  char file[1024];
  tex_file(V, name, file, sizeof file);
  Tmap *m = NULL;
  for (int i = 0; i < ntmaps && !m; i++) if (!strcmp(tmaps[i].file, file)) m = &tmaps[i];
  if (!m) {
    if (ntmaps == (int)(sizeof tmaps / sizeof tmaps[0])) { for (int i = 0; i < ntmaps; i++) tmap_free(&tmaps[i]); ntmaps = 0; }
    m = &tmaps[ntmaps++];
    SDL_zerop(m);
    SDL_strlcpy(m->file, file, sizeof m->file);
  }
  Uint64 now = SDL_GetTicks();
  if (m->checked && now - m->checked < 1000) return m;
  m->checked = now;
  SDL_PathInfo pi;
  SDL_Time mt = SDL_GetPathInfo(file, &pi) ? pi.modify_time : 0;
  if (mt == m->mtime && m->l) return m;
  m->mtime = mt;
  tmap_free(m);
  m->tileset[0] = 0;
  lua_State *L = luaL_newstate();                  // (no libraries: data only)
  if (L && luaL_loadfilex(L, file, "t") == LUA_OK && lua_pcall(L, 0, 1, 0) == LUA_OK && lua_istable(L, -1)) {
    int t = lua_gettop(L);
    m->tile = (int)fnum(L, t, "tile", 16); m->w = (int)fnum(L, t, "w", 0); m->h = (int)fnum(L, t, "h", 0);
    int dg = (int)fnum(L, t, "digits", 2) == 4 ? 4 : 2;   // (hex digits a cell: 4 for a tileset of more than 256 tiles)
    if (m->tile < 1) m->tile = 16;
    lua_getfield(L, t, "tileset");
    const char *ts = lua_tostring(L, -1);
    if (ts && !strncmp(ts, "plugin:", 7)) SDL_strlcpy(m->tileset, ts, sizeof m->tileset);   // (the tilemap plugin's own: tex_file finds it)
    else if (ts) {                                 // beside the map: its folder under assets/
      char dir[512];
      SDL_strlcpy(dir, name, sizeof dir);
      char *sl = SDL_strrchr(dir, '/');
      if (sl) sl[1] = 0; else dir[0] = 0;
      SDL_snprintf(m->tileset, sizeof m->tileset, "%s%s", dir, ts);
    }
    lua_pop(L, 1);
    lua_getfield(L, t, "layers");
    int nl = lua_istable(L, -1) ? (int)objlen(L, -1) : 0;
    if (nl > 0 && m->w > 0 && m->h > 0 && m->w <= 4096 && m->h <= 4096) m->l = SDL_calloc(nl, sizeof *m->l);
    for (int i = 1; m->l && i <= nl; i++) {
      lua_rawgeti(L, -1, i);
      if (lua_istable(L, -1)) {
        int lt = lua_gettop(L);
        TmLayer *ly = &m->l[m->n++];
        lua_getfield(L, lt, "name");
        if (lua_type(L, -1) == LUA_TSTRING) SDL_strlcpy(ly->name, lua_tostring(L, -1), sizeof ly->name);
        lua_pop(L, 1);
        ly->z = (float)fnum(L, lt, "z", i);
        lua_getfield(L, lt, "decals");             // (a decals layer: its pictures)
        int nd = lua_istable(L, -1) ? (int)objlen(L, -1) : 0;
        if (nd > 0 && nd <= 65536) ly->d = SDL_calloc(nd, sizeof *ly->d);
        for (int k = 1; ly->d && k <= nd; k++) {
          lua_rawgeti(L, -1, k);
          if (lua_istable(L, -1)) {
            int dt = lua_gettop(L);
            TmDecal *dc = &ly->d[ly->nd++];
            dc->tile = (int)fnum(L, dt, "tile", 0);
            dc->x = (float)fnum(L, dt, "x", 0); dc->y = (float)fnum(L, dt, "y", 0);
            dc->deg = (float)fnum(L, dt, "deg", 0); dc->scale = (float)fnum(L, dt, "scale", 1);
            lua_getfield(L, dt, "flip"); dc->flip = lua_toboolean(L, -1); lua_pop(L, 1);
            lua_getfield(L, dt, "image");
            if (lua_type(L, -1) == LUA_TSTRING) {    // (beside the map, as its tileset)
              char dir[256];
              SDL_strlcpy(dir, name, sizeof dir);
              char *sl = SDL_strrchr(dir, '/');
              if (sl) sl[1] = 0; else dir[0] = 0;
              SDL_snprintf(dc->image, sizeof dc->image, "%s%s", dir, lua_tostring(L, -1));
            }
            lua_pop(L, 1);
          }
          lua_pop(L, 1);
        }
        lua_pop(L, 1);
        ly->cells = SDL_malloc(sizeof(Uint16) * m->w * m->h);
        for (int k = 0; k < m->w * m->h; k++) ly->cells[k] = 0xFFFF;
        lua_getfield(L, lt, "rows");
        for (int y = 0; lua_istable(L, -1) && y < m->h; y++) {
          lua_rawgeti(L, -1, y + 1);
          size_t len = 0;
          const char *row = lua_type(L, -1) == LUA_TSTRING ? lua_tolstring(L, -1, &len) : "";
          for (int x = 0; x < m->w && (size_t)(x * dg + dg - 1) < len; x++) {
            char hx[5] = { 0 };
            bool ok = true;
            for (int k = 0; k < dg; k++) { hx[k] = row[x * dg + k]; if (!SDL_isxdigit(hx[k])) ok = false; }
            if (ok) { long v = SDL_strtol(hx, NULL, 16); if (v >= 0 && v < 0xFFFF) ly->cells[y * m->w + x] = (Uint16)v; }
          }
          lua_pop(L, 1);
        }
        lua_pop(L, 1);
      }
      lua_pop(L, 1);
    }
  }
  if (L) lua_close(L);
  return m;
}

// the cells of a tile map (w x h, 0xFFFF: none) drawn from a tileset
static void draw_cells(Viewer *V, Mat M, const Uint16 *cells, int w, int h, int tile, float cs, Col tint, const char *tileset) {
  Tex *tx = tileset && tileset[0] ? tex_get(V, tileset) : NULL;
  if (!tx || !tx->tex) {                           // (no tileset: its outline in magenta)
    SDL_FPoint q[4] = { xfa(M, 0, 0), xfa(M, w * cs, 0), xfa(M, w * cs, h * cs), xfa(M, 0, h * cs) };
    for (int i = 0; i < 4; i++) pts[i] = q[i];
    pts[4] = q[0];
    draw_poly(V, 5, false, (Col){ 255, 0, 255, 255 });
    return;
  }
  if (tx->smooth) { SDL_SetTextureScaleMode(tx->tex, SDL_SCALEMODE_NEAREST); tx->smooth = false; }   // (pixel art: crisp)
  int cols = tx->w / tile;
  if (cols < 1) return;
  static SDL_Vertex *vb; static int *ib; static int cap;
  int nq = 0;
  for (int k = 0; k < w * h; k++) if (cells[k] != 0xFFFF) nq++;
  if (nq == 0) return;
  if (nq > cap) { cap = nq + 256; vb = SDL_realloc(vb, sizeof *vb * cap * 4); ib = SDL_realloc(ib, sizeof *ib * cap * 6); }
  SDL_FColor fc = fcol(tint);
  float iw = 1.f / tx->w, ih = 1.f / tx->h;
  int q = 0;
  for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
    Uint16 c = cells[y * w + x];
    if (c == 0xFFFF) continue;
    float u0 = (c % cols) * tile * iw, v0 = (c / cols) * tile * ih, u1 = u0 + tile * iw, v1 = v0 + tile * ih;
    SDL_FPoint p[4] = { xfa(M, x * cs, y * cs), xfa(M, (x + 1) * cs, y * cs), xfa(M, (x + 1) * cs, (y + 1) * cs), xfa(M, x * cs, (y + 1) * cs) };
    float uv[4][2] = { { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } };
    for (int i = 0; i < 4; i++) { vb[q * 4 + i].position = p[i]; vb[q * 4 + i].color = fc; vb[q * 4 + i].tex_coord.x = uv[i][0]; vb[q * 4 + i].tex_coord.y = uv[i][1]; }
    static const int I[6] = { 0, 1, 2, 0, 2, 3 };
    for (int i = 0; i < 6; i++) ib[q * 6 + i] = q * 4 + I[i];
    q++;
  }
  SDL_RenderGeometry(V->ren, tx->tex, vb, q * 4, ib, q * 6);
  acc_add(xfa(M, 0, 0).x, xfa(M, 0, 0).y);         // (picking: the map's whole rectangle)
  acc_add(xfa(M, w * cs, h * cs).x, xfa(M, w * cs, h * cs).y);
  acc_solid = true;
}

// tilemap = { rows = { "0001..", ... }, tileset = "plugin:tiles.png", tile = 16, size = 16 }:
// a layer given in place (a game that makes its maps as it plays: the
// dungeon / terrain generators' data), its rows as a .tmap writes them
static void draw_tilemap_rows(Viewer *V, int t, Mat M) {
  lua_State *L = V->L;
  lua_getfield(L, t, "rows");
  int r = lua_gettop(L);
  int h = (int)objlen(L, r), w = 0;
  int dg = (int)fnum(L, t, "digits", 2) == 4 ? 4 : 2;
  if (h > 0) { size_t n0 = 0; lua_rawgeti(L, r, 1); lua_tolstring(L, -1, &n0); w = (int)(n0 / dg); lua_pop(L, 1); }
  if (w <= 0 || h <= 0 || w > 1024 || h > 1024) { lua_settop(L, r - 1); return; }
  static Uint16 *cells; static int ccap;
  if (w * h > ccap) { ccap = w * h; cells = SDL_realloc(cells, sizeof *cells * ccap); }
  for (int y = 0; y < h; y++) {
    lua_rawgeti(L, r, y + 1);
    size_t n = 0;
    const char *row = lua_tolstring(L, -1, &n);
    for (int x = 0; x < w; x++) {
      Uint16 v = 0xFFFF;
      if (row && (size_t)(x * dg + dg - 1) < n && row[x * dg] != '.') {
        char hx[5] = { 0 };
        for (int k = 0; k < dg; k++) hx[k] = row[x * dg + k];
        long lv = SDL_strtol(hx, NULL, 16);
        if (lv >= 0 && lv < 0xFFFF) v = (Uint16)lv;
      }
      cells[y * w + x] = v;
    }
    lua_pop(L, 1);
  }
  lua_settop(L, r - 1);
  int tile = (int)fnum(L, t, "tile", 16);
  if (tile < 1) tile = 16;
  float cs = (float)fnum(L, t, "size", tile);
  Col tint = { 255, 255, 255, 255 };
  lua_getfield(L, t, "color"); tint = read_color(L, lua_gettop(L), tint); lua_pop(L, 1);
  lua_getfield(L, t, "tileset");
  char ts[512];
  SDL_strlcpy(ts, lua_isstring(L, -1) ? lua_tostring(L, -1) : "plugin:tiles.png", sizeof ts);
  lua_pop(L, 1);
  draw_cells(V, M, cells, w, h, tile, cs, tint, ts);
}

// a decals layer: each picture turned about its middle (x, y: map px, a cell `tile` px; cs: a cell's world units)
static void draw_decals(Viewer *V, Mat M, const TmLayer *ly, int tile, float cs, Col tint, const char *tileset) {
  float k = cs / tile;                             // (map px -> world units)
  Tex *ts = tileset && tileset[0] ? tex_get(V, tileset) : NULL;
  SDL_FColor fc = fcol(tint);
  static const int I[6] = { 0, 1, 2, 0, 2, 3 };
  for (int i = 0; i < ly->nd; i++) {
    const TmDecal *d = &ly->d[i];
    Tex *tx = d->image[0] ? tex_get(V, d->image) : ts;
    if (!tx || !tx->tex) continue;
    if (tx->smooth) { SDL_SetTextureScaleMode(tx->tex, SDL_SCALEMODE_NEAREST); tx->smooth = false; }
    float u0 = 0, v0 = 0, u1 = 1, v1 = 1, w = (float)tx->w, h = (float)tx->h;
    if (!d->image[0]) {                            // a tile of the tileset
      int cols = tx->w / tile;
      if (cols < 1) continue;
      u0 = (float)(d->tile % cols) * tile / tx->w; v0 = (float)(d->tile / cols) * tile / tx->h;
      u1 = u0 + (float)tile / tx->w; v1 = v0 + (float)tile / tx->h;
      w = h = (float)tile;
    }
    if (d->flip) { float u = u0; u0 = u1; u1 = u; }
    float hw = w * d->scale / 2 * k, hh = h * d->scale / 2 * k;
    float a = d->deg * (float)SDL_PI_D / 180.f, c = SDL_cosf(a), sn = SDL_sinf(a);
    float lx[4] = { -hw, hw, hw, -hw }, lyy[4] = { -hh, -hh, hh, hh };
    float uv[4][2] = { { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } };
    SDL_Vertex v[4];
    for (int j = 0; j < 4; j++) {
      float px = d->x * k + lx[j] * c - lyy[j] * sn, py = d->y * k + lx[j] * sn + lyy[j] * c;
      v[j].position = xfa(M, px, py); v[j].color = fc;
      v[j].tex_coord.x = uv[j][0]; v[j].tex_coord.y = uv[j][1];
      acc_add(v[j].position.x, v[j].position.y);
    }
    SDL_RenderGeometry(V->ren, tx->tex, v, 4, I, 6);
    acc_solid = true;
  }
}
static void draw_layer(Viewer *V, Mat M, Tmap *m, int li, float cs, Col tint) {
  if (m->l[li].nd > 0) draw_decals(V, M, &m->l[li], m->tile, cs, tint, m->tileset);
  else draw_cells(V, M, m->l[li].cells, m->w, m->h, m->tile, cs, tint, m->tileset);
}

static void draw_tilemap(Viewer *V, int t, Mat M, Col col) {
  lua_State *L = V->L;
  (void)col;
  if (lua_istable(L, t)) {                         // (rows in place: no file)
    lua_getfield(L, t, "rows");
    bool inl = lua_istable(L, -1);
    lua_pop(L, 1);
    if (inl) { draw_tilemap_rows(V, t, M); return; }
  }
  const char *name = NULL;
  if (lua_type(L, t) == LUA_TSTRING) name = lua_tostring(L, t);
  else if (lua_istable(L, t)) { lua_rawgeti(L, t, 1); name = lua_tostring(L, -1); lua_pop(L, 1); }
  if (!name) return;
  Tmap *m = tmap_get(V, name);
  if (!m->l || m->n == 0) return;
  int li = 0;                                      // which layer: its name, or its index ("*": all, by z)
  bool all = false;
  if (lua_istable(L, t)) {
    lua_getfield(L, t, "layer");
    if (lua_type(L, -1) == LUA_TNUMBER) li = (int)lua_tointeger(L, -1) - 1;
    else if (lua_type(L, -1) == LUA_TSTRING && !strcmp(lua_tostring(L, -1), "*")) all = true;
    else if (lua_type(L, -1) == LUA_TSTRING) { li = -1; for (int i = 0; i < m->n; i++) if (!strcmp(m->l[i].name, lua_tostring(L, -1))) li = i; }
    lua_pop(L, 1);
  }
  if (!all && (li < 0 || li >= m->n)) return;
  float cs = lua_istable(L, t) ? (float)fnum(L, t, "size", m->tile) : (float)m->tile;
  Col tint = { 255, 255, 255, 255 };
  if (lua_istable(L, t)) { lua_getfield(L, t, "color"); tint = read_color(L, lua_gettop(L), tint); lua_pop(L, 1); }
  if (!all) { draw_layer(V, M, m, li, cs, tint); return; }
  int ord[64], n = m->n < 64 ? m->n : 64;          // (by z, then place: insertion sort, stable)
  for (int i = 0; i < n; i++) {
    int j = i;
    while (j > 0 && m->l[ord[j - 1]].z > m->l[i].z) { ord[j] = ord[j - 1]; j--; }
    ord[j] = i;
  }
  for (int i = 0; i < n; i++) draw_layer(V, M, m, ord[i], cs, tint);
}

// camera3d = { w = 320, h = 180, eye = { 0, 2, 6 }, at = { 0, 0, 0 }, up = { 0, 1, 0 }, fov = 60,
//   near = 0.1, far = 100, clear = { r, g, b [, a] }, ambient = { r, g, b }, sun = { dir = { x, y, z },
//   color = { r, g, b } }, res = 1 }: a 3D viewport (docs/3D.md). The 3D nodes under it are drawn
// into a picture w x h (times res: its pixels a world unit), centred on the node, a part of the 2D
// world. A 3D node: transform3d = { x, y, z, rx, ry, rz, s | sx, sy, sz } (meters, radians; children
// follow), mesh = { "cube" | "plane" | "sphere" | "/assets/ship.glb", color = { r, g, b, a },
// texture = "/assets/crate.png" (in place of its own), hidden }. Drawn by the CPU (raster3d.h)
// until the GPU path comes (docs/3D.md, phase 3).
#include "mesh3d.h"
#include "raster3d.h"
#include "render3d.h"
typedef struct Cam3D_ {
  char path[256]; R3Target t; SDL_Texture *tex; int tw, th; Uint64 used; G3View g; bool gpu;   // gpu: drawn by render3d.h
  struct Pick3D_ *p3; int np3, cap3; float pvp[16], pw2, ph2; Mat pM;   // what a ray can hit (pick3d), as last drawn: the picture's size, place
  SDL_FRect rect;                                  // where its picture was drawn (picking's coordinates: the fly camera's)
  float geye[3], gat[3];                           // the game's camera, as last drawn
  bool fly; float feye[3], yaw, pitch; Uint64 fly_t;   // the editor's fly camera over it (not the game's: RMB held + WASD)
  R3Target mask; SDL_Texture *otex; unsigned char *orgba; int ow, oh;   // the selected 3D nodes' outline (yellow, 2 px)
} Cam3D;
// the editor's fly camera (replay.c: RMB held on a camera3d's picture): mouse looks, W A S D Q E move
// (Shift: faster, the wheel: its speed), R gives the game's camera back. Never the game's state.
static struct { bool held; int cam; unsigned keys; float speed; } fly3d = { false, -1, 0, 3 };
static Viewer *g_mesh3d_viewer;                    // (host_mesh3d: the viewer the models are read for)
static Cam3D cams3d[8];
// the outline of the items marked (G3Item.outline): their silhouette (the CPU's, any path) grown 2 px, yellow,
// over the picture: cam->otex (pw x ph, clear elsewhere). -> false: none marked
static bool outline3d_build(Cam3D *cam, SDL_Renderer *ren, const G3View *G, const float vp[16], int pw, int ph) {
  bool any = false;
  for (int i = 0; i < G->n; i++) if (G->items[i].outline) any = true;
  if (!any) return false;
  static const unsigned char clear[4] = { 0, 0, 0, 0 };
  if (!r3_begin(&cam->mask, pw, ph, clear)) return false;
  R3Light L0;
  SDL_zero(L0);
  L0.ambient[0] = L0.ambient[1] = L0.ambient[2] = 1;
  static const float white[4] = { 1, 1, 1, 1 };
  for (int i = 0; i < G->n; i++) {
    const G3Item *it = &G->items[i];
    if (!it->outline) continue;
    pose3d_cpu((Mesh3D *)it->m);                   // (skinned on the GPU: posed here too, for its silhouette)
    r3_draw(&cam->mask, it->m, it->model, vp, white, &L0, it->has_cpu_tex ? &it->cpu_tex : NULL);
  }
  if (cam->ow != pw || cam->oh != ph || !cam->orgba) {
    SDL_free(cam->orgba);
    cam->orgba = SDL_malloc((size_t)pw * ph * 4);
    if (cam->otex) SDL_DestroyTexture(cam->otex);
    cam->otex = NULL;
    cam->ow = pw; cam->oh = ph;
    if (!cam->orgba) { cam->ow = cam->oh = 0; return false; }
  }
  SDL_memset(cam->orgba, 0, (size_t)pw * ph * 4);
  const unsigned char *m = cam->mask.rgba;
  int x0 = pw, y0 = ph, x1 = -1, y1 = -1;          // (the silhouette's box: only round it)
  for (int y = 0; y < ph; y++) for (int x = 0; x < pw; x++) if (m[((size_t)y * pw + x) * 4 + 3]) {
    if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
  }
  if (x1 < 0) return false;
  const int R = 2;
  for (int y = SDL_max(0, y0 - R); y <= SDL_min(ph - 1, y1 + R); y++)
    for (int x = SDL_max(0, x0 - R); x <= SDL_min(pw - 1, x1 + R); x++) {
      if (m[((size_t)y * pw + x) * 4 + 3]) continue;
      bool close_by = false;  // (not "near": a macro in windows.h)
      for (int dy = -R; dy <= R && !close_by; dy++) for (int dx = -R; dx <= R && !close_by; dx++) {
        int xx = x + dx, yy = y + dy;
        if (dx * dx + dy * dy > R * R + 1 || xx < 0 || yy < 0 || xx >= pw || yy >= ph) continue;
        if (m[((size_t)yy * pw + xx) * 4 + 3]) close_by = true;
      }
      if (close_by) { unsigned char *o = &cam->orgba[((size_t)y * pw + x) * 4]; o[0] = 255; o[1] = 255; o[2] = 0; o[3] = 255; }
    }
  if (!cam->otex) {
    cam->otex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_RGBA32, SDL_TEXTUREACCESS_STREAMING, pw, ph);
    if (!cam->otex) return false;
    SDL_SetTextureBlendMode(cam->otex, SDL_BLENDMODE_BLEND);
    SDL_SetTextureScaleMode(cam->otex, SDL_SCALEMODE_NEAREST);
  }
  SDL_UpdateTexture(cam->otex, NULL, cam->orgba, pw * 4);
  return true;
}
static void outline3d_free(Cam3D *c) { if (c->otex) SDL_DestroyTexture(c->otex); SDL_free(c->orgba); SDL_free(c->mask.rgba); SDL_free(c->mask.depth); c->otex = NULL; c->orgba = NULL; c->mask.rgba = NULL; c->mask.depth = NULL; c->mask.w = c->mask.h = 0; c->ow = c->oh = 0; }
// the fly camera (replay.c calls these while RMB is held over a camera3d's picture)
static bool fly3d_begin(float x, float y) {        // x, y: picking's coordinates -> over a camera's picture?
  for (int i = 0; i < (int)SDL_arraysize(cams3d); i++) {
    const SDL_FRect *r = &cams3d[i].rect;
    if (cams3d[i].path[0] && x >= r->x && y >= r->y && x < r->x + r->w && y < r->y + r->h) {
      fly3d.held = true; fly3d.cam = i; fly3d.keys = 0;
      cams3d[i].fly_t = SDL_GetTicksNS();
      return true;
    }
  }
  return false;
}
static void fly3d_take(Cam3D *c) {                 // (first look or move: from the game's camera)
  if (c->fly) return;
  float d[3] = { c->gat[0] - c->geye[0], c->gat[1] - c->geye[1], c->gat[2] - c->geye[2] };
  v3_norm(d);
  SDL_memcpy(c->feye, c->geye, sizeof c->feye);
  c->yaw = atan2f(d[0], -d[2]); c->pitch = asinf(SDL_clamp(d[1], -1, 1));
  c->fly = true;
}
static void fly3d_look(float dx, float dy) {
  if (!fly3d.held || fly3d.cam < 0) return;
  Cam3D *c = &cams3d[fly3d.cam];
  fly3d_take(c);
  c->yaw += dx * 0.005f;
  c->pitch = SDL_clamp(c->pitch - dy * 0.005f, -1.55f, 1.55f);
}
static bool fly3d_key(SDL_Keycode k, bool down) {   // -> taken
  static const SDL_Keycode keys[] = { SDLK_W, SDLK_S, SDLK_A, SDLK_D, SDLK_E, SDLK_Q, SDLK_LSHIFT, SDLK_RSHIFT };
  if (k == SDLK_R) { if (down && fly3d.cam >= 0) cams3d[fly3d.cam].fly = false; return true; }   // (R: the game's camera again)
  for (int i = 0; i < (int)SDL_arraysize(keys); i++) if (keys[i] == k) {
    unsigned bit = 1u << (i < 6 ? i : 6);
    if (down) fly3d.keys |= bit; else fly3d.keys &= ~bit;
    return true;
  }
  return false;
}
static void fly3d_end(void) { fly3d.held = false; fly3d.keys = 0; }
static void fly3d_apply(Cam3D *c, int idx, float eye[3], float at[3], float up[3]) {   // (draw_camera3d: its eye, at, up while flown)
  Uint64 now = SDL_GetTicksNS();
  float dt = SDL_min((now - c->fly_t) / 1e9f, 0.1f);
  c->fly_t = now;
  if (fly3d.held && fly3d.cam == idx && (fly3d.keys & 63)) {
    fly3d_take(c);
    float cp = cosf(c->pitch), f[3] = { cp * sinf(c->yaw), sinf(c->pitch), -cp * cosf(c->yaw) }, r[3] = { cosf(c->yaw), 0, sinf(c->yaw) };
    float v = fly3d.speed * ((fly3d.keys & 64) ? 4.f : 1.f) * dt;
    unsigned k = fly3d.keys;
    for (int a = 0; a < 3; a++) c->feye[a] += v * (f[a] * (((k & 1) ? 1 : 0) - ((k & 2) ? 1 : 0)) + r[a] * (((k & 8) ? 1 : 0) - ((k & 4) ? 1 : 0)));
    c->feye[1] += v * (((k & 16) ? 1 : 0) - ((k & 32) ? 1 : 0));
  }
  if (!c->fly) return;
  float cp = cosf(c->pitch);
  SDL_memcpy(eye, c->feye, 12);
  at[0] = eye[0] + cp * sinf(c->yaw); at[1] = eye[1] + sinf(c->pitch); at[2] = eye[2] - cp * cosf(c->yaw);
  up[0] = 0; up[1] = 1; up[2] = 0;
}
static void lite3d_release(void);
static void cams3d_release(void) { for (int i = 0; i < (int)SDL_arraysize(cams3d); i++) if (cams3d[i].g.col || cams3d[i].g.items) g3_view_free(&cams3d[i].g); lite3d_release(); }
static void v3_read(lua_State *L, int t, const char *k, float out[3], float d0, float d1, float d2) {
  out[0] = d0; out[1] = d1; out[2] = d2;
  lua_getfield(L, t, k);
  if (lua_istable(L, -1)) for (int i = 0; i < 3; i++) { lua_rawgeti(L, -1, i + 1); if (lua_isnumber(L, -1)) out[i] = (float)lua_tonumber(L, -1); lua_pop(L, 1); }
  lua_pop(L, 1);
}
static void rgb_read(lua_State *L, int t, const char *k, float out[4], float d0, float d1, float d2) {   // 0..255 -> 0..1
  Col c = { (Uint8)(d0 * 255), (Uint8)(d1 * 255), (Uint8)(d2 * 255), 255 };
  lua_getfield(L, t, k);
  c = read_color(L, lua_gettop(L), c);
  lua_pop(L, 1);
  out[0] = c.r / 255.f; out[1] = c.g / 255.f; out[2] = c.b / 255.f; out[3] = c.a / 255.f;
}
static int g_r3_nodes;                             // (3D nodes drawn this frame: V->drawn counts them too)
static bool gpu3d;                                 // (the viewport being walked is the GPU's)
// picking 3D nodes (picking.h pick3d_hook): while a camera3d is drawn, what can be hit is listed with it (its
// shape: a bounds3d component's box or sphere, else its mesh); a click sends a ray through the picture: the
// shapes are tested, and a mesh's box, then (hit) its triangles. The nearest wins.
typedef struct Pick3D_ { char path[256]; const Mesh3D *m; float model[16]; int shape; float c[3], s[3]; } Pick3D;   // shape: 0 the mesh, 1 a box (s: half sizes), 2 a sphere (s[0]: radius); c: its middle, the node's own space
static struct { bool on; struct Cam3D_ *cam; Mat M; float w, h, vp[16]; } pick3d;
static void pick3d_list(void *camp, const char *path, const Mesh3D *m, const float model[16], int shape, const float c[3], const float sz[3]) {
  Cam3D *cam = camp;
  if (cam->np3 == cam->cap3) {
    int cap = cam->cap3 ? cam->cap3 * 2 : 32;
    if (cap > 4096) return;
    Pick3D *p = SDL_realloc(cam->p3, sizeof *p * (size_t)cap);
    if (!p) return;
    cam->p3 = p; cam->cap3 = cap;
  }
  Pick3D *e = &cam->p3[cam->np3++];
  SDL_strlcpy(e->path, path, sizeof e->path);
  e->m = m; SDL_memcpy(e->model, model, sizeof e->model); e->shape = shape;
  SDL_memcpy(e->c, c, sizeof e->c); SDL_memcpy(e->s, sz, sizeof e->s);
}
static void pick3d_record(lua_State *L, int node, int comp, const Mesh3D *m, const float model[16], bool shape_only) {
  if (!pick3d.on || !pick3d.cam) return;
  lua_getfield(L, node, "path");
  const char *path = lua_tostring(L, -1);
  lua_getfield(L, comp, "bounds3d");                // bounds3d = { w, h, d } (a box) | { r } (a sphere), x, y, z: its middle
  float c[3] = { 0, 0, 0 }, sz[3] = { 0, 0, 0 };
  int shape = -1;
  if (lua_istable(L, -1)) {
    int b = lua_gettop(L);
    c[0] = (float)fnum(L, b, "x", 0); c[1] = (float)fnum(L, b, "y", 0); c[2] = (float)fnum(L, b, "z", 0);
    if (lua_getfield(L, b, "r"), lua_isnumber(L, -1)) { shape = 2; sz[0] = (float)lua_tonumber(L, -1); }
    lua_pop(L, 1);
    if (shape < 0) { shape = 1; sz[0] = (float)fnum(L, b, "w", 1) / 2; sz[1] = (float)fnum(L, b, "h", 1) / 2; sz[2] = (float)fnum(L, b, "d", 1) / 2; }
  }
  lua_pop(L, 1);
  if (path) {
    if (shape > 0 && shape_only) pick3d_list(pick3d.cam, path, NULL, model, shape, c, sz);
    else if (shape < 0 && !shape_only && m) pick3d_list(pick3d.cam, path, m, model, 0, c, sz);
  }
  lua_pop(L, 1);
}
static bool m4_invert(const float m[16], float o[16]) {   // (column-major, general)
  float inv[16];
  inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
  inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
  inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
  inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
  inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
  inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
  inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
  inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
  inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
  inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
  inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
  inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
  inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
  inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
  inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
  inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];
  float det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
  if (fabsf(det) < 1e-20f) return false;
  for (int i = 0; i < 16; i++) o[i] = inv[i] / det;
  return true;
}
static void m4_point(const float m[16], const float p[3], float w, float o[3]) {
  for (int a = 0; a < 3; a++) o[a] = m[a] * p[0] + m[4 + a] * p[1] + m[8 + a] * p[2] + m[12 + a] * w;
}
static bool ray_box(const float O[3], const float D[3], const float lo[3], const float hi[3], float *t0) {   // (slabs) -> entered at t0 >= 0?
  float tn = -1e30f, tf = 1e30f;
  for (int a = 0; a < 3; a++) {
    if (fabsf(D[a]) < 1e-12f) { if (O[a] < lo[a] || O[a] > hi[a]) return false; continue; }
    float u = (lo[a] - O[a]) / D[a], v = (hi[a] - O[a]) / D[a];
    if (u > v) { float k = u; u = v; v = k; }
    if (u > tn) tn = u;
    if (v < tf) tf = v;
    if (tn > tf || tf < 0) return false;
  }
  *t0 = tn > 0 ? tn : 0;
  return true;
}
static bool ray_tri(const float O[3], const float D[3], const float *a, const float *b, const float *c, float *t) {   // (Moller-Trumbore: front faces, as drawn: counter-clockwise; a back face isn't seen, nor picked)
  float e1[3] = { b[0] - a[0], b[1] - a[1], b[2] - a[2] }, e2[3] = { c[0] - a[0], c[1] - a[1], c[2] - a[2] };
  float p[3] = { D[1] * e2[2] - D[2] * e2[1], D[2] * e2[0] - D[0] * e2[2], D[0] * e2[1] - D[1] * e2[0] };
  float det = e1[0] * p[0] + e1[1] * p[1] + e1[2] * p[2];
  if (det < 1e-12f) return false;
  float inv = 1 / det, s[3] = { O[0] - a[0], O[1] - a[1], O[2] - a[2] };
  float u = (s[0] * p[0] + s[1] * p[1] + s[2] * p[2]) * inv;
  if (u < 0 || u > 1) return false;
  float q[3] = { s[1] * e1[2] - s[2] * e1[1], s[2] * e1[0] - s[0] * e1[2], s[0] * e1[1] - s[1] * e1[0] };
  float v = (D[0] * q[0] + D[1] * q[1] + D[2] * q[2]) * inv;
  if (v < 0 || u + v > 1) return false;
  *t = (e2[0] * q[0] + e2[1] * q[1] + e2[2] * q[2]) * inv;
  return *t >= 0;
}
// a ray (world: O + t D) against one listed thing -> hit, its t
static bool pick3d_test(const Pick3D *e, const float O[3], const float D[3], float *t) {
  float inv[16], o[3], d[3];
  if (!m4_invert(e->model, inv)) return false;
  m4_point(inv, O, 1, o); m4_point(inv, D, 0, d);   // (the node's own space: the same t)
  if (e->shape == 1) {
    float lo[3] = { e->c[0] - e->s[0], e->c[1] - e->s[1], e->c[2] - e->s[2] }, hi[3] = { e->c[0] + e->s[0], e->c[1] + e->s[1], e->c[2] + e->s[2] };
    return ray_box(o, d, lo, hi, t);
  }
  if (e->shape == 2) {
    float oc[3] = { o[0] - e->c[0], o[1] - e->c[1], o[2] - e->c[2] };
    float A = d[0] * d[0] + d[1] * d[1] + d[2] * d[2], B = 2 * (oc[0] * d[0] + oc[1] * d[1] + oc[2] * d[2]), C = oc[0] * oc[0] + oc[1] * oc[1] + oc[2] * oc[2] - e->s[0] * e->s[0];
    float disc = B * B - 4 * A * C;
    if (A < 1e-20f || disc < 0) return false;
    float r = sqrtf(disc), t1 = (-B - r) / (2 * A), t2 = (-B + r) / (2 * A);
    *t = t1 >= 0 ? t1 : t2;
    return *t >= 0;
  }
  const Mesh3D *m = e->m;
  pose3d_cpu((Mesh3D *)m);                         // (skinned on the GPU: its vertices posed here now, to be hit)
  float tb;
  if (!m || !ray_box(o, d, m->bmin, m->bmax, &tb)) return false;   // (its box first: missed, no triangles)
  float best = 1e30f;
  for (int q = 0; q + 2 < m->ni; q += 3) {
    unsigned a = m->idx[q], b = m->idx[q + 1], c = m->idx[q + 2];
    if (a >= (unsigned)m->nv || b >= (unsigned)m->nv || c >= (unsigned)m->nv) continue;
    float tt;
    if (ray_tri(o, d, &m->pos[a * 3], &m->pos[b * 3], &m->pos[c * 3], &tt) && tt < best) best = tt;
  }
  if (best >= 1e30f) return false;
  *t = best;
  return true;
}
// the ray through a camera's picture at (u, v) (0..1, its top left 0) -> nearest path | NULL; *t its distance (the ray's)
static const char *pick3d_ray(const Cam3D *cam, float u, float v, float *tbest) {
  float inv[16];
  if (!cam->np3 || !m4_invert(cam->pvp, inv)) return NULL;
  float nx = u * 2 - 1, ny = 1 - v * 2;
  float a4[4] = { nx, ny, 0, 1 }, b4[4] = { nx, ny, 1, 1 }, A[4], B[4];
  for (int r = 0; r < 4; r++) { A[r] = inv[r] * a4[0] + inv[4 + r] * a4[1] + inv[8 + r] * a4[2] + inv[12 + r]; B[r] = inv[r] * b4[0] + inv[4 + r] * b4[1] + inv[8 + r] * b4[2] + inv[12 + r]; }
  if (fabsf(A[3]) < 1e-12f || fabsf(B[3]) < 1e-12f) return NULL;
  float O[3] = { A[0] / A[3], A[1] / A[3], A[2] / A[3] }, D[3] = { B[0] / B[3] - O[0], B[1] / B[3] - O[1], B[2] / B[3] - O[2] };
  const char *best = NULL;
  float bt = 1e30f;
  for (int i = 0; i < cam->np3; i++) {
    float t;
    if (pick3d_test(&cam->p3[i], O, D, &t) && t < bt) { bt = t; best = cam->p3[i].path; }
  }
  if (tbest) *tbest = bt;
  return best;
}
static const char *pick3d_at(float x, float y, SDL_FRect *cr, char *cam_path, size_t cap) {   // (picking.h's hook: picking's coordinates)
  Cam3D *top = NULL;
  Uint64 now = SDL_GetTicks();
  for (int i = 0; i < (int)SDL_arraysize(cams3d); i++) {   // (the last drawn under it: on top)
    Cam3D *c = &cams3d[i];
    const SDL_FRect *r = &c->rect;
    if (!c->path[0] || !c->np3 || now - (c->used - 1) > 1000) continue;
    if (x < r->x || y < r->y || x >= r->x + r->w || y >= r->y + r->h) continue;
    if (!top || c->used >= top->used) top = c;
  }
  if (!top) return NULL;
  Mat M = top->pM;
  float det = M.a * M.d - M.b * M.c;
  if (fabsf(det) < 1e-12f) return NULL;
  float px = x - M.tx, py = y - M.ty;
  float lx = (M.d * px - M.c * py) / det, ly = (-M.b * px + M.a * py) / det;   // (the picture's own place: its middle 0)
  float u = lx / top->pw2 + 0.5f, v = ly / top->ph2 + 0.5f;
  if (u < 0 || v < 0 || u > 1 || v > 1) return NULL;
  *cr = top->rect;
  SDL_strlcpy(cam_path, top->path, cap);
  return pick3d_ray(top, u, v, NULL);
}
// foliage3d: a node's scatter (runtime/foliage.lua, through boot.lua's viewer_foliage): every copy an item of
// the view, so the GPU draws a layer's copies instanced (render3d.h: one draw a part). The copies' places are
// read from Lua once a scatter (its items table: kept while its settings don't change), not every frame
typedef struct { const void *items; int n, nmesh; char mesh[16][256]; float wind[16], fade[16]; unsigned char *layer; float *data; Uint64 used; } Foliage3D;   // data: a copy's local matrix (16), its tint (4)
static Foliage3D foliage3d[16];
static float foliage_arr(lua_State *L, int arr, int i) { lua_rawgeti(L, arr, i); float v = (float)lua_tonumber(L, -1); lua_pop(L, 1); return v; }
static int foliage3d_drawn;                        // (copies added this frame: host_camera3d's tests)
static void draw3d_foliage(Viewer *V, G3View *G, int c, const float M[16]) {
  lua_State *L = V->L;
  int top = lua_gettop(L);
  lua_getfield(L, c, "foliage3d");
  if (!lua_istable(L, -1)) { lua_settop(L, top); return; }
  int comp = lua_gettop(L);
  lua_getglobal(L, "viewer_foliage");
  lua_rawgeti(L, LUA_REGISTRYINDEX, V->world);
  lua_pushvalue(L, comp);
  if (lua_pcall(L, 2, 1, 0) != 0 || !lua_istable(L, -1)) { lua_settop(L, top); return; }
  int it = lua_gettop(L);
  const void *key = lua_topointer(L, it);
  Foliage3D *F = NULL, *old = &foliage3d[0];
  for (int i = 0; i < (int)SDL_arraysize(foliage3d) && !F; i++) if (foliage3d[i].items == key && foliage3d[i].used) F = &foliage3d[i];
  if (!F) {                                        // (a new scatter, or its settings changed: read once)
    for (int i = 0; i < (int)SDL_arraysize(foliage3d); i++) if (foliage3d[i].used < old->used) old = &foliage3d[i];
    F = old;
    SDL_free(F->layer); SDL_free(F->data);
    SDL_zerop(F);
    int n = SDL_clamp((int)fnum(L, it, "n", 0), 0, 50000);
    F->layer = SDL_malloc((size_t)(n ? n : 1));
    F->data = SDL_malloc(sizeof(float) * 20 * (size_t)(n ? n : 1));
    if (!F->layer || !F->data) { SDL_free(F->layer); SDL_free(F->data); SDL_zerop(F); lua_settop(L, top); return; }
    lua_getfield(L, it, "meshes");
    if (lua_istable(L, -1)) for (int k = 1; k <= 16; k++) {
      lua_rawgeti(L, -1, k);
      if (lua_type(L, -1) == LUA_TSTRING) { SDL_strlcpy(F->mesh[k - 1], lua_tostring(L, -1), sizeof F->mesh[0]); F->nmesh = k; }
      lua_pop(L, 1);
    }
    lua_pop(L, 1);
    lua_getfield(L, it, "wind");                   // (a layer's wind, how far it stays whole)
    if (lua_istable(L, -1)) for (int k = 0; k < 16; k++) F->wind[k] = foliage_arr(L, lua_gettop(L), k + 1);
    lua_pop(L, 1);
    lua_getfield(L, it, "fade");
    if (lua_istable(L, -1)) for (int k = 0; k < 16; k++) F->fade[k] = foliage_arr(L, lua_gettop(L), k + 1);
    lua_pop(L, 1);
    static const char *names[13] = { "layer", "x", "y", "z", "rx", "ry", "rz", "sx", "sy", "sz", "r", "g", "b" };
    int arr[13];
    for (int k = 0; k < 13; k++) { lua_getfield(L, it, names[k]); arr[k] = lua_gettop(L); }
    for (int i = 0; i < n; i++) {
      float v[13];
      for (int k = 0; k < 13; k++) v[k] = lua_istable(L, arr[k]) ? foliage_arr(L, arr[k], i + 1) : 0;
      int li = (int)v[0] - 1;
      F->layer[i] = (unsigned char)(li >= 0 && li < 16 ? li : 255);
      float *d = &F->data[i * 20];
      m4_trs(v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], d);
      d[16] = v[10]; d[17] = v[11]; d[18] = v[12]; d[19] = 1;
    }
    F->items = key; F->n = n;
  }
  F->used = SDL_GetTicks() + 1;
  Mesh3D *mm[16] = { 0 };
  for (int k = 0; k < F->nmesh; k++) mm[k] = F->mesh[k][0] ? mesh3d_get(V, F->mesh[k]) : NULL;
  for (int i = 0; i < F->n; i++) {
    int li = F->layer[i];
    if (li >= F->nmesh || !mm[li]) continue;
    float W[16];
    m4_mul(M, &F->data[i * 20], W);
    G3Item *gi = g3_add(G, mm[li], W, &F->data[i * 20 + 16], NULL);
    if (gi) { gi->sway = F->wind[li]; gi->fade = F->fade[li]; foliage3d_drawn++; }
  }
  lua_settop(L, top);
}
static void tg_note_2d(const char *path, Mat M);   // (tgizmo.h: the selection's place, for the transform gizmo)
static void tg_note_3d(const char *path, const float M[16], const float parent[16], int cam);
static void draw3d_node(Viewer *V, R3Target *T, G3View *G, int node, const float parent[16], const float vp[16], const R3Light *Lt, int depth) {
  lua_State *L = V->L;
  if (depth > 32 || !lua_checkstack(L, 12)) return;
  node = absidx(L, node);
  int top = lua_gettop(L);
  lua_getfield(L, node, "c");
  int c = lua_gettop(L);
  if (!lua_istable(L, c) || fbool(L, c, "hidden")) { lua_settop(L, top); return; }
  float M[16];
  SDL_memcpy(M, parent, sizeof M);
  lua_getfield(L, c, "transform3d");
  if (!lua_istable(L, -1)) { lua_pop(L, 1); lua_getfield(L, c, "xform3d"); }   // (its old name, set by a game's own code)
  if (lua_istable(L, -1)) {
    int t = lua_gettop(L);
    float s = (float)fnum(L, t, "s", 1), Lm[16];
    m4_trs((float)fnum(L, t, "x", 0), (float)fnum(L, t, "y", 0), (float)fnum(L, t, "z", 0),
           (float)fnum(L, t, "rx", 0), (float)fnum(L, t, "ry", 0), (float)fnum(L, t, "rz", 0),
           (float)fnum(L, t, "sx", s), (float)fnum(L, t, "sy", s), (float)fnum(L, t, "sz", s), Lm);
    m4_mul(parent, Lm, M);
    if (V->selected[0] && pick3d.on && pick3d.cam && !V->standalone) {   // (the selection: the gizmo goes there)
      lua_getfield(L, node, "path");
      const char *np = lua_tostring(L, -1);
      if (np && !strcmp(np, V->selected)) tg_note_3d(np, M, parent, (int)(pick3d.cam - cams3d));
      lua_pop(L, 1);
    }
  }
  lua_pop(L, 1);
  lua_getfield(L, c, "mesh");
  if (lua_istable(L, -1) || lua_type(L, -1) == LUA_TSTRING) {
    int t = lua_gettop(L);
    const char *name = NULL;
    if (lua_type(L, t) == LUA_TSTRING) name = lua_tostring(L, t);
    else { lua_rawgeti(L, t, 1); name = lua_tostring(L, -1); lua_pop(L, 1); }
    Mesh3D *m = mesh3d_get(V, name);
    if (m && (m->njoints || m->nmorphs)) {        // animator = { clip = "walk" | n, t = seconds, loop = true, morphs = { mouthO = 1 } }: posed (phase 5)
      lua_getfield(L, c, "animator");
      if (lua_istable(L, -1)) {
        int an = lua_gettop(L);
        lua_getfield(L, an, "clip");
        int clip = lua_type(L, -1) == LUA_TNUMBER ? (int)lua_tointeger(L, -1) - 1 : mesh3d_clip(m, lua_tostring(L, -1));
        lua_pop(L, 1);
        lua_getfield(L, an, "loop");
        bool loop = lua_isnil(L, -1) || lua_toboolean(L, -1);
        lua_pop(L, 1);
        lua_getfield(L, node, "path");
        char key[300];
        SDL_snprintf(key, sizeof key, "node:%s", lua_tostring(L, -1) ? lua_tostring(L, -1) : "?");
        lua_pop(L, 1);
        float set[256];                            // morphs = { name = weight }: the game's, over the clip's
        bool any = false;
        lua_getfield(L, an, "morphs");
        if (lua_istable(L, -1) && m->nmorphs) {
          for (int k = 0; k < 256; k++) set[k] = NAN;
          lua_pushnil(L);
          while (lua_next(L, -2)) {
            int k = lua_type(L, -2) == LUA_TSTRING ? mesh3d_morph_index(m, lua_tostring(L, -2)) : -1;
            if (k >= 0 && k < 256 && lua_isnumber(L, -1)) { set[k] = (float)lua_tonumber(L, -1); any = true; }
            lua_pop(L, 1);
          }
        }
        lua_pop(L, 1);
        lua_getfield(L, an, "blend");              // blend = { clip = "Run", t = s, w = 0..1, loop = true }: a second clip over it
        if (lua_istable(L, -1)) {
          int bt = lua_gettop(L);
          lua_getfield(L, bt, "clip");
          pose_blend.clip = lua_type(L, -1) == LUA_TNUMBER ? (int)lua_tointeger(L, -1) - 1 : mesh3d_clip(m, lua_tostring(L, -1));
          lua_pop(L, 1);
          lua_getfield(L, bt, "loop");
          pose_blend.loop = lua_isnil(L, -1) || lua_toboolean(L, -1);
          lua_pop(L, 1);
          pose_blend.t = (float)fnum(L, bt, "t", 0);
          pose_blend.w = pose_blend.clip >= 0 ? (float)SDL_clamp(fnum(L, bt, "w", 0), 0, 1) : 0;
        }
        lua_pop(L, 1);
        pose3d_gpu = gpu3d && G3.skin_pipe;      // (the GPU's picture: skinned there, its matrices alone here)
        Mesh3D *posed = pose3d_get(key, m, clip, (float)fnum(L, an, "t", 0), loop, any ? set : NULL);
        pose3d_gpu = false;
        pose_blend.w = 0;
        if (posed) m = posed;
      }
      lua_pop(L, 1);
    }
    if (m) {
      float tint[4] = { 1, 1, 1, 1 };
      const Tex3D *tx = NULL;
      static Tex3D over;
      Tex *it = NULL;
      if (lua_istable(L, t)) {
        rgb_read(L, t, "color", tint, 1, 1, 1);
        lua_getfield(L, t, "texture");
        if (lua_type(L, -1) == LUA_TSTRING) {
          it = tex_get(V, lua_tostring(L, -1));
          if (it && tex_pixels(it)) { over = (Tex3D){ it->w, it->h, it->px }; tx = &over; } else it = NULL;
        }
        lua_pop(L, 1);
      }
      G3Item *gi = g3_add(G, m, M, tint, it && gpu3d ? g3_file_texture(it->file, tx) : NULL);   // (drawn when the walk is done: the sun's depth first)
      if (gi && V->selected[0] && pick3d.on) {     // (the selected node, or one under it: outlined)
        lua_getfield(L, node, "path");
        const char *np = lua_tostring(L, -1);
        size_t sl = strlen(V->selected);
        gi->outline = np && (!strcmp(np, V->selected) || (!strncmp(np, V->selected, sl) && np[sl] == '/'));
        lua_pop(L, 1);
      }
      pick3d_record(L, node, c, m, M, false);   // (its mesh: picked by a ray, unless it has a bounds3d)
      if (gi && tx) { gi->cpu_tex = *tx; gi->has_cpu_tex = true; }
      g_r3_nodes++;
    }
  }
  lua_pop(L, 1);
  draw3d_foliage(V, G, c, M);                      // (its scatter, when it has one: copies of meshes over an area)
  pick3d_record(L, node, c, NULL, M, true);        // (a bounds3d: its shape, mesh or none)
  if (world_call(V, "children", node, NULL) && lua_istable(L, -1)) {
    int kids = lua_gettop(L), n = (int)objlen(L, kids);
    for (int i = 1; i <= n; i++) { lua_rawgeti(L, kids, i); draw3d_node(V, T, G, -1, M, vp, Lt, depth + 1); lua_pop(L, 1); }
  }
  lua_settop(L, top);
}
static void draw_camera3d(Viewer *V, int node, int t, Mat M) {
  lua_State *L = V->L;
  g_mesh3d_viewer = V;
  if (!lua_istable(L, t)) return;
  node = absidx(L, node); t = absidx(L, t);
  float res = (float)fnum(L, t, "res", 1);
  float w = (float)fnum(L, t, "w", 320), h = (float)fnum(L, t, "h", 180);
  int pw = (int)(w * res), ph = (int)(h * res);
  if (pw < 1 || ph < 1 || pw > 2048 || ph > 2048) return;
  lua_getfield(L, node, "path");
  const char *path = lua_tostring(L, -1);
  char key[256];
  SDL_strlcpy(key, path ? path : "?", sizeof key);
  lua_pop(L, 1);
  Cam3D *cam = NULL, *old = &cams3d[0];            // (its picture: kept a camera, by path)
  for (int i = 0; i < (int)SDL_arraysize(cams3d) && !cam; i++) if (!strcmp(cams3d[i].path, key)) cam = &cams3d[i];
  if (!cam) {
    for (int i = 0; i < (int)SDL_arraysize(cams3d); i++) if (cams3d[i].used < old->used) old = &cams3d[i];
    cam = old;
    if (cam->tex) SDL_DestroyTexture(cam->tex);
    SDL_free(cam->t.rgba); SDL_free(cam->t.depth);
    if (cam->g.col || cam->g.items) g3_view_free(&cam->g);
    outline3d_free(cam);
    SDL_free(cam->p3);
    SDL_zerop(cam);
    SDL_strlcpy(cam->path, key, sizeof cam->path);
  }
  cam->used = SDL_GetTicks() + 1;
  float clear[4];
  rgb_read(L, t, "clear", clear, 40 / 255.f, 44 / 255.f, 52 / 255.f);
  unsigned char cl[4] = { (unsigned char)(clear[0] * 255), (unsigned char)(clear[1] * 255), (unsigned char)(clear[2] * 255), (unsigned char)(clear[3] * 255) };
  g3_release_views = cams3d_release;
  cam->gpu = !fbool(L, t, "cpu") && g3_init() && g3_view_size(&cam->g, V->ren, pw, ph);   // (cpu = true: the CPU draws it anyway)
  if (!cam->gpu && !r3_begin(&cam->t, pw, ph, cl)) return;
  float eye[3], at[3], up[3], view[16], proj[16], vp[16];
  v3_read(L, t, "eye", eye, 0, 2, 6);
  v3_read(L, t, "at", at, 0, 0, 0);
  v3_read(L, t, "up", up, 0, 1, 0);
  SDL_memcpy(cam->geye, eye, sizeof eye); SDL_memcpy(cam->gat, at, sizeof at);
  if (!V->standalone) fly3d_apply(cam, (int)(cam - cams3d), eye, at, up);   // (the editor's fly camera: its own eye)
  m4_look_at(eye, at, up, view);
  m4_perspective((float)fnum(L, t, "fov", 60), (float)pw / ph, (float)fnum(L, t, "near", 0.1), (float)fnum(L, t, "far", 100), proj);
  m4_mul(proj, view, vp);
  R3Light Lt;
  SDL_zero(Lt);
  float amb[4], sc[4];
  rgb_read(L, t, "ambient", amb, 0.35f, 0.35f, 0.4f);
  SDL_memcpy(Lt.ambient, amb, sizeof Lt.ambient);
  Lt.sun_dir[0] = -0.4f; Lt.sun_dir[1] = -1; Lt.sun_dir[2] = -0.3f;
  sc[0] = sc[1] = sc[2] = 0.85f;
  lua_getfield(L, t, "sun");
  if (lua_istable(L, -1)) {
    int st = lua_gettop(L);
    v3_read(L, st, "dir", Lt.sun_dir, -0.4f, -1, -0.3f);
    rgb_read(L, st, "color", sc, 0.85f, 0.85f, 0.85f);
  }
  lua_pop(L, 1);
  v3_norm(Lt.sun_dir);
  SDL_memcpy(Lt.sun_col, sc, sizeof Lt.sun_col);
  float shadow_area = 0;                           // shadows = true | { size = 1024 (texels), area = m round `at` (else: all of it) }
  lua_getfield(L, t, "shadows");
  if (lua_toboolean(L, -1)) {
    Lt.shadows = true; Lt.shadow_size = 1024;
    if (lua_istable(L, -1)) {
      int st = lua_gettop(L);
      Lt.shadow_size = SDL_clamp((int)fnum(L, st, "size", 1024), 64, 4096);
      shadow_area = (float)fnum(L, st, "area", 0);
    }
  }
  lua_pop(L, 1);
  float I[16];
  m4_identity(I);
  if (world_call(V, "children", node, NULL) && lua_istable(L, -1)) {   // (its 3D nodes: its subtree)
    int kids = lua_gettop(L), n = (int)objlen(L, kids);
    gpu3d = cam->gpu;
    pick3d.on = true; pick3d.cam = cam; pick3d.M = M; pick3d.w = w; pick3d.h = h; SDL_memcpy(pick3d.vp, vp, sizeof pick3d.vp);
    cam->np3 = 0; SDL_memcpy(cam->pvp, vp, sizeof cam->pvp); cam->pM = M; cam->pw2 = w; cam->ph2 = h;
    pick3d_hook = pick3d_at;
    for (int i = 1; i <= n; i++) { lua_rawgeti(L, kids, i); draw3d_node(V, &cam->t, &cam->g, -1, I, vp, &Lt, 0); lua_pop(L, 1); }
  }
  lua_pop(L, 1);
  pick3d.on = false;
  bool outlined = outline3d_build(cam, V->ren, &cam->g, vp, pw, ph);   // (the selected ones: before the list is drawn and emptied)
  if (Lt.shadows) s3_sun_fit(&cam->g, &Lt, at, shadow_area);
  SDL_Texture *pic = NULL;
  if (cam->gpu) {
    SDL_memcpy(g3_eye, eye, sizeof g3_eye); g3_time = (float)(SDL_GetTicks() % 3600000) / 1000.f;
    if (!g3_render(&cam->g, cl, vp, &Lt)) return;
    pic = cam->g.wrap;
  } else {
  r3_render(&cam->t, &cam->g, vp, &Lt);
  if (!cam->tex || cam->tw != pw || cam->th != ph) {
    if (cam->tex) SDL_DestroyTexture(cam->tex);
    cam->tex = SDL_CreateTexture(V->ren, SDL_PIXELFORMAT_RGBA32, SDL_TEXTUREACCESS_STREAMING, pw, ph);
    cam->tw = pw; cam->th = ph;
    if (cam->tex) { SDL_SetTextureBlendMode(cam->tex, SDL_BLENDMODE_BLEND); SDL_SetTextureScaleMode(cam->tex, SDL_SCALEMODE_NEAREST); }
  }
  if (!cam->tex) return;
  SDL_UpdateTexture(cam->tex, NULL, cam->t.rgba, pw * 4);
  pic = cam->tex;
  }
  SDL_FPoint q[4] = { xfa(M, -w / 2, -h / 2), xfa(M, w / 2, -h / 2), xfa(M, w / 2, h / 2), xfa(M, -w / 2, h / 2) };
  static const float uv[4][2] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } };
  SDL_Vertex v[4];
  SDL_FColor fc = { 1, 1, 1, g_alpha };
  for (int i = 0; i < 4; i++) { v[i].position = q[i]; v[i].color = fc; v[i].tex_coord.x = uv[i][0]; v[i].tex_coord.y = uv[i][1]; acc_add(q[i].x, q[i].y); }
  static const int idx[6] = { 0, 1, 2, 0, 2, 3 };
  SDL_RenderGeometry(V->ren, pic, v, 4, idx, 6);
  if (outlined && cam->otex) SDL_RenderGeometry(V->ren, cam->otex, v, 4, idx, 6);   // (the selection's outline, over it)
  cam->rect.x = SDL_min(SDL_min(q[0].x, q[1].x), SDL_min(q[2].x, q[3].x)); cam->rect.y = SDL_min(SDL_min(q[0].y, q[1].y), SDL_min(q[2].y, q[3].y));
  cam->rect.w = SDL_max(SDL_max(q[0].x, q[1].x), SDL_max(q[2].x, q[3].x)) - cam->rect.x;
  cam->rect.h = SDL_max(SDL_max(q[0].y, q[1].y), SDL_max(q[2].y, q[3].y)) - cam->rect.y;
  acc_solid = true;
}

// 3D views under lite (editor.h: host_view3d, host_model_info; plugins/modelview): lite leaves a
// hole in its picture (renderer.clear_rect), the host draws the view there, under lite's picture
// (replay.c: compose), so lite's menus and tooltips over it stay on top. Drawn again only when
// the request or the model changes; GPU or CPU, as camera3d.
typedef struct { float a[4]; unsigned char kind; } Seg3D;   // an overlay's line, in the picture's pixels: 0 wire, 1 normal, 2 bone, 3 joint (a dot)
typedef struct { bool used, drawn, outlined; EditorView3D req, last; unsigned mver, draws, read; Cam3D cam; Seg3D *segs; int nsegs, cap; } Lite3D;   // draws, read: the picture read back (tests) only when drawn since
static Lite3D lite3d[8];
static void lite3d_free(Lite3D *l) {
  if (l->cam.tex) SDL_DestroyTexture(l->cam.tex);
  SDL_free(l->cam.t.rgba); SDL_free(l->cam.t.depth);
  if (l->cam.g.col || l->cam.g.items) g3_view_free(&l->cam.g);
  SDL_free(l->segs);
  outline3d_free(&l->cam);
  SDL_zerop(l);
}
// the overlays (host_view3d overlay: 1 the skeleton, 2 the wireframe, 4 the normals): lines projected once a draw, in
// x-ray (no depth): drawn over the picture each frame
static bool lite3d_project(const float vp[16], const float p[3], int pw, int ph, float out[2]) {
  float x = vp[0] * p[0] + vp[4] * p[1] + vp[8] * p[2] + vp[12], y = vp[1] * p[0] + vp[5] * p[1] + vp[9] * p[2] + vp[13];
  float w = vp[3] * p[0] + vp[7] * p[1] + vp[11] * p[2] + vp[15];
  if (w < 1e-4f) return false;
  out[0] = (x / w * 0.5f + 0.5f) * pw; out[1] = (0.5f - y / w * 0.5f) * ph;
  return true;
}
static void lite3d_seg(Lite3D *l, const float vp[16], const float a[3], const float b[3], int pw, int ph, unsigned char kind) {
  float p[2], q[2];
  if (!lite3d_project(vp, a, pw, ph, p) || !lite3d_project(vp, b, pw, ph, q)) return;
  if (l->nsegs == l->cap) {
    int cap = l->cap ? l->cap * 2 : 1024;
    Seg3D *s2 = SDL_realloc(l->segs, sizeof *s2 * (size_t)cap);
    if (!s2) return;
    l->segs = s2; l->cap = cap;
  }
  Seg3D *g = &l->segs[l->nsegs++];
  g->a[0] = p[0]; g->a[1] = p[1]; g->a[2] = q[0]; g->a[3] = q[1]; g->kind = kind;
}
static void lite3d_overlay(Lite3D *l, const Mesh3D *base, const Mesh3D *m, const float vp[16], int pw, int ph) {
  l->nsegs = 0;
  unsigned ov = l->req.overlay;
  if (!ov || !m) return;
  float r = SDL_max(m->bmax[0] - m->bmin[0], SDL_max(m->bmax[1] - m->bmin[1], m->bmax[2] - m->bmin[2]));
  if (ov & 2) for (int q = 0; q + 2 < m->ni && l->nsegs < 400000; q += 3)   // (the triangles' edges)
    for (int e = 0; e < 3; e++) {
      unsigned a = m->idx[q + e], b = m->idx[q + (e + 1) % 3];
      if (a < (unsigned)m->nv && b < (unsigned)m->nv) lite3d_seg(l, vp, &m->pos[a * 3], &m->pos[b * 3], pw, ph, 0);   // (a shared edge: twice)
    }
  if (ov & 4) for (int v = 0; v < m->nv && l->nsegs < 400000; v++) {   // (a vertex's normal, 3% of its size)
    const float *P = &m->pos[v * 3], *N = &m->nrm[v * 3];
    float b[3] = { P[0] + N[0] * r * 0.03f, P[1] + N[1] * r * 0.03f, P[2] + N[2] * r * 0.03f };
    lite3d_seg(l, vp, P, b, pw, ph, 1);
  }
  if ((ov & 1) && base->njoints) {                 // (the joints as they're posed: a bone to each one's parent)
    float *W = SDL_malloc(sizeof(float) * 16 * (size_t)base->njoints), *mats = SDL_malloc(sizeof(float) * 16 * (size_t)SDL_max(base->nbinds, 1));
    if (l->req.bclip > 0 && l->req.bw > 0) { pose_blend.clip = l->req.bclip - 1; pose_blend.t = l->req.bt; pose_blend.w = SDL_min(l->req.bw, 1); pose_blend.loop = l->req.loop; }
    bool posed_ok = W && mats && mesh3d_pose(base, l->req.clip - 1, l->req.t, l->req.loop, mats, W);
    pose_blend.w = 0;
    if (posed_ok) {
      for (int j = 0; j < base->njoints; j++) {
        const float *J = &W[j * 16];
        int p = base->joints[j].parent;
        if (p >= 0) lite3d_seg(l, vp, &W[p * 16 + 12], &J[12], pw, ph, 2);
        lite3d_seg(l, vp, &J[12], &J[12], pw, ph, 3);
      }
    }
    SDL_free(W); SDL_free(mats);
  }
}
static void lite3d_request(const EditorView3D *v) {
  Lite3D *l = NULL, *free_one = NULL;
  for (int i = 0; i < (int)SDL_arraysize(lite3d); i++) {
    if (lite3d[i].used && !strcmp(lite3d[i].req.key, v->key)) l = &lite3d[i];
    else if (!lite3d[i].used && !free_one) free_one = &lite3d[i];
  }
  if (v->remove) { if (l) lite3d_free(l); return; }
  if (!l) { if (!free_one) return; l = free_one; l->used = true; }
  l->req = *v;
}
static bool lite3d_info(const char *file, EditorModelInfo *out) {
  if (!g_mesh3d_viewer) { SDL_strlcpy(out->err, "no viewer yet", sizeof out->err); return false; }
  char name[1100];
  SDL_snprintf(name, sizeof name, "file:%s", file);
  Mesh3D *m = mesh3d_get(g_mesh3d_viewer, name);
  if (!m) {
    for (int i = 0; i < nmeshes3d; i++) if (!strcmp(meshes3d[i].file, file)) SDL_strlcpy(out->err, meshes3d[i].err, sizeof out->err);
    if (!out->err[0]) SDL_strlcpy(out->err, "can't read it", sizeof out->err);
    return false;
  }
  out->nv = m->nv; out->ni = m->ni; out->nparts = SDL_min(m->nparts, 32); out->ntex = SDL_min(m->ntex, 32);
  out->njoints = m->njoints; out->nclips = SDL_min(m->nclips, 32);
  for (int i = 0; i < out->nclips; i++) { SDL_strlcpy(out->clip_name[i], m->clips[i].name, sizeof out->clip_name[i]); out->clip_len[i] = m->clips[i].duration; out->clip_loops[i] = m->clips[i].loops; }
  out->nmorphs = SDL_min(m->nmorphs, 32);
  for (int i = 0; i < out->nmorphs; i++) SDL_strlcpy(out->morph_name[i], m->morphs[i].name, sizeof out->morph_name[i]);
  SDL_memcpy(out->bmin, m->bmin, sizeof out->bmin); SDL_memcpy(out->bmax, m->bmax, sizeof out->bmax);
  for (int i = 0; i < out->nparts; i++) { SDL_memcpy(out->parts[i].base, m->parts[i].base, 16); out->parts[i].tex = m->parts[i].tex; out->parts[i].tris = m->parts[i].count / 3; }
  for (int i = 0; i < out->ntex; i++) { out->tex_w[i] = m->tex[i].w; out->tex_h[i] = m->tex[i].h; }
  return true;
}
// every lite view, under lite's picture: dst in window points (lite's pixels / retina), clipped to `clip`
static void lite3d_draw(Viewer *V, SDL_FRect clip, float retina) {
  g_mesh3d_viewer = V;
  for (int i = 0; i < (int)SDL_arraysize(lite3d); i++) {
    Lite3D *l = &lite3d[i];
    if (!l->used || l->req.w < 2 || l->req.h < 2) continue;
    int pw = (int)l->req.w, ph = (int)l->req.h;
    if (pw > 4096 || ph > 4096) continue;
    char name[1100];
    SDL_snprintf(name, sizeof name, "file:%s", l->req.file);
    Mesh3D *m = l->req.file[0] ? mesh3d_get(V, name) : NULL;
    unsigned mver = m ? m->version + 1 : 0;   // (a ground: the built-in plane, never read again)
    Cam3D *cam = &l->cam;
    bool gpu = g3_init();
    bool again = !l->drawn || memcmp(&l->req, &l->last, sizeof l->req) || mver != l->mver || gpu != cam->gpu;
    if (again) {
      cam->gpu = gpu && g3_view_size(&cam->g, V->ren, pw, ph);
      if (!cam->gpu && !r3_begin(&cam->t, pw, ph, l->req.clear)) continue;
      float view[16], proj[16], vp[16], I[16];
      m4_look_at(l->req.eye, l->req.at, l->req.up, view);
      m4_perspective(l->req.fov, (float)pw / ph, 0.01f, 1000, proj);
      m4_mul(proj, view, vp);
      m4_identity(I);
      R3Light Lt;
      SDL_zero(Lt);
      SDL_memcpy(Lt.ambient, l->req.ambient, 12); SDL_memcpy(Lt.sun_dir, l->req.sun_dir, 12); SDL_memcpy(Lt.sun_col, l->req.sun_col, 12);
      v3_norm(Lt.sun_dir);
      static const float white[4] = { 1, 1, 1, 1 };
      cam->g.n = 0;
      if (m && (m->njoints || m->nmorphs) && (l->req.clip > 0 || l->req.morph_mask)) {   // (a clip at t, the panel's blend shapes: posed)
        char pk[100];
        SDL_snprintf(pk, sizeof pk, "lite:%s", l->req.key);
        float set[256];
        for (int k = 0; k < 256; k++) set[k] = k < 32 && (l->req.morph_mask >> k & 1) ? l->req.morph[k] : NAN;
        if (l->req.bclip > 0 && l->req.bw > 0) { pose_blend.clip = l->req.bclip - 1; pose_blend.t = l->req.bt; pose_blend.w = SDL_min(l->req.bw, 1); pose_blend.loop = l->req.loop; }
        Mesh3D *posed = pose3d_get(pk, m, l->req.clip - 1, l->req.t, l->req.loop, l->req.morph_mask ? set : NULL);
        pose_blend.w = 0;
        if (posed) m = posed;
      }
      if (m && !l->req.hide_model) { G3Item *gi = g3_add(&cam->g, m, I, white, NULL); if (gi) gi->outline = l->req.outline; }   // (M: off, its bones alone, say; O: its outline)
      lite3d_overlay(l, l->req.file[0] ? mesh3d_get(V, name) : NULL, m, vp, pw, ph);
      Mesh3D *ground = m && l->req.ground ? mesh3d_get(V, "plane") : NULL;
      const Mesh3D *gb = l->req.file[0] ? mesh3d_get(V, name) : NULL;   // (the floor: where the model stands as read, not as posed,
      if (!gb) gb = m;                             //  else it moves and grows with the clip)
      if (ground) {                                // (a floor under it: what its shadow falls on)
        float r = SDL_max(gb->bmax[0] - gb->bmin[0], SDL_max(gb->bmax[1] - gb->bmin[1], gb->bmax[2] - gb->bmin[2])), G[16];
        float gc[4] = { 0.55f, 0.57f, 0.6f, 1 };
        m4_trs((gb->bmin[0] + gb->bmax[0]) / 2, gb->bmin[1] - r * 0.002f, (gb->bmin[2] + gb->bmax[2]) / 2, 0, 0, 0, r * 4, 1, r * 4, G);
        g3_add(&cam->g, ground, G, gc, NULL);
      }
      if (l->req.fol_n && l->req.fol) {            // a scatter's copies (plugins/foliage's preview), instanced; its floor
        if (l->req.ground && l->req.fol_w > 0) {
          float G[16], gc[4] = { 0.36f, 0.45f, 0.27f, 1 };
          m4_trs(0, -0.002f, 0, 0, 0, 0, l->req.fol_w, 1, l->req.fol_d, G);
          g3_add(&cam->g, mesh3d_get(V, "plane"), G, gc, NULL);
        }
        Mesh3D *mm[8] = { 0 };
        for (int k = 0; k < l->req.fol_nmesh && k < 8; k++) mm[k] = l->req.fol_mesh[k][0] ? mesh3d_get(V, l->req.fol_mesh[k]) : NULL;
        for (int i = 0; i < l->req.fol_n; i++) {
          const float *f = &l->req.fol[i * 14];
          int li = (int)f[0] - 1;
          if (li < 0 || li >= 8 || !mm[li]) continue;
          float W[16], tint[4] = { f[10], f[11], f[12], 1 };
          m4_trs(f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9], W);
          G3Item *gi = g3_add(&cam->g, mm[li], W, tint, NULL);
          if (gi) { gi->sway = l->req.fol_wind[li]; gi->fade = l->req.fol_fade[li]; }
        }
      }
      l->outlined = outline3d_build(cam, V->ren, &cam->g, vp, pw, ph);
      if (l->req.shadows) { Lt.shadows = true; Lt.shadow_size = 2048; s3_sun_fit(&cam->g, &Lt, l->req.at, 0); }
      if (cam->gpu) {
        SDL_memcpy(g3_eye, l->req.eye, sizeof g3_eye); g3_time = l->req.time;
        if (!g3_render(&cam->g, l->req.clear, vp, &Lt)) continue;
      } else {
        r3_render(&cam->t, &cam->g, vp, &Lt);
        if (!cam->tex || cam->tw != pw || cam->th != ph) {
          if (cam->tex) SDL_DestroyTexture(cam->tex);
          cam->tex = SDL_CreateTexture(V->ren, SDL_PIXELFORMAT_RGBA32, SDL_TEXTUREACCESS_STREAMING, pw, ph);
          cam->tw = pw; cam->th = ph;
          if (cam->tex) SDL_SetTextureScaleMode(cam->tex, SDL_SCALEMODE_NEAREST);
        }
        if (!cam->tex) continue;
        SDL_UpdateTexture(cam->tex, NULL, cam->t.rgba, pw * 4);
      }
      l->last = l->req; l->mver = mver; l->drawn = true; l->draws++;
    }
    SDL_Texture *pic = cam->gpu ? cam->g.wrap : cam->tex;
    if (!pic) continue;
    SDL_SetTextureBlendMode(pic, SDL_BLENDMODE_NONE);   // (opaque: kit.gpu's lesson, its clear colour's alpha is not a hole)
    SDL_FRect dst = { l->req.x / retina, l->req.y / retina, l->req.w / retina, l->req.h / retina }, in;
    if (!SDL_GetRectIntersectionFloat(&dst, &clip, &in)) continue;
    SDL_FRect src = { (in.x - dst.x) * retina, (in.y - dst.y) * retina, in.w * retina, in.h * retina };
    SDL_RenderTexture(V->ren, pic, &src, &in);
    if (l->outlined && cam->otex) SDL_RenderTexture(V->ren, cam->otex, &src, &in);   // (its outline: yellow, 2 px)
    if (l->nsegs) {                                // (its overlays, over it: clipped to it)
      SDL_Rect cr = { (int)SDL_floorf(in.x), (int)SDL_floorf(in.y), (int)SDL_ceilf(in.w), (int)SDL_ceilf(in.h) };
      SDL_SetRenderClipRect(V->ren, &cr);
      SDL_SetRenderDrawBlendMode(V->ren, SDL_BLENDMODE_BLEND);
      static const unsigned char col[4][4] = { { 235, 235, 245, 70 }, { 90, 170, 255, 200 }, { 255, 210, 60, 255 }, { 255, 120, 40, 255 } };
      for (int kind = 0; kind < 4; kind++) {
        SDL_SetRenderDrawColor(V->ren, col[kind][0], col[kind][1], col[kind][2], col[kind][3]);
        for (int k = 0; k < l->nsegs; k++) {
          const Seg3D *g = &l->segs[k];
          if (g->kind != kind) continue;
          float x1 = dst.x + g->a[0] / retina, y1 = dst.y + g->a[1] / retina, x2 = dst.x + g->a[2] / retina, y2 = dst.y + g->a[3] / retina;
          if (kind == 3) { SDL_FRect d = { x1 - 2, y1 - 2, 4, 4 }; SDL_RenderFillRect(V->ren, &d); }
          else SDL_RenderLine(V->ren, x1, y1, x2, y2);
        }
      }
      SDL_SetRenderClipRect(V->ren, NULL);
    }
  }
}
// a model's thumbnail (editor.h host_model_thumb: the tree's /assets): the CPU's picture px x px, its background
// clear (alpha 0), seen from the front-right and above, fitted, the rest pose
static bool lite3d_thumb(const char *file, int px, unsigned char *rgba) {
  if (!g_mesh3d_viewer || px < 8 || px > 256) return false;
  char name[1100];
  SDL_snprintf(name, sizeof name, "file:%s", file);
  Mesh3D *m = mesh3d_get(g_mesh3d_viewer, name);
  if (!m) return false;
  static R3Target T;
  static const unsigned char clear[4] = { 0, 0, 0, 0 };
  if (!r3_begin(&T, px, px, clear)) return false;
  float c[3] = { (m->bmin[0] + m->bmax[0]) / 2, (m->bmin[1] + m->bmax[1]) / 2, (m->bmin[2] + m->bmax[2]) / 2 };
  float dx = m->bmax[0] - m->bmin[0], dy = m->bmax[1] - m->bmin[1], dz = m->bmax[2] - m->bmin[2];
  float r = SDL_max(1e-3f, sqrtf(dx * dx + dy * dy + dz * dz) / 2), d = r / sinf(22.5f * 3.14159265f / 180) * 1.02f;
  float eye[3] = { c[0] + d * cosf(0.35f) * sinf(0.6f), c[1] + d * sinf(0.35f), c[2] + d * cosf(0.35f) * cosf(0.6f) }, up[3] = { 0, 1, 0 };
  float view[16], proj[16], vp[16], I[16];
  m4_look_at(eye, c, up, view);
  m4_perspective(45, 1, d * 0.01f, d * 4, proj);
  m4_mul(proj, view, vp);
  m4_identity(I);
  R3Light Lt;
  SDL_zero(Lt);
  Lt.ambient[0] = Lt.ambient[1] = Lt.ambient[2] = 0.4f;
  Lt.sun_dir[0] = -0.4f; Lt.sun_dir[1] = -1; Lt.sun_dir[2] = -0.3f; v3_norm(Lt.sun_dir);
  Lt.sun_col[0] = Lt.sun_col[1] = Lt.sun_col[2] = 0.8f;
  static const float white[4] = { 1, 1, 1, 1 };
  r3_draw(&T, m, I, vp, white, &Lt, NULL);
  SDL_memcpy(rgba, T.rgba, (size_t)px * px * 4);
  return true;
}
static void lite3d_release(void) { for (int i = 0; i < (int)SDL_arraysize(lite3d); i++) if (lite3d[i].cam.g.col || lite3d[i].cam.g.items) g3_view_free(&lite3d[i].cam.g); }
// a lite view's last picture (editor.h host_view3d_pixel; tests): out = w, h, triangles, r, g, b, a (r -1: no pixel asked), overlay lines
static bool lite3d_pixel(const char *key, int x, int y, int *out) {
  for (int i = 0; i < (int)SDL_arraysize(lite3d); i++) {
    Lite3D *l = &lite3d[i];
    if (!l->used || strcmp(l->req.key, key) || !l->drawn) continue;
    Cam3D *c = &l->cam;
    if (c->gpu) {
      if (c->t.w != c->g.w || c->t.h != c->g.h || !c->t.rgba) {
        SDL_free(c->t.rgba); c->t.rgba = SDL_malloc((size_t)c->g.w * c->g.h * 4); c->t.w = c->g.w; c->t.h = c->g.h; l->read = l->draws + 1;
      }
      if (l->read != l->draws || !c->t.rgba) {
        if (!c->t.rgba || !g3_read(&c->g, c->t.rgba)) return false;
        l->read = l->draws;
      }
      c->t.tris = c->g.tris;
    }
    out[0] = c->t.w; out[1] = c->t.h; out[2] = c->t.tris; out[3] = -1; out[7] = l->nsegs; out[8] = 0;
    if (l->outlined && c->orgba) for (int k = 0; k < c->ow * c->oh; k++) if (c->orgba[k * 4 + 3]) out[8]++;   // (its outline's pixels)
    if (x >= 0 && y >= 0 && x < c->t.w && y < c->t.h) {
      const unsigned char *p = &c->t.rgba[((size_t)y * c->t.w + x) * 4];
      for (int k = 0; k < 4; k++) out[3 + k] = p[k];
    }
    return true;
  }
  return false;
}

// host_camera3d(path [, x, y]) -> w, h, triangles drawn [, r, g, b, a at x, y | draw calls (the GPU's; else -1), "gpu" | "cpu"] | nil: a viewport's
// last picture (tests; later: picking)
static int l_host_camera3d(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  for (int i = 0; i < (int)SDL_arraysize(cams3d); i++) {
    Cam3D *c = &cams3d[i];
    if (strcmp(c->path, path)) continue;
    if (c->gpu) {                                  // (the GPU's picture: read back, as the CPU's would be)
      if (c->t.w != c->g.w || c->t.h != c->g.h || !c->t.rgba) {
        SDL_free(c->t.rgba); SDL_free(c->t.depth); c->t.depth = NULL;
        c->t.rgba = SDL_malloc((size_t)c->g.w * c->g.h * 4); c->t.w = c->g.w; c->t.h = c->g.h;
      }
      if (!c->t.rgba || !g3_read(&c->g, c->t.rgba)) return 0;
      c->t.tris = c->g.tris;
    }
    if (!c->t.rgba) continue;
    bool at = lua_isnumber(L, 2) && lua_isnumber(L, 3);   // (asked before anything is pushed: index 2 is then w)
    int x = at ? (int)lua_tointeger(L, 2) : 0, y = at ? (int)lua_tointeger(L, 3) : 0;
    lua_pushinteger(L, c->t.w); lua_pushinteger(L, c->t.h); lua_pushinteger(L, c->t.tris);
    if (at) {
      if (x < 0 || y < 0 || x >= c->t.w || y >= c->t.h) return 3;
      const unsigned char *p = &c->t.rgba[((size_t)y * c->t.w + x) * 4];
      for (int k = 0; k < 4; k++) lua_pushinteger(L, p[k]);
      return 7;
    }
    lua_pushinteger(L, c->gpu ? c->g.draws : -1);   // (the GPU's draw calls: a mesh drawn many times is one a part)
    lua_pushstring(L, c->gpu ? "gpu" : "cpu");
    return 5;
  }
  return 0;
}
// host_mesh3d(name) -> vertices, indices, parts, textures, its first texture's w, h | nil, why: a model as read (tests)
// host_render3d() -> "gpu" | "cpu", why: what draws 3D viewports here
static int l_host_render3d(lua_State *L) {
  bool ok = g3_init();
  lua_pushstring(L, ok ? "gpu" : "cpu");
  lua_pushstring(L, ok ? gpu_driver() : G3.err);
  return 2;
}
static int l_host_mesh3d(lua_State *L) {
  const char *name = luaL_checkstring(L, 1);
  if (!g_mesh3d_viewer) return 0;
  Mesh3D *m = mesh3d_get(g_mesh3d_viewer, name);
  if (!m) {
    lua_pushnil(L);
    for (int i = 0; i < nmeshes3d; i++) if (SDL_strstr(meshes3d[i].file, name[0] == '/' ? name + 8 : name)) { lua_pushstring(L, meshes3d[i].err); return 2; }
    lua_pushstring(L, "not read");
    return 2;
  }
  lua_pushinteger(L, m->nv); lua_pushinteger(L, m->ni); lua_pushinteger(L, m->nparts); lua_pushinteger(L, m->ntex);
  int tw = 0, th = 0;
  for (int i = 0; i < m->ntex; i++) if (m->tex[i].rgba) { tw = m->tex[i].w; th = m->tex[i].h; break; }
  lua_pushinteger(L, tw); lua_pushinteger(L, th);
  lua_pushinteger(L, m->njoints); lua_pushinteger(L, m->nclips); lua_pushinteger(L, m->nmorphs);
  return 9;
}
// host_outline3d(camera path) -> pixels of its selection's outline (0: none; tests)
static int l_host_outline3d(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  for (int i = 0; i < (int)SDL_arraysize(cams3d); i++) {
    Cam3D *c = &cams3d[i];
    if (strcmp(c->path, path) || !c->orgba) continue;
    int n = 0;
    for (int k = 0; k < c->ow * c->oh; k++) if (c->orgba[k * 4 + 3]) n++;
    lua_pushinteger(L, n);
    return 1;
  }
  lua_pushinteger(L, 0);
  return 1;
}
// host_pick3d(camera, u, v) -> path, distance | nil: what a ray through its picture at u, v (0..1) hits (tests)
static int l_host_pick3d(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  for (int i = 0; i < (int)SDL_arraysize(cams3d); i++) {
    if (strcmp(cams3d[i].path, path)) continue;
    float t;
    const char *hit = pick3d_ray(&cams3d[i], (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3), &t);
    if (!hit) return 0;
    lua_pushstring(L, hit); lua_pushnumber(L, t);
    return 2;
  }
  return 0;
}
// host_pick(x, y) -> path | nil: what a right-click there picks (window points; tests)
static int l_host_pick(lua_State *L) {
  const Pick *p = pick_at((float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2));
  if (!p) return 0;
  lua_pushstring(L, p->path);
  return 1;
}
// host_pose3d(name, clip, t, vertex) -> x, y, z: a skinned model's vertex (1-based) posed at t (tests)
static int l_host_pose3d(lua_State *L) {
  const char *name = luaL_checkstring(L, 1);
  if (!g_mesh3d_viewer) return 0;
  Mesh3D *m = mesh3d_get(g_mesh3d_viewer, name);
  if (!m || !(m->njoints || m->nmorphs)) return 0;
  int clip = lua_type(L, 2) == LUA_TNUMBER ? (int)lua_tointeger(L, 2) - 1 : mesh3d_clip(m, lua_tostring(L, 2));
  int v = (int)luaL_checkinteger(L, 4) - 1;
  if (v < 0 || v >= m->nv) return 0;
  float set[256];                                  // (5: { name = weight }: blend shapes over the clip's)
  bool any = false;
  if (lua_istable(L, 5)) {
    for (int k = 0; k < 256; k++) set[k] = NAN;
    lua_pushnil(L);
    while (lua_next(L, 5)) {
      int k = lua_type(L, -2) == LUA_TSTRING ? mesh3d_morph_index(m, lua_tostring(L, -2)) : -1;
      if (k >= 0 && k < 256 && lua_isnumber(L, -1)) { set[k] = (float)lua_tonumber(L, -1); any = true; }
      lua_pop(L, 1);
    }
  }
  if (lua_istable(L, 6)) {                         // (6: { clip, t, w }: a second clip blended over it)
    lua_getfield(L, 6, "clip");
    pose_blend.clip = lua_type(L, -1) == LUA_TNUMBER ? (int)lua_tointeger(L, -1) - 1 : mesh3d_clip(m, lua_tostring(L, -1));
    lua_pop(L, 1);
    lua_getfield(L, 6, "t"); pose_blend.t = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    lua_getfield(L, 6, "w"); pose_blend.w = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    pose_blend.loop = false;
  }
  Mesh3D *p = pose3d_get("hook:host_pose3d", m, clip, (float)luaL_optnumber(L, 3, 0), false, any ? set : NULL);
  pose_blend.w = 0;
  if (!p) return 0;
  for (int k = 0; k < 3; k++) lua_pushnumber(L, p->pos[v * 3 + k]);
  return 3;
}
static void draw_gizmo(Viewer *V, Mat M, const char *name) {
  SDL_FPoint o = xf(M, 0, 0), ax = xf(M, 12, 0), ay = xf(M, 0, 12);
  SDL_SetRenderDrawColor(V->ren, 255, 80, 80, 255);
  SDL_RenderLine(V->ren, o.x, o.y, ax.x, ax.y);
  SDL_SetRenderDrawColor(V->ren, 80, 255, 80, 255);
  SDL_RenderLine(V->ren, o.x, o.y, ay.x, ay.y);
  SDL_SetRenderDrawColor(V->ren, 150, 150, 170, 255);
  SDL_RenderDebugText(V->ren, o.x + 4, o.y + 4, name);
}

// ---------------------------------------------------------------------------
// tree traversal
// ---------------------------------------------------------------------------

// ref: 0 = normal node, 1 = root of a `ref` instance, 2 = inside an instance
// Draw order: layers. A node's `layer` component (a name; else its
// parent's; the root's: "default") puts it, and what's below it, in that
// layer; /data/layers' `order` lists the layers bottom to top (unlisted ones
// after, by name: runtime/boot.lua viewer_layers). One pass a layer, each in
// tree order; with one layer (none set), one pass as before.
static char g_lay_names[16][32];
static int g_nlay, g_lay_pass = -1, g_lay_inh;
static int layer_index(const char *name) {
  for (int i = 0; i < g_nlay; i++) if (!strcmp(g_lay_names[i], name)) return i;
  return g_lay_inh;
}

static void draw_node(Viewer *V, int node, Mat parent, Col pcol, int depth, int ref) {
  lua_State *L = V->L;
  if (depth > 64 || !lua_checkstack(L, 16)) return;
  node = absidx(L, node);
  int top = lua_gettop(L);

  lua_getfield(L, node, "c");
  int c = lua_gettop(L);
  if (!lua_istable(L, c)) { lua_settop(L, top); return; }
  if (fbool(L, c, "hidden") && ref != 1) { lua_settop(L, top); return; }
  int lay = g_lay_inh;                             // its layer: its own, or its parent's
  if (g_nlay > 1) {
    lua_getfield(L, c, "layer");
    if (lua_type(L, -1) == LUA_TSTRING) lay = layer_index(lua_tostring(L, -1));
    lua_pop(L, 1);
  }
  bool mine = g_lay_pass < 0 || lay == g_lay_pass; // (this pass draws it, or only goes through it)

  // transform
  Mat M = parent;
  bool has_xf = false;
  lua_getfield(L, c, "transform");
  if (!lua_istable(L, -1)) { lua_pop(L, 1); lua_getfield(L, c, "xform"); }   // (its old name, set by a game's own code)
  if (!lua_istable(L, -1)) { lua_pop(L, 1); lua_getfield(L, c, "pos"); }
  if (lua_istable(L, -1)) {
    int t = lua_gettop(L);
    float x = (float)fnum(L, t, "x", 0), y = (float)fnum(L, t, "y", 0);
    float r = (float)fnum(L, t, "r", 0), s = (float)fnum(L, t, "s", 1);
    float sx = (float)fnum(L, t, "sx", s), sy = (float)fnum(L, t, "sy", s);
    float kx = (float)fnum(L, t, "shear", 0), ky = (float)fnum(L, t, "shear_y", 0);   // (shear: the top leans right by that much of the height; shear_y: the right side goes down)
    Mat Lm = { cosf(r) * sx, sinf(r) * sx, -sinf(r) * sy, cosf(r) * sy, x, y };
    if (kx != 0 || ky != 0) {                      // (rotate . scale . shear: x' = x - kx y, y' = y + ky x)
      Mat A = Lm;
      Lm.a = A.a + A.c * ky; Lm.b = A.b + A.d * ky;
      Lm.c = A.c - A.a * kx; Lm.d = A.d - A.b * kx;
    }
    M = mat_mul(parent, Lm);
    has_xf = true;
  }
  lua_pop(L, 1);

  // color
  lua_getfield(L, c, "color");
  Col col = read_color(L, lua_gettop(L), pcol);
  lua_pop(L, 1);

  // visuals
  static const struct { const char *k; void (*fn)(Viewer *, int, Mat, Col); } VIS[] = {
    { "tris", draw_tris }, { "rect", draw_rect }, { "circle", draw_circle },
    { "tilemap", draw_tilemap },
    { "lines", draw_lines }, { "sprite", draw_sprite }, { "image", draw_image }, { "text", draw_text },
    { "bullets", draw_bullets },
  };
  bool drew = false;
  acc_reset();
  for (size_t i = 0; mine && i < sizeof VIS / sizeof VIS[0]; i++) {
    lua_getfield(L, c, VIS[i].k);
    if (!lua_isnil(L, -1)) { VIS[i].fn(V, lua_gettop(L), M, col); drew = true; }
    lua_pop(L, 1);
  }
  if (mine) {                                      // a 3D viewport: its subtree's 3D nodes, as its picture
    lua_getfield(L, c, "camera3d");
    if (lua_istable(L, -1)) { draw_camera3d(V, node, lua_gettop(L), M); drew = true; }
    lua_pop(L, 1);
  }
  lua_getfield(L, node, "path");
  const char *mypath = lua_tostring(L, -1);        // stays alive in the node table
  lua_pop(L, 1);
  if (mine && has_xf && ref == 0 && mypath && V->selected[0] && !V->standalone && !strcmp(mypath, V->selected) && g_alpha >= 1.f)
    tg_note_2d(mypath, M);                         // (the selection: the gizmo goes there)
  if (drew && mypath)
    pick_add(mypath, ref ? cur_via : NULL, ref ? cur_cls : NULL, acc_x0, acc_y0, acc_x1, acc_y1,
             acc_solid, acc_seg0, nsegs, 0, 0);

  // bounds: an explicit picking shape in node space
  lua_getfield(L, c, "bounds");
  if (mine && lua_istable(L, -1) && mypath) {
    int b = lua_gettop(L);
    SDL_FPoint q[32];
    int n = 0;
    float r = (float)fnum(L, b, "r", 0);
    if (r > 0) {                                    // circle
      float cx = (float)fnum(L, b, "x", 0), cy = (float)fnum(L, b, "y", 0);
      for (n = 0; n < 32; n++) {
        float a = n / 32.f * 6.2831853f;
        q[n] = xf(M, cx + r * cosf(a), cy + r * sinf(a));
      }
    } else {                                        // box
      float bw = (float)fnum(L, b, "w", 0), bh = (float)fnum(L, b, "h", 0);
      float bx = (float)fnum(L, b, "x", -bw / 2), by = (float)fnum(L, b, "y", -bh / 2);
      if (bw > 0 && bh > 0) {
        q[0] = xf(M, bx, by); q[1] = xf(M, bx + bw, by);
        q[2] = xf(M, bx + bw, by + bh); q[3] = xf(M, bx, by + bh);
        n = 4;
      }
    }
    if (n) {
      float x0 = 1e30f, y0 = 1e30f, x1 = -1e30f, y1 = -1e30f;
      for (int i = 0; i < n; i++) {
        if (q[i].x < x0) x0 = q[i].x;
        if (q[i].y < y0) y0 = q[i].y;
        if (q[i].x > x1) x1 = q[i].x;
        if (q[i].y > y1) y1 = q[i].y;
      }
      if (fbool(L, b, "aabb")) {                    // screen-aligned box around it
        q[0].x = x0; q[0].y = y0; q[1].x = x1; q[1].y = y0;
        q[2].x = x1; q[2].y = y1; q[3].x = x0; q[3].y = y1;
        n = 4;
      }
      int p0 = npolys;
      acc_poly(q, n);
      pick_add(mypath, ref ? cur_via : NULL, ref ? cur_cls : NULL, x0 + 2, y0 + 2, x1 - 2, y1 - 2,
               false, 0, 0, p0, npolys);
      if (npicks && picks[npicks - 1].poly0 == p0) picks[npicks - 1].bounded = true;
    }
  }
  lua_pop(L, 1);

  // ref: instance another node (and its subtree) with our transform
  lua_getfield(L, c, "ref");
  if (lua_type(L, -1) == LUA_TSTRING) {
    const char *path = lua_tostring(L, -1);
    if (world_call(V, "node", 0, path) && lua_istable(L, -1)) {
      char saved[256], saved_cls[256];
      SDL_strlcpy(saved, cur_via, sizeof saved);
      SDL_strlcpy(saved_cls, cur_cls, sizeof saved_cls);
      if (ref == 0 && mypath) {                     // outermost instance and its class
        SDL_strlcpy(cur_via, mypath, sizeof cur_via);
        SDL_strlcpy(cur_cls, path, sizeof cur_cls);
      }
      int inh = g_lay_inh;
      g_lay_inh = lay;
      draw_node(V, -1, M, col, depth + 1, 1);
      g_lay_inh = inh;
      SDL_strlcpy(cur_via, saved, sizeof cur_via);
      SDL_strlcpy(cur_cls, saved_cls, sizeof cur_cls);
      drew = true;
    }
    lua_pop(L, 1);
  }
  lua_pop(L, 1);
  if (drew) V->drawn++;

  // gizmos (dev UI only): placed nodes with nothing to draw; with the toolbar's
  // Gizmos on, the selected nodes and everything under them too (/: all)
  if (mine && has_xf && ref == 0 && !V->standalone && ((V->gizmos && gizmo_wanted(V, mypath)) || !drew) && g_alpha >= 1.f) {   // (not a ghost's)
    lua_getfield(L, node, "name");
    draw_gizmo(V, M, lua_tostring(L, -1) ? lua_tostring(L, -1) : "?");
    lua_pop(L, 1);
    if (!drew && mypath) {                          // markers are clickable too
      SDL_FPoint o = xf(M, 0, 0);
      pick_add(mypath, NULL, NULL, o.x - 6, o.y - 6, o.x + 14, o.y + 14, true, 0, 0, 0, 0);
    }
  }

  // children, in sorted order (in our layer, unless they say otherwise)
  int inh = g_lay_inh;
  g_lay_inh = lay;
  if (world_call(V, "children", node, NULL) && lua_istable(L, -1)) {
    int kids = lua_gettop(L), n = (int)objlen(L, kids);
    for (int i = 1; i <= n; i++) {
      lua_rawgeti(L, kids, i);
      bool live = true;                            // the root's children: only /o and /e are drawn (the layout; ecs: World:live)
      if (depth == 0 && ref == 0) {
        lua_getfield(L, -1, "path");
        const char *cp = lua_tostring(L, -1);
        if (cp && world_call(V, "live", 0, cp)) live = lua_toboolean(L, -1);
        lua_pop(L, 2);
      }
      if (live) draw_node(V, -1, M, col, depth + 1, ref ? 2 : 0);
      lua_pop(L, 1);
    }
  }
  g_lay_inh = inh;
  lua_settop(L, top);
}

// a world's tree, from its root (on the stack at `node`): one pass a layer
static void draw_layers(Viewer *V, int node, Mat cam, Col col) {
  lua_State *L = V->L;
  node = absidx(L, node);
  g_nlay = 0;
  int def = 0;
  lua_getglobal(L, "viewer_layers");               // the layers' names, bottom to top
  lua_rawgeti(L, LUA_REGISTRYINDEX, V->world);
  if (lua_pcall(L, 1, 1, 0) == 0 && lua_istable(L, -1)) {
    int n = (int)objlen(L, -1);
    for (int i = 1; i <= n && g_nlay < 16; i++) {
      lua_rawgeti(L, -1, i);
      if (lua_isstring(L, -1)) {
        SDL_strlcpy(g_lay_names[g_nlay], lua_tostring(L, -1), sizeof g_lay_names[0]);
        if (!strcmp(g_lay_names[g_nlay], "default")) def = g_nlay;
        g_nlay++;
      }
      lua_pop(L, 1);
    }
  }
  lua_pop(L, 1);
  g_lay_inh = def;
  if (g_nlay <= 1) { g_lay_pass = -1; draw_node(V, node, cam, col, 0, 0); return; }
  for (int p = 0; p < g_nlay; p++) { g_lay_pass = p; g_lay_inh = def; draw_node(V, node, cam, col, 0, 0); }
  g_lay_pass = -1;
}
