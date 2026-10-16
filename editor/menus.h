// editor/menus.h - the popup menus, drawn by lite (one look, one code path).
// Part of replay.c: included once, after bar.h and tab.h.
//
// replay.c draws the tree, the properties and the bar; their popups are
// lite's (plugins/hostmenu.lua over plugins/contextmenu.lua and
// plugins/canvas/menu.lua): a search box, submenus, a scroll bar when they
// don't fit the window, the keyboard. A menu goes to lite as text (a line an
// item: depth \t kind \t text \t info \t flags, see hostmenu.lua); what was
// picked comes back through host_call("pick <id> <path>"), path "3" or "1.2"
// (separators don't count). This file builds each one and does what it says:
//   main    the bar's ☰: the plugins' categories >, Editor > (Log window, Confirm close, Theme >,
//           Thumbnails >, FPS > (focused, unfocused, minimized)), Help, Reset
//   net     RMB on the Network button: Ghosts, Send rate >, P1..P4 line >
//   lobby   RMB on P2-P4 (online, stopped): the hosts nearby (players.lua)
//   pick    a property's drop-down, the tree's right-click menu (tab.h: pick)
// While one is open lite has the mouse and the keys (replay.c: overlays).

static Viewer *g_mv;                               // (set by main: host_call has no arguments for it)
static SDL_Window *g_mwin;

// the text being built
static char g_mt[262144];                         // (the main menu: every plugin's menu, the Text editor's commands)
static size_t g_mtn;
static void mt_begin(void) { g_mtn = 0; g_mt[0] = 0; }
static void mt_add(int depth, char kind, const char *text, const char *info, const char *flags) {
  char clean[200], cinfo[64];
  SDL_strlcpy(clean, text ? text : "", sizeof clean);
  SDL_strlcpy(cinfo, info ? info : "", sizeof cinfo);
  for (char *c = clean; *c; c++) if (*c == '\t' || *c == '\n') *c = ' ';
  for (char *c = cinfo; *c; c++) if (*c == '\t' || *c == '\n') *c = ' ';
  int n = SDL_snprintf(g_mt + g_mtn, sizeof g_mt - g_mtn, "%d\t%c\t%s\t%s\t%s\n", depth, kind, clean, cinfo, flags ? flags : "");
  if (n > 0 && g_mtn + (size_t)n < sizeof g_mt) g_mtn += (size_t)n;
}
static void mt_sep(int depth) { mt_add(depth, 's', "", "", ""); }
static int path_at(const char *path, int k) {      // the k-th number of "3.1.2" (0-based), 0: none
  for (int i = 0; i < k && path; i++) { path = SDL_strchr(path, '.'); if (path) path++; }
  return path ? SDL_atoi(path) : 0;
}

