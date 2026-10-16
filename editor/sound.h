// editor/sound.h - the game's audio: a small mixer on SDL3's audio streams.
// Part of replay.c: included once, in order, from there (one compilation unit).
//
// Sounds (one-shots or loops): sixteen voices, each an SDL_AudioStream bound to
// one device (SDL mixes them). A clip is a file decoded once (again when it
// changes on disk): .wav (dr_wav), .ogg (stb_vorbis), .mp3 (dr_mp3), .flac
// (dr_flac), all to 16-bit; or PCM the game made (.sfx: runtime/sfxr.lua).
// Per sound: volume, pan (-1 left .. 1 right: the other side turned down),
// pitch (a speed ratio: 2 an octave up, and faster), loop, and a bus.
// Music: streamed from the file (decoded as it plays), looping, with a
// crossfade between tracks. Buses: sfx, music, voice (each a volume, under
// the master volume: the toolbar's speaker, audio_set_volume).
//
//   host_sound(pcm [, rate, volume, pan, pitch, bus, loop]) -> id | nil, err   (16-bit mono pcm)
//   host_sound_file(path [, volume, pan, pitch, bus, loop]) -> id | nil, err
//   host_sound_set(id, volume [, pitch]) -> playing?   host_sound_kill(id)   host_sound_stop() (all)
//   host_music(path | nil [, volume, fade, loop]) -> true | nil, err   (nil: stop, fading out)
//   host_bus(name [, volume]) -> its volume   ("sfx", "music", "voice")
//   host_audio_info(path) -> seconds, channels, rate | nil, err
// runtime/sound.lua gives the game w:sound, w:music, w:bus. Files are read
// with SDL_LoadFile (UTF-8 paths everywhere) and decoded from memory. The
// device pauses with the game (audio_update) and Stop silences it all.
#define DR_WAV_IMPLEMENTATION
#define DR_FLAC_IMPLEMENTATION
#define DR_MP3_IMPLEMENTATION
#define DR_WAV_NO_STDIO
#define DR_FLAC_NO_STDIO
#define DR_MP3_NO_STDIO
#include "3rd/audio/dr_wav.h"
#include "3rd/audio/dr_flac.h"
#include "3rd/audio/dr_mp3.h"
#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_NO_PUSHDATA_API
#define error stbv_error                           // (one compilation unit: minilua has an `error` too)
#include "3rd/audio/stb_vorbis.c"
#undef error
#undef L
#undef C
#undef R

#define SND_VOICES 16
enum { BUS_SFX, BUS_MUSIC, BUS_VOICE, BUS_N };
static const char *BUS_NAME[BUS_N] = { "sfx", "music", "voice" };
static float snd_bus[BUS_N] = { 1, 1, 1 };
static SDL_AudioDeviceID snd_dev;
typedef struct {
  SDL_AudioStream *s;
  Uint32 id;                                       // (0: free)
  int bus;
  float vol;
  bool loop;
  Uint8 *loop_pcm; int loop_bytes;                 // (a loop: its own copy, put again as it runs low)
} Voice;
static Voice snd_voice[SND_VOICES];
static Uint32 snd_next_id = 1;
static float snd_master = 1;                       // the toolbar's volume (0..1): every sound, the game's and the editor's
static float audio_volume(void) { return snd_master; }
static void audio_set_volume(float v) {
  v = v < 0 ? 0 : v > 1 ? 1 : v;
  snd_master = v;
  if (snd_dev) SDL_SetAudioDeviceGain(snd_dev, v);
  editor_set_volume(v);                            // (lite's previews: the sfxr editor...)
}

static bool snd_open(void) {
  if (snd_dev) return true;
  if (!SDL_WasInit(SDL_INIT_AUDIO) && !SDL_InitSubSystem(SDL_INIT_AUDIO)) return false;
  snd_dev = SDL_OpenAudioDevice(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, NULL);
  if (!snd_dev) return false;
  SDL_SetAudioDeviceGain(snd_dev, snd_master);
  SDL_AudioSpec spec = { SDL_AUDIO_S16LE, 2, 44100 };
  for (int i = 0; i < SND_VOICES; i++) {
    snd_voice[i].s = SDL_CreateAudioStream(&spec, NULL);
    if (!snd_voice[i].s || !SDL_BindAudioStream(snd_dev, snd_voice[i].s)) return false;
  }
  return true;
}

