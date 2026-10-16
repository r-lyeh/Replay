/* koi_image_write - v1.02 - public domain stb like image writer
                                    to C stdio - https://github.com/Muppetsg2/koi
                                    no warranty implied; use at your own risk
   
   Do this:
      #define KOI_IMAGE_WRITE_IMPLEMENTATION
   before you include this file in *one* C or C++ file to create the implementation.

   // i.e. it should look like this:
   #include ...
   #include ...
   #include ...
   #define KOI_IMAGE_WRITE_IMPLEMENTATION
   #include "koi_image_write.h"

   You can #define KOI_WRITE_ASSERT(x) before the #include to avoid using assert.h.


   QUICK NOTES:
      This header file is a library for writing images to C stdio or a callback.

   Full documentation under "DOCUMENTATION" below.


LICENSE

   See end of file for license information.

RECENT REVISION HISTORY:

      1.02  (2026-04-30) Improved file handling
      1.01  (2025-11-20) Unified formatting of functions and tabs
      1.00  (2025-05-09) QOI file writer

   See end of file for full revision history.


 ============================    Contributors    =========================

   Image formats
      Marceli Antosik (qoi)
*/

#if !defined(KOI_INCLUDE_KOI_IMAGE_WRITE_H)
#define KOI_INCLUDE_KOI_IMAGE_WRITE_H

// DOCUMENTATION
//
// Basic usage:
//    int koi_write_qoi(filename, w, h, comp, data);
//    // ... process data if not NULL ...
//    // ... save data to file ...
//
// Standard parameters:
//    char const *filename   -- save image path
//    int w                  -- save image width in pixels
//    int h                  -- save image height in pixels
//    int channels_in_data   -- # of image components in save image data
//    const void *data       -- save image data
//
// The return value from an image save function is an 'int' which is
// non-0 on success, or 0 on failure. The function create an image file 
// defined by the parameters. The image is a rectangle of pixels stored
// from left-to-right, top-to-bottom.
//
// Each pixel contains 'comp' channels of data stored interleaved with 8-bits per channel,
// in the following order:
//
//     N=#comp     components
//       1           grey
//       2           grey, alpha
//       3           red, green, blue
//       4           red, green, blue, alpha
//
// The rectangle is 'w' pixels wide and 'h' pixels tall. The *data pointer 
// points to the first byte of the top-left-most pixel. If image saving fails for any reason,
// the return value will be NULL. The function koiw_failure_reason() can be queried for an extremely brief,
// end-user unfriendly explanation of why the load failed. Define KOI_WRITE_NO_FAILURE_STRINGS
// to avoid compiling these strings at all, and KOI_WRITE_FAILURE_USERMSG to get slightly
// more user-friendly ones.
//
// There are also equivalent functions that use an arbitrary write function. You are 
// expected to open/close your file - equivalent before and after calling these:
// 
//    int koi_write_qoi_to_func(koi_write_func *func, void *context, int w, int h, int comp, const void *data);
//
// where the callback is:
//    void koi_write_func(void *context, void *data, int size);
//
// ===========================================================================
//
// UNICODE
//
//   If compiling for Windows and you wish to use Unicode filenames, compile
//   with
//       #define KOI_WRITE_WINDOWS_UTF8
//   and pass utf8-encoded filenames. Call koiw_convert_wchar_to_utf8 to convert
//   Windows wchar_t filenames to utf8.
//
// ===========================================================================
//
// PHILOSOPHY
//
// koi libraries are designed with the following priorities:
//
//    1. easy to use
//    2. easy to maintain
//    3. good performance
//
// Sometimes I let "good performance" creep up in priority over "easy to maintain",
// and for best performance I may provide less-easy-to-use APIs that give higher
// performance, in addition to the easy-to-use ones. Nevertheless, it's important
// to keep in mind that from the standpoint of you, a client of this library,
// all you care about is #1 and #3, and koi libraries DO NOT emphasize #3 above all.
//
// Some secondary priorities arise directly from the first two, some of which
// provide more explicit reasons why performance can't be emphasized.
//
//    - Portable ("ease of use")
//    - Small source code footprint ("easy to maintain")
//    - No dependencies ("ease of use")
//
// ===========================================================================
//
// ADDITIONAL CONFIGURATION
//
// - You can flip image data on write setting flag to non-zero value.
//
//       void koi_set_flip_vertically_on_write(int flag);
//
// - You can define KOI_WRITE_NO_STDIO to disable the file variant of these
//   functions, so the library will not use stdio.h at all.
//
// - You can set this global variables that will be use in save functions:
//
//      void koi_set_qoi_color_space_on_write(int value);   // defaults to 0 (sRGB); set to 1 to tell other that save values are linear.
//
//  - You can suppress implementation of any of the encoder to reduce
//    your code footprint by #defining one or more of the following
//    symbols before creating the implementation.
//
//        KOI_WRITE_NO_QOI
//
//  - You can request *only* certain encoders and suppress all other ones
//    (this will be more forward-compatible, as addition of new decoders
//    doesn't require you to disable them explicitly):
//
//        KOI_WRITE_ONLY_QOI