// --- the main menu ---------------------------------------------------------
static const int FPS_FOCUS[] = { 0, 12, 18, 24, 30, 36, 48, 60, 72, 90, 120, 144, 180, 240 };
static const int FPS_BACK[] = { 0, 1, 2, 5, 10, 15, 30, 60 };
static const int THUMBS[] = { 0, 16, 24, 32, 40, 48, 56, 64, 72, 80 };
static struct { int ncat, cat_first[PTABS_MAX], cat_n[PTABS_MAX]; } g_mainm;   // per category: its plugins (g_ptabs, in order)
static void pmenu_line(char kind, int depth, const char *text, const char *info, const char *flags) {   // (a plugin's menu line: two deeper, under <category> > <plugin> >)
  if (kind == '-') mt_sep(2 + depth);
  else mt_add(2 + depth, 'i', text, info, flags);
}
static void fps_name(int list, int v, char *out, size_t n) {   // list 0: focused, 1: unfocused / minimized
  if (v == 0 && list == 0) SDL_snprintf(out, n, g_monitor_hz > 0 ? "monitor (%g)" : "monitor", g_monitor_hz);
  else if (v == 0) SDL_snprintf(out, n, "as focused");
  else SDL_snprintf(out, n, "%d", v);
}
static void main_menu_open(Viewer *V, float x, float y) {
  (void)V;
  burger_labels();
  ptabs_refresh();
  mt_begin();
  char v[64];
  // the plugins' categories first (Audio > the sfxr editor > its items), then
  // Editor > (its settings), Help, Reset editor
  if (g_ptabs.n == 0) mt_add(0, 'i', "(no plugin opens a tab of its own)", "", "d");
  g_mainm.ncat = 0;
  for (int i = 0; i < g_ptabs.n; i++) {            // (lite sorts them by category)
    if (i == 0 || SDL_strcmp(g_ptabs.cat[i], g_ptabs.cat[i - 1])) {
      g_mainm.cat_first[g_mainm.ncat] = i; g_mainm.cat_n[g_mainm.ncat] = 0; g_mainm.ncat++;
      bool here = false;                           // (the category of the plugin in view: tinted, like the ☰ while it's open)
      for (int j = i; j < g_ptabs.n && !SDL_strcmp(g_ptabs.cat[j], g_ptabs.cat[i]); j++) if (g_ptabs.active[j]) here = true;
      mt_add(0, 'i', g_ptabs.cat[i], "", here ? "a" : "");
    }
    g_mainm.cat_n[g_mainm.ncat - 1]++;
    mt_add(1, 'i', g_ptabs.title[i], "", g_ptabs.active[i] ? "a" : "");   // (the plugin in view: tinted)
    pmenu_each(i, pmenu_line);
  }
  mt_add(0, 'i', "Editor", "", "");
  mt_add(1, 'i', "Log window", "", V->logwin ? "c" : "");
  mt_add(1, 'i', "Confirm close", "", settings_confirm_close() ? "c" : "");
  mt_add(1, 'i', "Theme", settings_light() ? "light" : "dark", "");
  mt_add(2, 'i', "dark", "", settings_light() ? "" : "c");
  mt_add(2, 'i', "light", "", settings_light() ? "c" : "");
  burger_value(BURGER_THUMBS, v, sizeof v);
  mt_add(1, 'i', "Thumbnails", v, "");
  for (int i = 0; i < (int)SDL_arraysize(THUMBS); i++) {
    char t[32];
    if (THUMBS[i]) SDL_snprintf(t, sizeof t, "%d px", THUMBS[i]); else SDL_strlcpy(t, "off", sizeof t);
    mt_add(2, 'i', t, "", settings_thumbs() == THUMBS[i] ? "c" : "");
  }
  mt_sep(1);
  static const char *fps_items[3] = { "FPS", "FPS unfocused", "FPS minimized" };
  static const int fps_ids[3] = { BURGER_FPS, BURGER_FPS_BG, BURGER_FPS_MIN };
  for (int f = 0; f < 3; f++) {
    burger_value(fps_ids[f], v, sizeof v);
    mt_add(1, 'i', fps_items[f], v, "");
    int cur = f == 0 ? settings_fps() : f == 1 ? settings_fps_unfocused() : settings_fps_minimized();
    const int *l = f == 0 ? FPS_FOCUS : FPS_BACK;
    int n = f == 0 ? (int)SDL_arraysize(FPS_FOCUS) : (int)SDL_arraysize(FPS_BACK);
    for (int i = 0; i < n; i++) {
      char t[48];
      fps_name(f == 0 ? 0 : 1, l[i], t, sizeof t);
      mt_add(2, 'i', t, "", cur == l[i] ? "c" : "");
    }
  }
  mt_sep(0);
  mt_add(0, 'i', burger_text[BURGER_HELP], "F1", "");
  mt_add(0, 'i', "Reset editor...", "", "");
  burger.open = editor_menu("main", x, y, -1, g_mt, true);   // (the ☰ button lit while it's open)
}
static void main_menu_pick(Viewer *V, const char *path) {
  int a = path_at(path, 0), b = path_at(path, 1), c = path_at(path, 2);
  int ncat = g_ptabs.n == 0 ? 1 : g_mainm.ncat;   // (none: one dim line in their place)
  if (a >= 1 && a <= g_mainm.ncat && g_ptabs.n > 0) {   // <category> > <plugin> > <item>
    if (b >= 1 && b <= g_mainm.cat_n[a - 1] && c >= 1) {
      int i = g_mainm.cat_first[a - 1] + b - 1;
      const char *rest = SDL_strchr(path, '.');     // (its item's path in its menu: "3", "4.2.1")
      rest = rest ? SDL_strchr(rest + 1, '.') : NULL;
      char lua[300];
      if (rest && strspn(rest + 1, "0123456789.") == SDL_strlen(rest + 1)) {
        SDL_snprintf(lua, sizeof lua, "require('plugins.projectplugins').run_menu_path('%s', '%s')", g_ptabs.name[i], rest + 1);
        editor_exec(lua);
      }
    }
    return;
  }
  if (a == ncat + 2) { g_want_help = true; return; }
  if (a == ncat + 3) { g_want_reset = true; return; }
  if (a != ncat + 1) return;
  switch (b) {                                     // Editor > ...
  case 1:                                          // Log window
    V->logwin = !V->logwin;
    editor_set_log(V->logwin);
    g_settings.log_window = V->logwin ? 1 : 0;
    break;
  case 2:                                          // Confirm close
    g_settings.confirm_close = settings_confirm_close() ? 0 : 1;
    editor_exec(settings_confirm_close() ? "require('core.config').confirm_close_unsaved = true"
                                         : "require('core.config').confirm_close_unsaved = false");
    break;
  case 3:                                          // Theme > dark / light
    if (c >= 1 && c <= 2) { g_settings.theme = c - 1; settings_apply_theme(); }
    break;
  case 4:                                          // Thumbnails > ...
    if (c >= 1 && c <= (int)SDL_arraysize(THUMBS)) g_settings.thumbs = THUMBS[c - 1];
    break;
  case 5:                                          // FPS > ...
    if (c >= 1 && c <= (int)SDL_arraysize(FPS_FOCUS)) { g_settings.fps = FPS_FOCUS[c - 1]; update_fps_limit(g_mwin); }
    break;
  case 6:
    if (c >= 1 && c <= (int)SDL_arraysize(FPS_BACK)) g_settings.fps_unfocused = FPS_BACK[c - 1];
    break;
  case 7:
    if (c >= 1 && c <= (int)SDL_arraysize(FPS_BACK)) g_settings.fps_minimized = FPS_BACK[c - 1];
    break;
  default: return;
  }
  if (!settings_save()) SDL_snprintf(V->err, sizeof V->err, "can't write %s", g_settings_path);
}