// --- clips: files decoded once -------------------------------------------------
#define SND_CLIPS 64
typedef struct { char path[600]; SDL_Time mtime; Uint64 size; int channels, rate; Sint16 *pcm; Uint64 frames, used; } Clip;
static Clip snd_clip[SND_CLIPS];
static Uint64 snd_tick;
static bool ext_is(const char *path, const char *ext) {
  size_t n = SDL_strlen(path), e = SDL_strlen(ext);
  return n >= e && !SDL_strcasecmp(path + n - e, ext);
}
// an ID3v2 tag in front (tools add them to .flac / .wav / .ogg too): skipped
static size_t id3_skip(const void *data, size_t size) {
  const Uint8 *b = data;
  size_t at = 0;
  while (size - at >= 10 && b[at] == 'I' && b[at + 1] == 'D' && b[at + 2] == '3') {
    size_t n = ((size_t)(b[at + 6] & 0x7f) << 21) | ((size_t)(b[at + 7] & 0x7f) << 14) | ((size_t)(b[at + 8] & 0x7f) << 7) | (b[at + 9] & 0x7f);
    n += 10 + ((b[at + 5] & 0x10) ? 10 : 0);       // (its header, and a footer when it says so)
    if (n > size - at) break;
    at += n;
  }
  return at;
}
// a whole file (in memory) -> 16-bit interleaved pcm (SDL_free it), channels, rate, frames
static Sint16 *snd_decode(const void *data, size_t size, const char *path, int *ch, int *rate, Uint64 *frames, const char **err) {
  unsigned int c = 0, r = 0;
  size_t skip = id3_skip(data, size);
  data = (const Uint8 *)data + skip; size -= skip;
  Sint16 *tmp = NULL;
  *frames = 0;
  if (ext_is(path, ".wav")) {
    drwav_uint64 n = 0;
    tmp = drwav_open_memory_and_read_pcm_frames_s16(data, size, &c, &r, &n, NULL); *frames = n;
  } else if (ext_is(path, ".flac")) {
    drflac_uint64 n = 0;
    tmp = drflac_open_memory_and_read_pcm_frames_s16(data, size, &c, &r, &n, NULL); *frames = n;
  } else if (ext_is(path, ".mp3")) {
    drmp3_config cf = { 0 }; drmp3_uint64 n = 0;
    tmp = drmp3_open_memory_and_read_pcm_frames_s16(data, size, &cf, &n, NULL); *frames = n; c = cf.channels; r = cf.sampleRate;
  } else if (ext_is(path, ".ogg")) {
    int ci = 0, ri = 0; short *o = NULL;
    int n = stb_vorbis_decode_memory((const unsigned char *)data, (int)size, &ci, &ri, &o);
    if (n > 0) { tmp = o; c = (unsigned)ci; r = (unsigned)ri; *frames = (Uint64)n; } else if (o) free(o);
  } else { *err = "not a sound file (.wav, .ogg, .mp3, .flac)"; return NULL; }
  if (!tmp || !c || !r) { *err = "can't decode it"; if (tmp) free(tmp); return NULL; }
  size_t bytes = (size_t)*frames * c * 2;
  Sint16 *out = SDL_malloc(bytes ? bytes : 2);
  if (out && bytes) SDL_memcpy(out, tmp, bytes);
  free(tmp);                                       // (the decoders' default allocator: malloc)
  *ch = (int)c; *rate = (int)r;
  return out;
}
static Clip *snd_clip_get(const char *path, const char **err) {
  SDL_PathInfo pi;
  if (!SDL_GetPathInfo(path, &pi)) { *err = "no such file"; return NULL; }
  Clip *slot = NULL, *old = &snd_clip[0];
  for (int i = 0; i < SND_CLIPS; i++) {
    Clip *c = &snd_clip[i];
    if (c->pcm && !SDL_strcmp(c->path, path)) {
      if (c->mtime == pi.modify_time && c->size == pi.size) { c->used = ++snd_tick; return c; }
      slot = c;                                    // (changed on disk: decoded again)
      break;
    }
    if (!c->pcm && !slot) slot = c;
    if (c->used < old->used) old = c;
  }
  Clip *c = slot ? slot : old;                     // (all taken: the one used longest ago goes)
  if (c->pcm) { SDL_free(c->pcm); c->pcm = NULL; }
  size_t size = 0;
  void *data = SDL_LoadFile(path, &size);
  if (!data) { *err = SDL_GetError(); return NULL; }
  Sint16 *pcm = snd_decode(data, size, path, &c->channels, &c->rate, &c->frames, err);
  SDL_free(data);
  if (!pcm) return NULL;
  SDL_strlcpy(c->path, path, sizeof c->path);
  c->pcm = pcm; c->mtime = pi.modify_time; c->size = pi.size; c->used = ++snd_tick;
  return c;
}