#define KOI_IMAGE_WRITE_VERSION 2

#include <stdlib.h>
typedef unsigned char koiw_uc;
typedef signed char   koiw_sc;

#if defined(__cplusplus)
extern "C" {
#endif

// if KOI_IMAGE_WRITE_STATIC causes problems, try defining KOIWDEF to 'inline' or 'static inline'
#if !defined(KOIWDEF)
   #if defined(KOI_IMAGE_WRITE_STATIC)
      #define KOIWDEF  static
   #else
      #define KOIWDEF  extern
   #endif
#endif

#if !defined(KOI_WRITE_NO_STDIO)
KOIWDEF int koi_write_qoi(char const *filename, int w, int h, int comp, const void *data);

   #if defined(KOI_WRITE_WINDOWS_UTF8)
KOIWDEF int koiw_convert_wchar_to_utf8(char *buffer, size_t bufferlen, const wchar_t *input);
   #endif
#endif

typedef void koi_write_func(void *context, void *data, int size);

#if !defined(KOI_WRITE_NO_QOI)
KOIWDEF int koi_write_qoi_to_func(koi_write_func *func, void *context, int w, int h, int comp, const void *data);
#endif

// get a VERY brief reason for failure
// on most compilers (and ALL modern mainstream compilers) this is threadsafe
KOIWDEF const char *koiw_failure_reason(void);

// flip the image vertically, so the first pixel in the saved array is the bottom left
KOIWDEF void koi_set_flip_vertically_on_write(int flag_true_if_should_flip);
// set qoi color space info, value is either 0 or 1
#if !defined(KOI_WRITE_NO_QOI)
KOIWDEF void koi_set_qoi_color_space_on_write(int qoi_color_space);
#endif

// as above, but only applies to images saved on the thread that calls the function
// this function is only available if your compiler supports thread-local variables;
// calling it will fail to link if your compiler doesn't
KOIWDEF void koi_set_flip_vertically_on_write_thread(int flag_true_if_should_flip);
#if !defined(KOI_WRITE_NO_QOI)
KOIWDEF void koi_set_qoi_color_space_on_write_thread(int qoi_color_space);
#endif

#if defined(__cplusplus)
}
#endif

#endif // KOI_INCLUDE_KOI_IMAGE_WRITE_H

#if defined(KOI_IMAGE_WRITE_IMPLEMENTATION)
#if defined(KOI_WRITE_ONLY_QOI)
   #if !defined(KOI_WRITE_ONLY_QOI)
      #define KOI_WRITE_NO_QOI
   #endif
#endif
#if defined(_WIN32)
   #if !defined(_CRT_SECURE_NO_WARNINGS)
      #define _CRT_SECURE_NO_WARNINGS
   #endif
   #if !defined(_CRT_NONSTDC_NO_DEPRECATE)
      #define _CRT_NONSTDC_NO_DEPRECATE
   #endif
