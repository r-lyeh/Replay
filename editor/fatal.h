// editor/fatal.h - the error overlay (Replay). Part of replay.c: included once,
// after bar.h.
//
// When something fails while the game runs, a box over the game area says
// what, over the game and its overlay (debug draws, stats), and it's modal:
// nothing reads the keys, the mouse or the pads (not the game, not the
// editor, not the bar) until it's dismissed, and the game is paused.
//   - a system broke (a runtime error: it stops, the rest go on): its error,
//     its file and line (a click opens it in the editor, as a red row in the
//     tree does: runtime/boot.lua viewer_errors)
//   - a tick failed outright (a system that isn't a code leaf): its message
//   - the game's own panic: w:panic(title, text) (runtime/ecs.lua), its fatal
//     screen; w.on_panic_closed(w) when it's dismissed
// Enter, Space, ESC or Continue dismiss it (the game goes on if it was
// playing); a click on an error opens its line (the game stays paused). An
// exported game shows it too (nothing to open there).
#define FATAL_MAX 12
static struct {
  bool on, was_playing;
  int seq;                                         // (the world's fail_seq seen last: a new one opens it)
  char tick_err[256];                              // (the last tick error opened: not again)
  char title[160];
  int n;
  char text[FATAL_MAX][400], file[FATAL_MAX][1024];
  int line[FATAL_MAX];
  SDL_FRect item[FATAL_MAX], btn;
  int hot;                                         // (-1 none, 0..n-1 an item, FATAL_MAX the button)
} g_fatal = { .hot = -1 };