// --- the Network menu ------------------------------------------------------
static const int NET_RATES[] = { 5, 10, 15, 20, 30, 60 };
static const int NET_LINKS[] = { -1, 4, 3, 2, 1, 0, 5 };   // as everyone's, local .. awful, cut
static const char *net_link_name(int v) {
  static const char *names[] = { "awful", "bad", "fair", "good", "local", "cut" };
  return v < 0 ? "as all" : names[v];
}
static void net_menu_open(Viewer *V, float x, float y, float above) {
  (void)V;
  mt_begin();
  char v[32];
  mt_add(0, 'i', "Ghosts", "", g_net_ghosts ? "c" : "");
  SDL_snprintf(v, sizeof v, "%d/s", g_net_rate);
  mt_add(0, 'i', "Send rate", v, "");
  for (int i = 0; i < (int)SDL_arraysize(NET_RATES); i++) {
    char t[16];
    SDL_snprintf(t, sizeof t, "%d/s", NET_RATES[i]);
    mt_add(1, 'i', t, "", g_net_rate == NET_RATES[i] ? "c" : "");
  }
  mt_sep(0);
  for (int k = 1; k <= 4; k++) {
    char t[16];
    SDL_snprintf(t, sizeof t, "P%d line", k);
    mt_add(0, 'i', t, net_link_name(g_net_link[k - 1]), "");
    for (int i = 0; i < (int)SDL_arraysize(NET_LINKS); i++) mt_add(1, 'i', net_link_name(NET_LINKS[i]), "", g_net_link[k - 1] == NET_LINKS[i] ? "c" : "");
  }
  editor_menu("net", x, y, above, g_mt, false);
}
static void net_menu_pick(Viewer *V, const char *path) {
  int a = path_at(path, 0), b = path_at(path, 1);
  if (a == 1) players_set_ghosts(V, !g_net_ghosts);
  else if (a == 2 && b >= 1 && b <= (int)SDL_arraysize(NET_RATES)) players_set_rate(V, NET_RATES[b - 1]);
  else if (a >= 3 && a <= 6 && b >= 1 && b <= (int)SDL_arraysize(NET_LINKS)) players_set_link(V, a - 2, NET_LINKS[b - 1]);
}