#endif

#if !defined(KOI_WRITE_NO_STDIO)
#include <stdio.h>
#endif // KOI_WRITE_NO_STDIO

#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#if !defined(KOI_WRITE_ASSERT)
#include <assert.h>
   #define KOI_WRITE_ASSERT(x) assert(x)
#endif

#if defined(__cplusplus)
   #define KOIW_EXTERN extern "C"
#else
   #define KOIW_EXTERN extern
#endif

#if !defined(_MSC_VER)
   #if defined(__cplusplus)
      #define koiw_inline inline
   #else
      #define koiw_inline
   #endif
#else
   #define koiw_inline __forceinline
#endif

#if !defined(KOI_WRITE_NO_THREAD_LOCALS)
   #if defined(__cplusplus) &&  __cplusplus >= 201103L
      #define KOI_WRITE_THREAD_LOCAL       thread_local
   #elif defined(__GNUC__) && __GNUC__ < 5
      #define KOI_WRITE_THREAD_LOCAL       __thread
   #elif defined(_MSC_VER)
      #define KOI_WRITE_THREAD_LOCAL       __declspec(thread)
   #elif defined (__STDC_VERSION__) && __STDC_VERSION__ >= 201112L && !defined(__STDC_NO_THREADS__)
      #define KOI_WRITE_THREAD_LOCAL       _Thread_local
   #endif

   #if !defined(KOI_WRITE_THREAD_LOCAL)
      #if defined(__GNUC__)
         #define KOI_WRITE_THREAD_LOCAL    __thread
      #endif
   #endif
#endif

#define KOIW_UCHAR(x) (koiw_uc)((x) & 0xff)

#if defined(_MSC_VER) || defined(__SYMBIAN32__)
typedef unsigned int koiw__uint32;
#else
#include <stdint.h>
typedef uint32_t     koiw__uint32;
#endif

// should produce compiler error if size is wrong
typedef int koiw_validate_uint32[sizeof(koiw__uint32) == 4 ? 1 : -1];

typedef struct
{
   koi_write_func *func;
   void *context;
   koiw_uc buffer[64];
   int buf_used;
} koi__write_context;

// initialize a callback-based context
static void koi__start_write_callbacks(koi__write_context *s, koi_write_func *c, void *context)
{
   s->func = c;
   s->context = context;
   s->buf_used = 0;   //< @replay: (it wasn't set: a write began from whatever was on the stack)
}

static
#if defined(KOI_WRITE_THREAD_LOCAL)
KOI_WRITE_THREAD_LOCAL
#endif
const char *koiw__g_failure_reason;

KOIWDEF const char *koiw_failure_reason(void)
{
   return koiw__g_failure_reason;
}

#if !defined(KOI_WRITE_NO_FAILURE_STRINGS)
static int koiw__err(const char *str)
{
   koiw__g_failure_reason = str;
   return 0;
}
#endif

// koiw__err - error

#if defined(KOI_WRITE_NO_FAILURE_STRINGS)
   #define koiw__err(x, y) 0
#elif defined(KOI_WRITE_FAILURE_USERMSG)
   #define koiw__err(x, y) koiw__err(y)
#else
    #define koiw__err(x,y)  koiw__err(x)
#endif

static int koi__vertically_flip_on_write_global = 0;

KOIWDEF void koi_set_flip_vertically_on_write(int flag_true_if_should_flip)
{
   koi__vertically_flip_on_write_global = flag_true_if_should_flip;
}

#if !defined(KOI_WRITE_NO_QOI)
static int koi__qoi_color_space_on_write_global = 0;

KOIWDEF void koi_set_qoi_color_space_on_write(int qoi_color_space)
{
   koi__qoi_color_space_on_write_global = qoi_color_space;
}
#endif

#if !defined(KOI_WRITE_THREAD_LOCAL)
   #define koi__vertically_flip_on_write koi__vertically_flip_on_write_global

   #if !defined(KOI_WRITE_NO_QOI)
      #define koi__qoi_color_space_on_write koi__qoi_color_space_on_write_global
   #endif