// --- voices --------------------------------------------------------------------
static int bus_of(const char *name) {
  for (int i = 0; i < BUS_N; i++) if (name && !SDL_strcmp(name, BUS_NAME[i])) return i;
  return BUS_SFX;
}
static void SDLCALL snd_loop_cb(void *ud, SDL_AudioStream *s, int additional, int total) {   // (the audio thread: a loop runs low)
  (void)total;
  Voice *v = ud;
  if (!v->loop || !v->loop_pcm || v->loop_bytes <= 0) return;
  while (additional > 0) { SDL_PutAudioStreamData(s, v->loop_pcm, v->loop_bytes); additional -= v->loop_bytes; }
}
static void voice_free(Voice *v) {
  if (!v->s) return;
  SDL_LockAudioStream(v->s);
  SDL_SetAudioStreamGetCallback(v->s, NULL, NULL);
  SDL_ClearAudioStream(v->s);
  v->loop = false;
  SDL_free(v->loop_pcm); v->loop_pcm = NULL; v->loop_bytes = 0;
  v->id = 0;
  SDL_UnlockAudioStream(v->s);
}
static Voice *voice_take(void) {                   // a free voice, else the one with the least left (loops last)
  Voice *best = NULL; Sint64 least = 0x7fffffffffffLL;
  for (int i = 0; i < SND_VOICES; i++) {
    Voice *v = &snd_voice[i];
    if (!v->id || (!v->loop && SDL_GetAudioStreamQueued(v->s) == 0)) { best = v; break; }
    Sint64 q = v->loop ? 0x7ffffffffffLL : SDL_GetAudioStreamQueued(v->s);
    if (q < least) { least = q; best = v; }
  }
  if (best) voice_free(best);
  return best;
}
// play 16-bit pcm of ch channels on a voice -> its id (0: none)
static Uint32 snd_play(const Sint16 *pcm, Uint64 frames, int ch, int rate, float vol, float pan, float pitch, int bus, bool loop) {
  if (!snd_open() || frames == 0 || rate <= 0) return 0;
  Voice *v = voice_take();
  if (!v) return 0;
  pan = pan < -1 ? -1 : pan > 1 ? 1 : pan;
  size_t bytes = (size_t)frames * 4;               // (always stereo: the pan baked in)
  Sint16 *st = SDL_malloc(bytes);
  if (!st) return 0;
  float gl = pan > 0 ? 1 - pan : 1, gr = pan < 0 ? 1 + pan : 1;
  for (Uint64 i = 0; i < frames; i++) {
    int l = pcm[i * ch], r = ch > 1 ? pcm[i * ch + 1] : l;
    st[i * 2] = (Sint16)(l * gl); st[i * 2 + 1] = (Sint16)(r * gr);
  }
  SDL_AudioSpec spec = { SDL_AUDIO_S16LE, 2, rate };
  SDL_LockAudioStream(v->s);
  SDL_SetAudioStreamFormat(v->s, &spec, NULL);
  SDL_SetAudioStreamFrequencyRatio(v->s, pitch < 0.05f ? 0.05f : pitch > 8 ? 8 : pitch);
  v->bus = bus; v->vol = vol < 0 ? 0 : vol;
  SDL_SetAudioStreamGain(v->s, v->vol * snd_bus[bus]);
  SDL_PutAudioStreamData(v->s, st, (int)bytes);
  if (loop) { v->loop = true; v->loop_pcm = (Uint8 *)st; v->loop_bytes = (int)bytes; SDL_SetAudioStreamGetCallback(v->s, snd_loop_cb, v); }
  else SDL_free(st);
  v->id = snd_next_id++;
  if (!snd_next_id) snd_next_id = 1;
  SDL_UnlockAudioStream(v->s);
  return v->id;
}
static Voice *voice_of(Uint32 id) {
  for (int i = 0; i < SND_VOICES; i++) if (id && snd_voice[i].id == id) return &snd_voice[i];
  return NULL;
}