// --- the lobby menu (runtime/players.lua: viewer_lobby_items / viewer_lobby_pick)
static struct { bool open, scanning, reopening; int seat; float x, y, above; int line_of[64], n; } g_lobm;
static void lobby_menu_show(Viewer *V) {
  if (V->world == LUA_NOREF) return;
  int top = lua_gettop(V->L);
  lua_getglobal(V->L, "viewer_lobby_items");
  const char *t = lua_pcall(V->L, 0, 1, 0) == 0 && lua_isstring(V->L, -1) ? lua_tostring(V->L, -1) : "";
  mt_begin();
  g_lobm.n = 0;
  int line = 0;
  for (const char *p = t; ; line++) {
    const char *e = SDL_strchr(p, '\n');
    char l[200];
    size_t len = e ? (size_t)(e - p) : SDL_strlen(p);
    if (len >= sizeof l) len = sizeof l - 1;
    SDL_memcpy(l, p, len); l[len] = 0;
    if (!len) mt_sep(0);
    else {
      mt_add(0, 'i', l, "", l[0] == '(' ? "d" : "");
      if (g_lobm.n < 64) g_lobm.line_of[g_lobm.n++] = line + 1;
    }
    if (!e) break;
    p = e + 1;
  }
  lua_settop(V->L, top);
  lua_getglobal(V->L, "viewer_lobby");
  g_lobm.scanning = lua_pcall(V->L, 0, 2, 0) == 0 && lua_toboolean(V->L, -1);
  lua_settop(V->L, top);
  g_lobm.reopening = g_lobm.open;
  g_lobm.open = editor_menu("lobby", g_lobm.x, g_lobm.y, g_lobm.above, g_mt, false);
  g_lobm.reopening = false;
}
static void lobby_menu_open(Viewer *V, int seat, float x, float y, float above) {
  g_lobm.seat = seat; g_lobm.x = x; g_lobm.y = y; g_lobm.above = above;
  viewer_call(V, "viewer_lobby_scan", 0);          // (looking now: the list fills in when it's done)
  lobby_menu_show(V);
}
static void lobby_menu_poll(Viewer *V) {           // (every frame) a scan done while it's open: shown again with the hosts
  if (!g_lobm.open || !g_lobm.scanning || V->world == LUA_NOREF) return;
  int top = lua_gettop(V->L);
  lua_getglobal(V->L, "viewer_lobby");
  bool scanning = lua_pcall(V->L, 0, 2, 0) == 0 && lua_toboolean(V->L, -1);
  lua_settop(V->L, top);
  if (!scanning) lobby_menu_show(V);
}
static void lobby_menu_pick(Viewer *V, const char *path) {
  int a = path_at(path, 0);
  if (a < 1 || a > g_lobm.n || V->world == LUA_NOREF) return;
  int line = g_lobm.line_of[a - 1];
  int top = lua_gettop(V->L);
  lua_getglobal(V->L, "viewer_lobby_pick");
  lua_rawgeti(V->L, LUA_REGISTRYINDEX, V->world);
  lua_pushinteger(V->L, line);
  lua_pushinteger(V->L, g_lobm.seat);
  if (lua_pcall(V->L, 3, 2, 0) != 0) SDL_snprintf(V->err, sizeof V->err, "online: %s", lua_tostring(V->L, -1));
  else {
    if (lua_toboolean(V->L, -2)) g_want_join = true;
    if (lua_isstring(V->L, -1)) SDL_snprintf(V->err, sizeof V->err, "online: %s", lua_tostring(V->L, -1));
  }
  lua_settop(V->L, top);
  bool again = SDL_strstr(path, ".") == NULL && a == g_lobm.n;   // (Look again: scans, shown again)
  if (again) lobby_menu_open(V, g_lobm.seat, g_lobm.x, g_lobm.y, g_lobm.above);
}