#else
static KOI_WRITE_THREAD_LOCAL int koi__vertically_flip_on_write_local, koi__vertically_flip_on_write_set;

KOIWDEF void koi_set_flip_vertically_on_write_thread(int flag_true_if_should_flip)
{
   koi__vertically_flip_on_write_local = flag_true_if_should_flip;
   koi__vertically_flip_on_write_set = 1;
}

   #define koi__vertically_flip_on_write (koi__vertically_flip_on_write_set    \
                                         ? koi__vertically_flip_on_write_local \
                                         : koi__vertically_flip_on_write_global)

   #if !defined(KOI_WRITE_NO_QOI)
static KOI_WRITE_THREAD_LOCAL int koi__qoi_color_space_on_write_local, koi__qoi_color_space_on_write_set;

KOIWDEF void koi_set_qoi_color_space_on_write_thread(int qoi_color_space)
{
   koi__qoi_color_space_on_write_local = qoi_color_space;
   koi__qoi_color_space_on_write_set = 1;
}

      #define koi__qoi_color_space_on_write (koi__qoi_color_space_on_write_set    \
                                            ? koi__qoi_color_space_on_write_local \
                                            : koi__qoi_color_space_on_write_global)
   #endif // !KOI_WRITE_NO_QOI
#endif // KOI_WRITE_THREAD_LOCAL

#if !defined(KOI_WRITE_NO_STDIO)
static void koi__stdio_write(void *context, void *data, int size)
{
   fwrite(data, 1, size, (FILE*)context);
}

#if defined(_WIN32) && defined(KOI_WRITE_WINDOWS_UTF8)
KOIW_EXTERN __declspec(dllimport) int __stdcall MultiByteToWideChar(unsigned int cp, unsigned long flags, const char *str, int cbmb, wchar_t *widestr, int cchwide);
KOIW_EXTERN __declspec(dllimport) int __stdcall WideCharToMultiByte(unsigned int cp, unsigned long flags, const wchar_t *widestr, int cchwide, char *str, int cbmb, const char *defchar, int *used_default);

KOIWDEF int koiw_convert_wchar_to_utf8(char *buffer, size_t bufferlen, const wchar_t *input)
{
   int len = (bufferlen > 0x7FFFFFFF) ? 0x7FFFFFFF : (int)bufferlen;
   return WideCharToMultiByte(65001 /* UTF8 */, 0, input, -1, buffer, len, NULL, NULL);
}
#endif

static FILE *koiw__fopen(char const *filename, char const *mode)
{
   FILE *f;
#if defined(_WIN32) && defined(KOI_WRITE_WINDOWS_UTF8)
   wchar_t wMode[64];
   wchar_t wFilename[4096];
   if (0 == MultiByteToWideChar(65001 /* UTF8 */, 0, filename, -1, wFilename, (int)(sizeof(wFilename) / sizeof(*wFilename))))
      return NULL;

   if (0 == MultiByteToWideChar(65001 /* UTF8 */, 0, mode, -1, wMode, (int)(sizeof(wMode) / sizeof(*wMode))))
      return NULL;

   #if defined(_MSC_VER) && _MSC_VER >= 1400
   if (0 != _wfopen_s(&f, wFilename, wMode))
      f = NULL;
   #else
   f = _wfopen(wFilename, wMode);
   #endif

#elif defined(_MSC_VER) && _MSC_VER >= 1400
   if (0 != fopen_s(&f, filename, mode))
      f = NULL;
#else
   f = fopen(filename, mode);
#endif
   return f;
}

static int koi__start_write_file(koi__write_context *s, const char *filename)
{
   FILE *f = koiw__fopen(filename, "wb");
   if (f == NULL) return koiw__err("can't fopen", "Unable to open file");
   koi__start_write_callbacks(s, koi__stdio_write, (void*)f);
   return 1;
}