// --- music: streamed, decoded as it plays --------------------------------------
typedef struct {
  SDL_AudioStream *s;
  int kind;                                        // 0 none, 1 wav, 2 flac, 3 mp3, 4 ogg
  void *data;                                      // (the file, in memory: the decoder reads it)
  drwav wav; drflac *flac; drmp3 mp3; stb_vorbis *ogg;   // (never moved: the decoders point at themselves)
  int ch, rate;
  bool loop, ended;
  float vol, gain, target, rate_per_s;             // (gain: the fade, toward target at rate_per_s)
  char path[600];
} Music;
static Music snd_music[2];                         // (the one playing, the one fading out)
static int snd_cur;                                // (which is the one playing)
static void SDLCALL music_cb(void *ud, SDL_AudioStream *s, int additional, int total) {   // (the audio thread: decode what it needs)
  (void)total;
  Music *m = ud;
  Sint16 buf[4096];
  while (additional > 0 && m->kind && !m->ended) {
    int fr = (int)(sizeof buf / 2 / m->ch);
    Uint64 got = 0;
    if (m->kind == 1) got = drwav_read_pcm_frames_s16(&m->wav, fr, buf);
    else if (m->kind == 2) got = drflac_read_pcm_frames_s16(m->flac, fr, buf);
    else if (m->kind == 3) got = drmp3_read_pcm_frames_s16(&m->mp3, fr, buf);
    else if (m->kind == 4) got = (Uint64)stb_vorbis_get_samples_short_interleaved(m->ogg, m->ch, buf, fr * m->ch);
    if (got == 0) {                                // the end: again from the start, or done
      if (!m->loop) { m->ended = true; break; }
      bool ok = m->kind == 1 ? drwav_seek_to_pcm_frame(&m->wav, 0) : m->kind == 2 ? drflac_seek_to_pcm_frame(m->flac, 0)
              : m->kind == 3 ? drmp3_seek_to_pcm_frame(&m->mp3, 0) : stb_vorbis_seek_start(m->ogg) != 0;
      if (!ok) { m->ended = true; break; }
      continue;
    }
    int bytes = (int)(got * m->ch * 2);
    SDL_PutAudioStreamData(s, buf, bytes);
    additional -= bytes;
  }
}
static void music_close(Music *m) {
  if (m->s) { SDL_LockAudioStream(m->s); SDL_SetAudioStreamGetCallback(m->s, NULL, NULL); SDL_ClearAudioStream(m->s); }
  if (m->kind == 1) drwav_uninit(&m->wav);
  else if (m->kind == 2) drflac_close(m->flac);
  else if (m->kind == 3) drmp3_uninit(&m->mp3);
  else if (m->kind == 4) stb_vorbis_close(m->ogg);
  m->kind = 0; m->flac = NULL; m->ogg = NULL; m->path[0] = 0; m->ended = false;
  SDL_free(m->data); m->data = NULL;
  if (m->s) SDL_UnlockAudioStream(m->s);
}
static void music_gain(Music *m) { if (m->s) SDL_SetAudioStreamGain(m->s, m->vol * m->gain * snd_bus[BUS_MUSIC]); }
static bool music_open(Music *m, const char *path, float vol, float fade, bool loop, const char **err) {
  if (!snd_open()) { *err = SDL_GetError(); return false; }
  if (!m->s) {
    SDL_AudioSpec sp = { SDL_AUDIO_S16LE, 2, 44100 };
    m->s = SDL_CreateAudioStream(&sp, NULL);
    if (!m->s || !SDL_BindAudioStream(snd_dev, m->s)) { *err = SDL_GetError(); return false; }
  }
  music_close(m);
  size_t size = 0;
  void *data = SDL_LoadFile(path, &size);
  if (!data) { *err = SDL_GetError(); return false; }
  int kind = 0, ch = 0, rate = 0;
  size_t skip = id3_skip(data, size);              // (the decoders read from after an ID3 tag; m->data keeps the whole file to free)
  const Uint8 *d0 = (const Uint8 *)data + skip;
  size_t size0 = size - skip;
  if (ext_is(path, ".wav") && drwav_init_memory(&m->wav, d0, size0, NULL)) { kind = 1; ch = m->wav.channels; rate = (int)m->wav.sampleRate; }
  else if (ext_is(path, ".flac") && (m->flac = drflac_open_memory(d0, size0, NULL)) != NULL) { kind = 2; ch = m->flac->channels; rate = (int)m->flac->sampleRate; }
  else if (ext_is(path, ".mp3") && drmp3_init_memory(&m->mp3, d0, size0, NULL)) { kind = 3; ch = (int)m->mp3.channels; rate = (int)m->mp3.sampleRate; }
  else if (ext_is(path, ".ogg")) {
    int e = 0;
    m->ogg = stb_vorbis_open_memory(d0, (int)size0, &e, NULL);
    if (m->ogg) { stb_vorbis_info in = stb_vorbis_get_info(m->ogg); kind = 4; ch = in.channels; rate = (int)in.sample_rate; }
  }
  m->kind = kind; m->data = data;
  if (!kind || ch < 1 || ch > 2) { *err = kind ? "music: mono or stereo only" : "can't decode it (.wav, .ogg, .mp3, .flac)"; music_close(m); return false; }
  m->ch = ch; m->rate = rate; m->loop = loop; m->ended = false;
  m->vol = vol; m->gain = fade > 0 ? 0 : 1; m->target = 1; m->rate_per_s = fade > 0 ? 1 / fade : 1000;
  SDL_strlcpy(m->path, path, sizeof m->path);
  SDL_AudioSpec spec = { SDL_AUDIO_S16LE, ch, rate };
  SDL_LockAudioStream(m->s);
  SDL_SetAudioStreamFormat(m->s, &spec, NULL);
  SDL_SetAudioStreamGetCallback(m->s, music_cb, m);
  SDL_UnlockAudioStream(m->s);
  music_gain(m);
  return true;
}

