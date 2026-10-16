// images.h - every picture format we read and write (part of editor.c, after
// stb_image / stb_image_write). One decoder for the game (the `image`
// component, tile sets, bullets: editor_image_decode) and for lite
// (renderer.image.load, the atlas packer, the texture viewer):
//   PNG, JPG, BMP, TGA, GIF  stb_image (public domain / MIT)
//   QOI                      koi_image (public domain), "qoif"
//   WebP                     tiny_webp (BSD-3: WebP's own licence), lossy and lossless, no animations
//   PUG                      r-lyeh's: a JPG (colour) + a PNG (alpha) + a 12-byte footer
//                            (sizes, little endian, then "pug1"); public domain
// and one encoder, by the file's extension: .png, .jpg / .jpeg (quality),
// .qoi, .pug (quality: its JPG's). Pixels are RGBA, 4 bytes each; what
// img_decode returns is freed with free().
#ifndef REPLAY_IMAGES_H
#define REPLAY_IMAGES_H
#include <stdlib.h>
#include <string.h>

#define KOI_IMAGE_IMPLEMENTATION
#define KOI_IMAGE_STATIC
#define KOI_NO_STDIO
#include "3rd/images/koi_image.h"
#define KOI_IMAGE_WRITE_IMPLEMENTATION
#define KOI_IMAGE_WRITE_STATIC
#define KOI_WRITE_NO_STDIO
#include "3rd/images/koi_image_write.h"
#define twp_STATIC
#define twp_IMPLEMENTATION
#include "3rd/images/tiny_webp.h"

static unsigned le32(const unsigned char *p) { return p[0] | (p[1] << 8) | (p[2] << 16) | ((unsigned) p[3] << 24); }

// -> RGBA pixels (free()) | NULL
static unsigned char *img_decode(const void *data, int size, int *w, int *h) {
  const unsigned char *d = (const unsigned char *) data;
  int n = 0;
  if (!d || size <= 0) return NULL;
  if (size >= 4 && !memcmp(d, "qoif", 4)) return koi_load_from_memory(d, size, w, h, &n, 4);
  if (size >= 12 && !memcmp(d, "RIFF", 4) && !memcmp(d + 8, "WEBP", 4))
    return twp_read_from_memory((void *) d, size, w, h, twp_FORMAT_RGBA, 0);
  unsigned char *rgba = stbi_load_from_memory(d, size, w, h, &n, 4);   // (a PUG starts with its JPG: this reads the colour)
  if (rgba && size > 12 && !memcmp(d + size - 4, "pug1", 4)) {
    unsigned color = le32(d + size - 12), alpha = le32(d + size - 8);
    if ((unsigned long long) color + alpha + 12 <= (unsigned) size) {
      int aw = 0, ah = 0, an = 0;
      unsigned char *a = stbi_load_from_memory(d + color, (int) alpha, &aw, &ah, &an, 1);
      if (a && aw == *w && ah == *h) for (int i = 0; i < aw * ah; i++) rgba[i * 4 + 3] = a[i];
      if (a) stbi_image_free(a);
    }
  }
  return rgba;
}

typedef struct { unsigned char *p; size_t n, cap; } ImgBuf;
static void img_put(void *ctx, void *data, int size) {
  ImgBuf *b = (ImgBuf *) ctx;
  if (size <= 0) return;
  if (b->n + size > b->cap) {
    size_t cap = b->cap ? b->cap * 2 : 65536;
    while (cap < b->n + size) cap *= 2;
    unsigned char *q = (unsigned char *) realloc(b->p, cap);
    if (!q) return;
    b->p = q; b->cap = cap;
  }
  memcpy(b->p + b->n, data, size);
  b->n += size;
}
static const char *img_ext(const char *path) {
  const char *dot = strrchr(path ? path : "", '.');
  return dot ? dot + 1 : "";
}
static int img_ieq(const char *a, const char *b) {
  for (; *a && *b; a++, b++) if ((*a | 32) != (*b | 32)) return 0;
  return *a == *b;
}
// RGBA -> the bytes of a file of that kind ("png", "jpg", "qoi", "pug"); quality 1..100 (0: 85)
// -> malloc'd bytes and their size | NULL
static unsigned char *img_encode(const char *kind, int w, int h, const unsigned char *rgba, int quality, size_t *out_n) {
  ImgBuf b = { 0 };
  int ok = 0;
  if (quality <= 0 || quality > 100) quality = 85;
  if (img_ieq(kind, "qoi")) ok = koi_write_qoi_to_func(img_put, &b, w, h, 4, rgba);
  else if (img_ieq(kind, "jpg") || img_ieq(kind, "jpeg")) ok = stbi_write_jpg_to_func(img_put, &b, w, h, 4, rgba, quality);
  else if (img_ieq(kind, "pug")) {
    ok = stbi_write_jpg_to_func(img_put, &b, w, h, 4, rgba, quality);   // (its colour: stb ignores the alpha)
    size_t color = b.n;
    unsigned char *a = (unsigned char *) malloc((size_t) w * h);
    if (ok && a) {
      for (int i = 0; i < w * h; i++) a[i] = rgba[i * 4 + 3];
      ok = stbi_write_png_to_func(img_put, &b, w, h, 1, a, w);
      size_t alpha = b.n - color;
      unsigned char foot[12] = { (unsigned char) color, (unsigned char) (color >> 8), (unsigned char) (color >> 16), (unsigned char) (color >> 24),
                                 (unsigned char) alpha, (unsigned char) (alpha >> 8), (unsigned char) (alpha >> 16), (unsigned char) (alpha >> 24),
                                 'p', 'u', 'g', '1' };
      img_put(&b, foot, 12);
    } else ok = 0;
    free(a);
  }
  else ok = stbi_write_png_to_func(img_put, &b, w, h, 4, rgba, w * 4);
  if (!ok || !b.n) { free(b.p); return NULL; }
  *out_n = b.n;
  return b.p;
}
#endif