static void koi__end_write_file(koi__write_context *s)
{
   fclose((FILE*)s->context);
}

#endif // !KOI_WRITE_NO_STDIO

koiw_inline static void koiw__put8(koi__write_context *s, koiw_uc c)
{
   s->func(s->context, &c, 1);
}

static void koiw__put16le(koi__write_context *s, int x)
{
   koiw_uc b[2];
   b[0] = KOIW_UCHAR(x);
   b[1] = KOIW_UCHAR(x >> 8);
   s->func(s->context, b, 2);
}

static void koiw__put16be(koi__write_context *s, int x)
{
   koiw_uc b[2];
   b[0] = KOIW_UCHAR(x >> 8);
   b[1] = KOIW_UCHAR(x);
   s->func(s->context, b, 2);
}

static void koiw__put32le(koi__write_context *s, koiw__uint32 x)
{
   koiw_uc b[4];
   b[0] = KOIW_UCHAR(x);
   b[1] = KOIW_UCHAR(x >> 8);
   b[2] = KOIW_UCHAR(x >> 16);
   b[3] = KOIW_UCHAR(x >> 24);
   s->func(s->context, b, 4);
}

static void koiw__put32be(koi__write_context *s, koiw__uint32 x)
{
   koiw_uc b[4];
   b[0] = KOIW_UCHAR(x >> 24);
   b[1] = KOIW_UCHAR(x >> 16);
   b[2] = KOIW_UCHAR(x >> 8);
   b[3] = KOIW_UCHAR(x);
   s->func(s->context, b, 4);
}

static void koiw__writefv(koi__write_context *s, int big_endian, const char *fmt, va_list v)
{
   while (*fmt) {
      switch (*fmt++) {
         case ' ': break;
         case '1': {
            koiw__put8(s, KOIW_UCHAR(va_arg(v, int)));
            break;
         }
         case '2': {
            int x = va_arg(v, int);
            if (big_endian) {
               koiw__put16be(s, x);
            }
            else {
               koiw__put16le(s, x);
            }
            break;
         }
         case '4': {
            koiw__uint32 x = va_arg(v, int);
            if (big_endian) {
               koiw__put32be(s, x);
            }
            else {
               koiw__put32le(s, x);
            }
            break;
         }
         default: {
            KOI_WRITE_ASSERT(0);
            return;
         }
      }
   }
}

static void koiw__writef(koi__write_context *s, int big_endian, const char *fmt, ...)
{
   va_list v;
   va_start(v, fmt);
   koiw__writefv(s, big_endian, fmt, v);
   va_end(v);
}

static void koiw__write_flush(koi__write_context *s)
{
   if (s->buf_used) {
      s->func(s->context, &s->buffer, s->buf_used);
      s->buf_used = 0;
   }
}

static void koiw__write1(koi__write_context *s, koiw_uc a)
{
   if ((size_t)s->buf_used + 1 > sizeof(s->buffer))
      koiw__write_flush(s);
   s->buffer[s->buf_used++] = a;
}

static void koiw__write3(koi__write_context *s, koiw_uc a, koiw_uc b, koiw_uc c)
{
   int n;
   if ((size_t)s->buf_used + 3 > sizeof(s->buffer))
      koiw__write_flush(s);
   n = s->buf_used;
   s->buf_used = n + 3;
   s->buffer[n + 0] = a;
   s->buffer[n + 1] = b;
   s->buffer[n + 2] = c;
}