// every frame (replay.c): the music's fades; the device paused with the game
static Uint64 snd_last_ms;
static void audio_update(bool paused) {
  Uint64 now = SDL_GetTicks();
  float dt = snd_last_ms ? (now - snd_last_ms) / 1000.f : 0;
  snd_last_ms = now;
  if (!snd_dev) return;
  if (paused != SDL_AudioDevicePaused(snd_dev)) { if (paused) SDL_PauseAudioDevice(snd_dev); else SDL_ResumeAudioDevice(snd_dev); }
  if (paused) return;
  if (dt > 0.1f) dt = 0.1f;
  for (int k = 0; k < 2; k++) {
    Music *m = &snd_music[k];
    if (!m->kind) continue;
    if (m->gain != m->target) {
      float step = m->rate_per_s * dt;
      m->gain = m->gain < m->target ? SDL_min(m->target, m->gain + step) : SDL_max(m->target, m->gain - step);
      music_gain(m);
    }
    if ((m->target == 0 && m->gain <= 0) || (m->ended && SDL_GetAudioStreamQueued(m->s) == 0)) music_close(m);
  }
}
static void audio_stop_all(void) {                 // (Stop: the game's sounds and music, all gone)
  for (int i = 0; i < SND_VOICES; i++) if (snd_voice[i].id) voice_free(&snd_voice[i]);
  for (int k = 0; k < 2; k++) if (snd_music[k].kind) music_close(&snd_music[k]);
  for (int b = 0; b < BUS_N; b++) snd_bus[b] = 1;  // (the game sets its own again on Play)
}