// lite's answers while it types the prompt (plugins/textproxy.lua: lite_prompt)
static void prompt_host(Viewer *V, const char *what) {
  char t[512];
  int cur, a, b;
  bool caret;
  if (!strcmp(what, "blurred")) { con.focus = false; con_lite = false; con_drag = false; return; }   // (lite gave the keyboard to another box)
  if (editor_prompt_get(t, sizeof t, &cur, &a, &b, &caret)) le_set(&con.e, t);
  con.blink = SDL_GetTicks();
  if (!strcmp(what, "run")) { con_run(V); editor_prompt("set", "", -1, 0, 0); }
  else if (!strcmp(what, "leave")) con_focus(g_mwin, false, g_edfocus_p ? *g_edfocus_p : false);
  else if (!strcmp(what, "older")) { if (con.hpos > 0) { le_set(&con.e, con.hist[--con.hpos]); editor_prompt("set", con.e.s, -1, 0, 0); } }
  else if (!strcmp(what, "newer")) {
    if (con.hpos < con.nhist - 1) le_set(&con.e, con.hist[++con.hpos]);
    else { con.hpos = con.nhist; le_set(&con.e, ""); }
    editor_prompt("set", con.e.s, -1, 0, 0);
  }
  else if (!strcmp(what, "clear")) con.out[0] = 0;
  else if (!strcmp(what, "copy")) SDL_SetClipboardText(con.e.len ? con.e.s : con.out);
}

// lite's answers (editor_set_host_call)
static const char *host_call(const char *cmd) {
  Viewer *V = g_mv;
  if (!V || !cmd) return NULL;
  char id[16] = "", path[64] = "";
  if (!SDL_strncmp(cmd, "text_settings ", 14)) { settings_set_text(cmd + 14); return "ok"; }   // (plugins/textmenu.lua: lite's settings, kept)
  if (SDL_sscanf(cmd, "pick %15s %63s", id, path) == 2) {
    if (!SDL_strcmp(id, "main")) { burger.open = false; main_menu_pick(V, path); }
    else if (!SDL_strcmp(id, "net")) net_menu_pick(V, path);
    else if (!SDL_strcmp(id, "lobby")) lobby_menu_pick(V, path);
    return "ok";
  }
  if (!SDL_strcmp(cmd, "typing on") || !SDL_strcmp(cmd, "typing off")) {   // a text box of lite's types (plugins/textproxy.lua): the keyboard is lite's
    g_side_focus = cmd[8] == 'n';                 // ("typing on" / "typing off")
    if (g_mwin) { if (g_side_focus) SDL_StartTextInput(g_mwin); else if (g_edfocus_p && !*g_edfocus_p) SDL_StopTextInput(g_mwin); }
    return "ok";
  }
  if (!SDL_strncmp(cmd, "prompt ", 7)) { prompt_host(V, cmd + 7); return "ok"; }   // the bar's Lua prompt (bar.h)
  if (SDL_sscanf(cmd, "closed %15s", id) == 1) {
    if (!SDL_strcmp(id, "lobby") && !g_lobm.reopening) g_lobm.open = false;
    if (!SDL_strcmp(id, "main")) burger.open = false;
    return "ok";
  }
  return NULL;
}