static void koiw__write_pixel(koi__write_context *s, int rgb_dir, int comp, int write_alpha, int expand_mono, koiw_uc *d)
{
   koiw_uc bg[3] = { 255, 0, 255 }, px[3];
   int k;
   
   if (write_alpha < 0)
      koiw__write1(s, d[comp - 1]);
   
   switch (comp) {
      case 2: // 2 pixels = mono + alpha, alpha is written separately, so same as 1-channel case
      case 1: {
         if (expand_mono)
            koiw__write3(s, d[0], d[0], d[0]);  // monochrome bmp
         else
            koiw__write1(s, d[0]);              // monochrome TGA
         break;
      }
      case 4: {
         if (!write_alpha) {
            // composite against pink background
            for (k = 0; k < 3; ++k)
               px[k] = bg[k] + ((d[k] - bg[k]) * d[3]) / 255;
            koiw__write3(s, px[1 - rgb_dir], px[1], px[1 + rgb_dir]);
            break;
         }
      }
      /* FALLTHROUGH */
      case 3: {
         koiw__write3(s, d[1 - rgb_dir], d[1], d[1 + rgb_dir]);
         break;
      }
   }
   if (write_alpha > 0)
      koiw__write1(s, d[comp - 1]);
}

//////////////////////////////////////////////////////////////////////////////
//
//  QOI - The "Quite OK Image Format" decoder
//
#if !defined(KOI_WRITE_NO_QOI)

typedef union {
   koiw_uc color[4];
   koiw__uint32 v;
} koiw__qoi_pixel;

static koiw__qoi_pixel koi_read_qoi_pixel(int comp, int has_alpha, koiw_uc *d)
{
   koiw__qoi_pixel out;
   koiw_uc bg[3] = { 255, 0, 255 }, px[3];
   int k;
   
   switch (comp) {
      case 2: // 2 pixels = mono + alpha, alpha is read separately, so same as 1-channel case
      case 1: {
         out.color[0] = out.color[1] = out.color[2] = d[0];
         break;
      }
      case 4: {
         if (!has_alpha) {
            // composite against pink background
            for (k = 0; k < 3; ++k)
               px[k] = bg[k] + ((d[k] - bg[k]) * d[3]) / 255;
            
            out.color[0] = px[0];
            out.color[1] = px[1];
            out.color[2] = px[2];
            break;
         }
      }
      /* FALLTHROUGH */
      case 3: {
         out.color[0] = d[0];
         out.color[1] = d[1];
         out.color[2] = d[2];
         break;
      }
   }
   if (has_alpha != 0)
      out.color[3] = d[comp - 1];
   else
      out.color[3] = 255;
   
   return out;
}