// --- Lua -----------------------------------------------------------------------
static float optf(lua_State *L, int i, float def) { return lua_isnumber(L, i) ? (float)lua_tonumber(L, i) : def; }
static int l_sound(lua_State *L) {
  size_t n = 0;
  const char *pcm = luaL_checklstring(L, 1, &n);
  int rate = (int)luaL_optinteger(L, 2, 44100);
  Uint32 id = snd_play((const Sint16 *)pcm, n / 2, 1, rate, optf(L, 3, 1), optf(L, 4, 0), optf(L, 5, 1), bus_of(luaL_optstring(L, 6, "sfx")), lua_toboolean(L, 7));
  if (!id) { lua_pushnil(L); lua_pushstring(L, snd_dev ? "no voice" : SDL_GetError()); return 2; }
  lua_pushinteger(L, id);
  return 1;
}
static int l_sound_file(lua_State *L) {
  const char *err = NULL;
  if (!snd_open()) { lua_pushnil(L); lua_pushstring(L, SDL_GetError()); return 2; }
  Clip *c = snd_clip_get(luaL_checkstring(L, 1), &err);
  if (!c) { lua_pushnil(L); lua_pushstring(L, err ? err : "can't read it"); return 2; }
  Uint32 id = snd_play(c->pcm, c->frames, c->channels, c->rate, optf(L, 2, 1), optf(L, 3, 0), optf(L, 4, 1), bus_of(luaL_optstring(L, 5, "sfx")), lua_toboolean(L, 6));
  if (!id) { lua_pushnil(L); lua_pushstring(L, "no voice"); return 2; }
  lua_pushinteger(L, id);
  return 1;
}
static int l_sound_set(lua_State *L) {
  Voice *v = voice_of((Uint32)luaL_checkinteger(L, 1));
  if (v) {
    SDL_LockAudioStream(v->s);
    if (lua_isnumber(L, 2)) { v->vol = (float)lua_tonumber(L, 2); SDL_SetAudioStreamGain(v->s, v->vol * snd_bus[v->bus]); }
    if (lua_isnumber(L, 3)) { float p = (float)lua_tonumber(L, 3); SDL_SetAudioStreamFrequencyRatio(v->s, p < 0.05f ? 0.05f : p > 8 ? 8 : p); }
    SDL_UnlockAudioStream(v->s);
  }
  lua_pushboolean(L, v && (v->loop || SDL_GetAudioStreamQueued(v->s) > 0));
  return 1;
}
static int l_sound_kill(lua_State *L) {
  Voice *v = voice_of((Uint32)luaL_checkinteger(L, 1));
  if (v) voice_free(v);
  return 0;
}
static int l_sound_stop(lua_State *L) {
  (void)L;
  for (int i = 0; i < SND_VOICES; i++) if (snd_voice[i].id) voice_free(&snd_voice[i]);
  return 0;
}
static int l_music(lua_State *L) {
  const char *path = lua_isstring(L, 1) ? lua_tostring(L, 1) : NULL;
  float vol = optf(L, 2, 1), fade = optf(L, 3, 0);
  bool loop = lua_isnoneornil(L, 4) || lua_toboolean(L, 4);
  Music *cur = &snd_music[snd_cur], *old = &snd_music[snd_cur ^ 1];
  if (cur->kind && path && !SDL_strcmp(cur->path, path) && !cur->ended) {   // (the same track: just its volume)
    cur->vol = vol; cur->target = 1; cur->rate_per_s = fade > 0 ? 1 / fade : 1000; music_gain(cur);
    lua_pushboolean(L, 1);
    return 1;
  }
  if (cur->kind) {                                 // the one playing fades out (or stops now)
    if (old->kind) music_close(old);
    cur->target = 0; cur->rate_per_s = fade > 0 ? 1 / fade : 1000;
    if (fade <= 0) music_close(cur);
    snd_cur ^= 1;
    cur = &snd_music[snd_cur];
  }
  if (!path) { lua_pushboolean(L, 1); return 1; }
  if (cur->kind) music_close(cur);
  const char *err = NULL;
  if (!music_open(cur, path, vol, fade, loop, &err)) { lua_pushnil(L); lua_pushstring(L, err ? err : "can't play it"); return 2; }
  lua_pushboolean(L, 1);
  return 1;
}
static int l_bus(lua_State *L) {
  int b = bus_of(luaL_checkstring(L, 1));
  if (lua_isnumber(L, 2)) {
    float v = (float)lua_tonumber(L, 2);
    snd_bus[b] = v < 0 ? 0 : v > 1 ? 1 : v;
    for (int i = 0; i < SND_VOICES; i++) if (snd_voice[i].id && snd_voice[i].bus == b) SDL_SetAudioStreamGain(snd_voice[i].s, snd_voice[i].vol * snd_bus[b]);
    if (b == BUS_MUSIC) for (int k = 0; k < 2; k++) music_gain(&snd_music[k]);
  }
  lua_pushnumber(L, snd_bus[b]);
  return 1;
}
static int l_audio_info(lua_State *L) {
  const char *err = NULL;
  Clip *c = snd_clip_get(luaL_checkstring(L, 1), &err);
  if (!c) { lua_pushnil(L); lua_pushstring(L, err ? err : "can't read it"); return 2; }
  lua_pushnumber(L, c->rate ? (double)c->frames / c->rate : 0);
  lua_pushinteger(L, c->channels);
  lua_pushinteger(L, c->rate);
  return 3;
}
static void sound_register(lua_State *L) {
  lua_register(L, "host_sound", l_sound);
  lua_register(L, "host_sound_file", l_sound_file);
  lua_register(L, "host_sound_set", l_sound_set);
  lua_register(L, "host_sound_kill", l_sound_kill);
  lua_register(L, "host_sound_stop", l_sound_stop);
  lua_register(L, "host_music", l_music);
  lua_register(L, "host_bus", l_bus);
  lua_register(L, "host_audio_info", l_audio_info);
}