static void fatal_show(Viewer *V) {
  g_fatal.on = true;
  g_fatal.was_playing = !V->paused && !V->stopped;
  V->paused = true;
  release_game_keys(V);
}
static void fatal_dismiss(Viewer *V, bool resume) {
  g_fatal.on = false;
  if (V->world != LUA_NOREF) {
    lua_State *L = V->L;
    lua_getglobal(L, "viewer_errors_dismiss");
    lua_rawgeti(L, LUA_REGISTRYINDEX, V->world);
    if (lua_pcall(L, 1, 0, 0) != 0) lua_pop(L, 1);
  }
  if (resume && g_fatal.was_playing && !V->stopped) V->paused = false;
}
// every frame: a new failure (the world's count went up, or a tick error) opens it
static void fatal_poll(Viewer *V) {
  if (V->world == LUA_NOREF) return;
  if (V->stopped) { if (g_fatal.on) g_fatal.on = false; return; }
  lua_State *L = V->L;
  int top = lua_gettop(L);
  lua_getglobal(L, "viewer_errors");
  lua_rawgeti(L, LUA_REGISTRYINDEX, V->world);
  if (lua_pcall(L, 1, 3, 0) == 0) {
    int seq = (int)lua_tointeger(L, -3);
    if (seq != g_fatal.seq) {
      g_fatal.seq = seq;
      int n = lua_istable(L, -1) ? (int)objlen(L, -1) : 0;
      if (seq > 0 && (n > 0 || lua_isstring(L, -2))) {
        SDL_strlcpy(g_fatal.title, luaL_optstring(L, -2, "Error"), sizeof g_fatal.title);
        g_fatal.n = 0;
        for (int i = 1; i <= n && g_fatal.n < FATAL_MAX; i++) {
          lua_rawgeti(L, -1, i);
          int k = g_fatal.n++;
          lua_getfield(L, -1, "text"); SDL_strlcpy(g_fatal.text[k], luaL_optstring(L, -1, ""), sizeof g_fatal.text[0]); lua_pop(L, 1);
          lua_getfield(L, -1, "file"); SDL_strlcpy(g_fatal.file[k], luaL_optstring(L, -1, ""), sizeof g_fatal.file[0]); lua_pop(L, 1);
          lua_getfield(L, -1, "line"); g_fatal.line[k] = (int)luaL_optinteger(L, -1, 1); lua_pop(L, 1);
          lua_pop(L, 1);
        }
        fatal_show(V);
      }
    }
  }
  lua_settop(L, top);
  if (!g_fatal.on && !SDL_strncmp(V->err, "tick: ", 6) && SDL_strcmp(V->err, g_fatal.tick_err)) {   // (a tick that failed outright)
    SDL_strlcpy(g_fatal.tick_err, V->err, sizeof g_fatal.tick_err);
    SDL_strlcpy(g_fatal.title, "The game stopped: a tick failed", sizeof g_fatal.title);
    g_fatal.n = 1;
    SDL_strlcpy(g_fatal.text[0], V->err + 6, sizeof g_fatal.text[0]);
    g_fatal.file[0][0] = 0;                        // (file:line at its start: that)
    const char *c = SDL_strstr(g_fatal.text[0], ".lua:");
    if (c) {
      size_t fl = (size_t)(c - g_fatal.text[0]) + 4;
      if (fl < sizeof g_fatal.file[0]) { SDL_memcpy(g_fatal.file[0], g_fatal.text[0], fl); g_fatal.file[0][fl] = 0; g_fatal.line[0] = SDL_atoi(c + 5); }
    }
    fatal_show(V);
  }
}
static void fatal_open(Viewer *V, int i) {         // an error's line, in the editor (the editor shown)
  if (!editor_running() || !g_fatal.file[i][0]) return;
  editor_open_error(g_fatal.file[i], g_fatal.line[i] > 0 ? g_fatal.line[i] : 1, g_fatal.text[i]);
  if (V->fade >= 0.999f) { V->af.on = false; V->fade = V->blend; }   // (the game over all of it: the editor under it)
}
// modal: every input event is the overlay's (window events, quitting: not) -> consumed?
static bool fatal_event(Viewer *V, const SDL_Event *e, float mx, float my) {
  if (!g_fatal.on) return false;
  switch (e->type) {
  case SDL_EVENT_KEY_DOWN:
    if (!e->key.repeat && (e->key.key == SDLK_RETURN || e->key.key == SDLK_KP_ENTER || e->key.key == SDLK_ESCAPE || e->key.key == SDLK_SPACE))
      fatal_dismiss(V, true);
    return true;
  case SDL_EVENT_MOUSE_BUTTON_DOWN:
    if (e->button.button == SDL_BUTTON_LEFT) {
      if (in_rect(&g_fatal.btn, mx, my)) fatal_dismiss(V, true);
      else for (int i = 0; i < g_fatal.n; i++)
        if (g_fatal.file[i][0] && editor_running() && in_rect(&g_fatal.item[i], mx, my)) { fatal_open(V, i); fatal_dismiss(V, false); break; }
    }
    return true;
  case SDL_EVENT_KEY_UP: case SDL_EVENT_TEXT_INPUT: case SDL_EVENT_TEXT_EDITING:
  case SDL_EVENT_MOUSE_BUTTON_UP: case SDL_EVENT_MOUSE_WHEEL: case SDL_EVENT_MOUSE_MOTION:
  case SDL_EVENT_GAMEPAD_BUTTON_DOWN: case SDL_EVENT_GAMEPAD_BUTTON_UP: case SDL_EVENT_GAMEPAD_AXIS_MOTION:
  case SDL_EVENT_JOYSTICK_BUTTON_DOWN: case SDL_EVENT_JOYSTICK_BUTTON_UP: case SDL_EVENT_JOYSTICK_AXIS_MOTION:
  case SDL_EVENT_FINGER_DOWN: case SDL_EVENT_FINGER_UP: case SDL_EVENT_FINGER_MOTION:
  case SDL_EVENT_DROP_FILE:
    return true;
  default:
    return false;
  }
}
// a text cut into rows that fit `room` px (at most `max`; the last one cut with "..")
static int fatal_wrap(const char *s, float room, char rows[][400], int max) {
  int n = 0;
  char cur[400] = "";
  const char *p = s;
  while (*p && n < max) {
    const char *q = p;
    while (*q == ' ') q++;
    const char *e = q;
    while (*e && *e != ' ') e++;
    char word[400];
    size_t wl = (size_t)(e - q) < sizeof word - 1 ? (size_t)(e - q) : sizeof word - 1;
    SDL_memcpy(word, q, wl); word[wl] = 0;
    char next[800];
    SDL_snprintf(next, sizeof next, "%s%s%s", cur, cur[0] ? " " : "", word);
    if (cur[0] && ui_w(next) > room) {
      SDL_strlcpy(rows[n++], cur, 400);
      SDL_strlcpy(cur, word, sizeof cur);
    } else SDL_strlcpy(cur, next, sizeof cur);
    p = e;
  }
  if (n < max && cur[0]) SDL_strlcpy(rows[n++], cur, 400);
  else if (n == max && *p) { char f[400]; fit(f, sizeof f, rows[max - 1], room - ui_w("..")); SDL_snprintf(rows[max - 1], 400, "%s..", f); }
  return n;
}
static void fatal_draw(Viewer *V, int w, int h, SDL_FRect gv, float mx, float my) {
  if (!g_fatal.on) return;
  SDL_Renderer *r = V->ren;
  (void)h;
  SDL_SetRenderDrawBlendMode(r, SDL_BLENDMODE_BLEND);
  SDL_SetRenderClipRect(r, NULL);
  SDL_SetRenderDrawColor(r, 0, 0, 0, 150);         // (the game, under it: dimmed)
  SDL_RenderFillRect(r, &gv);
  float row = (float)TAB_ROW + 3, pad = 14;
  float bw = gv.w - 40 < 720 ? gv.w - 40 : 720;
  if (bw < 260) bw = gv.w - 8 > 260 ? 260 : gv.w - 8;
  float room = bw - 2 * pad;
  char rows[FATAL_MAX][4][400];                    // (each item: up to 3 rows of its text, then where it is)
  int nr[FATAL_MAX];
  float bh = pad + row + 10;                       // (the title)
  for (int i = 0; i < g_fatal.n; i++) {
    nr[i] = fatal_wrap(g_fatal.text[i], room, rows[i], 3);
    if (g_fatal.file[i][0]) {
      const char *base = g_fatal.file[i];
      for (const char *c = base; *c; c++) if (*c == '/' || *c == '\\') base = c + 1;
      SDL_snprintf(rows[i][nr[i]++], 400, "\t%s:%d%s", base, g_fatal.line[i], editor_running() ? "   (click: open it)" : "");
    }
    bh += nr[i] * row + 8;
  }
  bh += row + pad + 6;                             // (the button)
  float x = SDL_floorf(gv.x + (gv.w - bw) / 2), y = SDL_floorf(gv.y + (gv.h - bh) / 3);
  if (y < gv.y + 8) y = gv.y + 8;
  if (x < 4) x = 4;
  if (x + bw > w - 4) bw = w - 4 - x;
  SDL_FRect box = { x, y, bw, bh };
  SDL_SetRenderDrawColor(r, 22, 14, 16, 248);
  SDL_RenderFillRect(r, &box);
  SDL_FRect bar = { x, y, bw, 4 };
  SDL_SetRenderDrawColor(r, 220, 70, 60, 255);
  SDL_RenderFillRect(r, &bar);
  SDL_RenderRect(r, &box);
  float ty = y + pad - 2;
  SDL_SetRenderDrawColor(r, 255, 120, 100, 255);
  char t[300];
  fit(t, sizeof t, g_fatal.title, room);
  ui_text_in(r, x + pad, ty, row, t);
  ty += row + 10;
  g_fatal.hot = -1;
  for (int i = 0; i < g_fatal.n; i++) {
    SDL_FRect it = { x + 6, ty - 3, bw - 12, nr[i] * row + 4 };
    g_fatal.item[i] = it;
    bool hot = g_fatal.file[i][0] && editor_running() && in_rect(&it, mx, my);
    if (hot) { g_fatal.hot = i; SDL_SetRenderDrawColor(r, 60, 36, 40, 255); SDL_RenderFillRect(r, &it); }
    for (int k = 0; k < nr[i]; k++) {
      bool dim = rows[i][k][0] == '\t';
      if (dim) SDL_SetRenderDrawColor(r, 150, 140, 145, 255); else SDL_SetRenderDrawColor(r, 238, 232, 232, 255);
      ui_text_in(r, x + pad, ty + k * row, row, dim ? rows[i][k] + 1 : rows[i][k]);
    }
    ty += nr[i] * row + 8;
  }
  const char *label = "Continue   (Enter, ESC)";
  float lw = SDL_ceilf(ui_w(label)) + 20;
  g_fatal.btn = (SDL_FRect){ x + bw - pad - lw, ty + 2, lw, row + 2 };
  bool bh_hot = in_rect(&g_fatal.btn, mx, my);
  if (bh_hot) g_fatal.hot = FATAL_MAX;
  SDL_SetRenderDrawColor(r, bh_hot ? 200 : 150, 60, 52, 255);
  SDL_RenderFillRect(r, &g_fatal.btn);
  SDL_SetRenderDrawColor(r, 255, 245, 240, 255);
  ui_text_in(r, g_fatal.btn.x + 10, g_fatal.btn.y + 1, row, label);
}