static int koi_write_qoi_core(koi__write_context *s, int x, int y, int comp, const void *data)
{
   int has_alpha = (comp == 2 || comp == 4);
   int i, j, jstart, jdir, index_pos;
   koiw__uint32 pxi, len;
   koiw_uc run = 0;
   koiw__qoi_pixel px, prev_px, index[64];
   
   if (y < 0 || x < 0)
      return koiw__err("bad dimmensions", "Corrupt image dimmensions");
   
   koiw__writef(s, 1, "1111 44 11", 'q', 'o', 'i', 'f', x, y, has_alpha ? 4 : 3, koi__qoi_color_space_on_write != 0 ? 1 : 0);
   
   prev_px.color[0] = 0;   // R
   prev_px.color[1] = 0;   // G
   prev_px.color[2] = 0;   // B
   prev_px.color[3] = 255; // A
   px = prev_px;

   memset(index, 0, sizeof(index));

#define KOIW_QOI_COLOR_HASH(px) (px.color[0] * 3 + px.color[1] * 5 + px.color[2] * 7 + px.color[3] * 11)
   
   if (koi__vertically_flip_on_write) {
      jstart = y - 1;
      jdir = -1;
   }
   else {
      jstart = 0;
      jdir = 1;
   }
   len = x * y;
   for (pxi = 0; pxi < len; ++pxi) {
      j = jstart + (pxi / x) * jdir;
      i = pxi % x;
      
      koiw_uc *row = (koiw_uc*)data + j * x * comp;
      koiw_uc *begin = row + i * comp;
      
      px = koi_read_qoi_pixel(comp, has_alpha, begin);
      
      if (px.v == prev_px.v) {
         if (++run == 62 || pxi == len - 1) {
            koiw__write1(s, (koiw_uc)(KOIW_UCHAR(0xc0) | (run - 1))); /* QOI_OP_RUN */
            run = 0;
         }
      }
      else {
         if (run > 0) {
            koiw__write1(s, (koiw_uc)(KOIW_UCHAR(0xc0) | (run - 1))); /* QOI_OP_RUN */
            run = 0;
         }
         
         index_pos = KOIW_QOI_COLOR_HASH(px) & (64 - 1);
         if (index[index_pos].v == px.v) {
            koiw__write1(s, KOIW_UCHAR(index_pos)); /* QOI_OP_INDEX */
         }
         else {
            index[index_pos] = px;
            int ch;
            koiw_uc header;
            if (px.color[3] == prev_px.color[3]) {
               koiw_sc dr = px.color[0] - prev_px.color[0];
               koiw_sc dg = px.color[1] - prev_px.color[1];
               koiw_sc db = px.color[2] - prev_px.color[2];
               
               if (dr > -3 && dr < 2 && dg > -3 && dg < 2 && db > -3 && db < 2) { /* QOI_OP_DIFF */
                  header = KOIW_UCHAR(0x40) | (dr + 2) << 4 | (dg + 2) << 2 | (db + 2);
                  ch = 0;
               }
               else {
                  koiw_sc dr_dg = dr - dg;
                  koiw_sc db_dg = db - dg;
                  
                  if (dr_dg > -9 && dr_dg < 8 && dg > -33 && dg < 32 && db_dg > -9 && db_dg < 8) { /* QOI_OP_LUMA */
                     koiw__write1(s, KOIW_UCHAR(0x80) | (dg + 32));
                     header = (dr_dg + 8) << 4 | (db_dg + 8);
                     ch = 0;
                  }
                  else {
                     header = KOIW_UCHAR(0xfe); /* QOI_OP_RGB */
                     ch = 3;
                  }
               }
            }
            else {
               header = KOIW_UCHAR(0xff); /* QOI_OP_RGBA */
               ch = 4;
            }
            koiw__write1(s, header);
            koiw__write_pixel(s, 1, ch, ch == 4, 1, px.color);
         }
      }
      prev_px = px;
   }
   koiw__write_flush(s);
   koiw__writef(s, 1, "11111111", 0, 0, 0, 0, 0, 0, 0, 1);
#undef KOIW_QOI_COLOR_HASH
   return 1;
}

KOIWDEF int koi_write_qoi_to_func(koi_write_func *func, void *context, int x, int y, int comp, const void *data)
{
   koi__write_context s;
   koi__start_write_callbacks(&s, func, context);
   return koi_write_qoi_core(&s, x, y, comp, data);
}

#if !defined(KOI_WRITE_NO_STDIO)
KOIWDEF int koi_write_qoi(char const *filename, int x, int y, int comp, const void *data)
{
   koi__write_context s;
   if (koi__start_write_file(&s, filename)) {
      int r = koi_write_qoi_core(&s, x, y, comp, data);
      koi__end_write_file(&s);
      return r;
   }
   else
      return 0;
}
#endif // !KOI_WRITE_NO_STDIO

#endif // !KOI_WRITE_NO_QOI

#endif // KOI_IMAGE_WRITE_IMPLEMENTATION

/*
   revision history:
      1.02  (2026-04-30) Improved file handling
      1.01  (2025-11-20) Unified formatting of functions and tabs
      1.00  (2025-05-09) QOI file writer
*/

/*
------------------------------------------------------------------------------
This software is available under 2 licenses -- choose whichever you prefer.
------------------------------------------------------------------------------
ALTERNATIVE A - MIT License
Copyright (c) 2025 Marceli Antosik
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
------------------------------------------------------------------------------
ALTERNATIVE B - Public Domain (https://unlicense.org)
This is free and unencumbered software released into the public domain.
Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.
In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the
software to the public domain. We make this dedication for the benefit
of the public at large and to the detriment of our heirs and
successors. We intend this dedication to be an overt act of
relinquishment in perpetuity of all present and future rights to this
software under copyright law.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
For more information, please refer to <https://unlicense.org>
------------------------------------------------------------------------------
*/