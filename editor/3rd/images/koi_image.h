/* koi_image - v1.02 - public domain stb like image loader 
               for more extensions - https://github.com/Muppetsg2/koi
                     no warranty implied; use at your own risk

   Do this:
      #define KOI_IMAGE_IMPLEMENTATION
   before you include this file in *one* C or C++ file to create the implementation.

   // i.e. it should look like this:
   #include ...
   #include ...
   #include ...
   #define KOI_IMAGE_IMPLEMENTATION
   #include "koi_image.h"

   You can #define KOI_ASSERT(x) before the #include to avoid using assert.h.
   And #define KOI_MALLOC and KOI_FREE to avoid using malloc, free


   QUICK NOTES:
      Primarily of interest to game developers and other people who can
      avoid problematic images and only need the trivial interface
      
      - decode from memory or through FILE (define KOI_NO_STDIO to remove code)
      - decode from arbitrary I/O callbacks

   Full documentation under "DOCUMENTATION" below.


LICENSE

   See end of file for license information.

RECENT REVISION HISTORY:

      1.02  (2026-04-30) Improved memory safety and made Windows file handling more robust
      1.01  (2025-11-20) Unified formatting of functions and tabs
      1.00  (2025-05-09) QOI file loader

   See end of file for full revision history.


 ============================    Contributors    =========================

   Image formats
      Marceli Antosik (qoi)
*/

#if !defined(KOI_INCLUDE_KOI_IMAGE_H)
#define KOI_INCLUDE_KOI_IMAGE_H

// DOCUMENTATION
//
// Basic usage:
//   int x,y,n;
//   unsigned char *data = koi_load(filename, &x, &y, &n, 0);
//   // ... process data if not NULL ...
//   // ... x = width, y = height, n = # 8-bit components per pixel ...
//   // ... replace '0' with '1'..'4' to force that many components per pixel
//   // ... 'n' will always be the number of channels in file
//   koi_image_free(data);
//
// Standard parameters:
//   int *x           -- outputs image width in pixels
//   int *y           -- outputs image height in pixels
//   int *channels_in_file  -- outputs # of image components in image file
//   int desired_channels   -- if non-zero, # of image components requested in result
//
// The return value from an image loader is an 'unsigned char *' which points
// to the pixel data, or NULL on an allocation failure or if the image is
// corrupt or invalid. The pixel data consists of *y scanlines of *x pixels,
// with each pixel consisting of N interleaved 8-bit components; the first
// pixel pointed to is top-left-most in the image. There is no padding between
// image scanlines or between pixels, regardless of format. The number of
// components N is 'desired_channels' if desired_channels is non-zero, or
// *channels_in_file otherwise. If desired_channels is non-zero,
// *channels_in_file has the number of components that _would_ have been
// output otherwise. E.g. if you set desired_channels to 4, you will always
// get RGBA output, but you can check *channels_in_file to see if it's trivially
// opaque because e.g. there were only 3 channels in the source image.
// 
// An output image with N components has the following components interleaved
// in this order in each pixel:
//
//    N=#comp    components
//      1       grey
//      2       grey, alpha
//      3       red, green, blue
//      4       red, green, blue, alpha
//
// If image loading fails for any reason, the return value will be NULL,
// and *x, *y, *channels_in_file will be unchanged. The function
// koi_failure_reason() can be queried for an extremely brief, end-user
// unfriendly explanation of why the load failed. Define KOI_NO_FAILURE_STRINGS
// to avoid compiling these strings at all, and KOI_FAILURE_USERMSG to get slightly
// more user-friendly ones.
//
// To query the width, height and component count of an image without having to
// decode the full file, you can use the koi_info family of functions:
//
//   int x,y,n,ok;
//   ok = koi_info(filename, &x, &y, &n);
//   // returns ok=1 and sets x, y, n if image is a supported format,
//   // 0 otherwise.
//
// Note that koi_image pervasively uses ints in its public API for sizes,
// including sizes of memory buffers. This is now part of the API and thus
// hard to change without causing breakage. As a result, the various image
// loaders all have certain limits on image size; these differ somewhat
// by format but generally boil down to either just under 2GB or just under
// 1GB. When the decoded image would be larger than this, koi_image decoding
// will fail.
//
// Additionally, koi_image will reject image files that have any of their
// dimensions set to a larger value than the configurable KOI_MAX_DIMENSIONS,
// which defaults to 2**24 = 16777216 pixels. Due to the above memory limit,
// the only way to have an image with such dimensions load correctly
// is for it to have a rather extreme aspect ratio. Either way, the
// assumption here is that such larger images are likely to be malformed
// or malicious. If you do need to load an image with individual dimensions
// larger than that, and it still fits in the overall size limit, you can
// #define KOI_MAX_DIMENSIONS on your own to be something larger.
//
// ===========================================================================
//
// UNICODE
//
//   If compiling for Windows and you wish to use Unicode filenames, compile
//   with
//      #define KOI_WINDOWS_UTF8
//   and pass utf8-encoded filenames. Call koi_convert_wchar_to_utf8 to convert
//   Windows wchar_t filenames to utf8.
//
// ===========================================================================
//
// PHILOSOPHY
//
// koi libraries are designed with the following priorities:
//
//   1. easy to use
//   2. easy to maintain
//   3. good performance
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
//   - Portable ("ease of use")
//   - Small source code footprint ("easy to maintain")
//   - No dependencies ("ease of use")
//
// ===========================================================================
//
// I/O CALLBACKS
//
// I/O callbacks allow you to read from arbitrary sources, like packaged
// files or some other source. Data read from callbacks are processed
// through a small internal buffer (currently 128 bytes) to try to reduce
// overhead.
//
// The three functions you must define are "read" (reads some bytes of data),
// "skip" (skips some bytes of data).
//
// ===========================================================================
//
// ADDITIONAL CONFIGURATION
//
//  - You can suppress implementation of any of the decoders to reduce
//   your code footprint by #defining one or more of the following
//   symbols before creating the implementation.
//
//      KOI_NO_QOI
//
//  - You can request *only* certain decoders and suppress all other ones
//   (this will be more forward-compatible, as addition of new decoders
//   doesn't require you to disable them explicitly):
//
//      KOI_ONLY_QOI
//
//  - You can suppress implementation of any koi_loadf function to reduce
//   your code footprint by #defining KOI_NO_LINEAR before creating
//   the implementation.
//
//  - If you define KOI_MAX_DIMENSIONS, koi_image will reject images greater
//   than that size (in either width or height) without further processing.
//   This is to let programs in the wild set an upper bound to prevent
//   denial-of-service attacks on untrusted data, as one could generate a
//   valid image of gigantic dimensions and force koi_image to allocate a
//   huge block of memory and spend disproportionate time decoding it. By
//   default this is set to (1 << 24), which is 16777216, but that's still
//   very big.

#if !defined(KOI_NO_STDIO)
#include <stdio.h>
#endif // KOI_NO_STDIO

#define KOI_IMAGE_VERSION 2

enum
{
   KOI_default    = 0, // only used for desired_channels

   KOI_grey       = 1,
   KOI_grey_alpha = 2,
   KOI_rgb        = 3,
   KOI_rgb_alpha  = 4
};

#include <stdlib.h>
typedef unsigned char koi_uc;
typedef unsigned short koi_us;

#if defined(__cplusplus)
extern "C" {
#endif

#if !defined(KOIDEF)
   #if defined(KOI_IMAGE_STATIC)
      #define KOIDEF static
   #else
      #define KOIDEF extern
   #endif
#endif

//////////////////////////////////////////////////////////////////////////////
//
// PRIMARY API - works on images of any type
//

//
// load image by filename, open file, or memory buffer
//

typedef struct
{
   int     (*read)  (void *user, char *data, int size);  // fill 'data' with 'size' bytes.  return number of bytes actually read
   void    (*skip)  (void *user, int n);                 // skip the next 'n' bytes, or 'unget' the last -n bytes if negative
} koi_io_callbacks;

////////////////////////////////////
//
// 8-bits-per-channel interface
//

KOIDEF koi_uc *koi_load_from_memory    (koi_uc const *buffer, int len, int *x, int *y, int *channels_in_file, int desired_channels);
KOIDEF koi_uc *koi_load_from_callbacks (koi_io_callbacks const *clbk, void *user, int *x, int *y, int *channels_in_file, int desired_channels);

#if !defined(KOI_NO_STDIO)
KOIDEF koi_uc *koi_load                (char const *filename, int *x, int *y, int *channels_in_file, int desired_channels);
KOIDEF koi_uc *koi_load_from_file      (FILE *f, int *x, int *y, int *channels_in_file, int desired_channels);
// for koi_load_from_file, file pointer is left pointing immediately after image
#endif

#if defined(KOI_WINDOWS_UTF8)
KOIDEF int koi_convert_wchar_to_utf8   (char *buffer, size_t bufferlen, const wchar_t *input);
#endif

////////////////////////////////////
//
// 16-bits-per-channel interface
//

KOIDEF koi_us *koi_load_16_from_memory    (koi_uc const *buffer, int len, int *x, int *y, int *channels_in_file, int desired_channels);
KOIDEF koi_us *koi_load_16_from_callbacks (koi_io_callbacks const *clbk, void *user, int *x, int *y, int *channels_in_file, int desired_channels);

#if !defined(STBI_NO_STDIO)
KOIDEF koi_us *koi_load_16                (char const *filename, int *x, int *y, int *channels_in_file, int desired_channels);
KOIDEF koi_us *koi_load_from_file_16      (FILE *f, int *x, int *y, int *channels_in_file, int desired_channels);
#endif

////////////////////////////////////
//
// float-per-channel interface
//
#if !defined(KOI_NO_LINEAR)
   KOIDEF float *koi_loadf_from_memory    (koi_uc const *buffer, int len, int *x, int *y, int *channels_in_file, int desired_channels);
   KOIDEF float *koi_loadf_from_callbacks (koi_io_callbacks const *clbk, void *user, int *x, int *y,  int *channels_in_file, int desired_channels);

   #if !defined(KOI_NO_STDIO)
   KOIDEF float *koi_loadf                (char const *filename, int *x, int *y, int *channels_in_file, int desired_channels);
   KOIDEF float *koi_loadf_from_file      (FILE *f, int *x, int *y, int *channels_in_file, int desired_channels);
   #endif

   KOIDEF void   koi_ldr_to_hdr_gamma(float gamma);
   KOIDEF void   koi_ldr_to_hdr_scale(float scale);
#endif // KOI_NO_LINEAR

// get a VERY brief reason for failure
// on most compilers (and ALL modern mainstream compilers) this is threadsafe
KOIDEF const char *koi_failure_reason        (void);

// free the loaded image -- this is just free()
KOIDEF void        koi_image_free            (void *retval_from_koi_load);

// get image dimensions & components without fully decoding
KOIDEF int         koi_info_from_memory      (koi_uc const *buffer, int len, int *x, int *y, int *comp);
KOIDEF int         koi_info_from_callbacks   (koi_io_callbacks const *clbk, void *user, int *x, int *y, int *comp);

#if !defined(KOI_NO_STDIO)
KOIDEF int         koi_info                  (char const *filename, int *x, int *y, int *comp);
KOIDEF int         koi_info_from_file        (FILE *f, int *x, int *y, int *comp);
#endif

// flip the image vertically, so the first pixel in the output array is the bottom left
KOIDEF void koi_set_flip_vertically_on_load(int flag_true_if_should_flip);

// as above, but only applies to images loaded on the thread that calls the function
// this function is only available if your compiler supports thread-local variables;
// calling it will fail to link if your compiler doesn't
KOIDEF void koi_set_flip_vertically_on_load_thread(int flag_true_if_should_flip);

#if defined(__cplusplus)
}
#endif

//
//
////   end header file   /////////////////////////////////////////////////////
#endif // KOI_INCLUDE_KOI_IMAGE_H

#if defined(KOI_IMAGE_IMPLEMENTATION)

#if defined(KOI_ONLY_QOI)
   #if !defined(KOI_ONLY_QOI)
      #define KOI_NO_QOI
   #endif
#endif

#include <string.h>

#if !defined(KOI_NO_LINEAR)
#include <math.h>  // ldexp, pow
#endif

#if !defined(KOI_NO_STDIO)
#include <stdio.h>
#endif

#if !defined(KOI_ASSERT)
#include <assert.h>
   #define KOI_ASSERT(x) assert(x)
#endif

#if defined(__cplusplus)
   #define KOI_EXTERN extern "C"
#else
   #define KOI_EXTERN extern
#endif

#if !defined(_MSC_VER)
   #if defined(__cplusplus)
      #define koi_inline inline
   #else
      #define koi_inline
   #endif
#else
   #define koi_inline __forceinline
#endif

#if !defined(KOI_NO_THREAD_LOCALS)
   #if defined(__cplusplus) &&  __cplusplus >= 201103L
      #define KOI_THREAD_LOCAL      thread_local
   #elif defined(__GNUC__) && __GNUC__ < 5
      #define KOI_THREAD_LOCAL      __thread
   #elif defined(_MSC_VER)
      #define KOI_THREAD_LOCAL      __declspec(thread)
   #elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L && !defined(__STDC_NO_THREADS__)
      #define KOI_THREAD_LOCAL      _Thread_local
   #endif

   #if !defined(KOI_THREAD_LOCAL)
      #if defined(__GNUC__)
         #define KOI_THREAD_LOCAL   __thread
      #endif
   #endif
#endif

#if defined(_MSC_VER) || defined(__SYMBIAN32__)
typedef unsigned short koi__uint16;
typedef unsigned int   koi__uint32;
typedef   signed int   koi__int32;
#else
#include <stdint.h>
typedef uint16_t       koi__uint16;
typedef uint32_t       koi__uint32;
typedef int32_t        koi__int32;
#endif

// should produce compiler error if size is wrong
typedef unsigned char koi_validate_uint32[sizeof(koi__uint32) == 4 ? 1 : -1];

#if defined(_MSC_VER)
   #define KOI_NOTUSED(v)  (void)(v)
#else
   #define KOI_NOTUSED(v)  (void)sizeof(v)
#endif

#if defined(KOI_MALLOC) && defined(KOI_FREE)
// ok
#elif !defined(KOI_MALLOC) && !defined(KOI_FREE)
// ok
#else
   #error "Must define all or none of KOI_MALLOC and KOI_FREE"
#endif

#if !defined(KOI_MALLOC)
   #define KOI_MALLOC(sz)     malloc(sz)
   #define KOI_FREE(p)        free(p)
#endif

#if !defined(KOI_MAX_DIMENSIONS)
   #define KOI_MAX_DIMENSIONS (1 << 24)
#endif

///////////////////////////////////////////////
//
//  koi__context struct and start_xxx functions

// koi__context structure is our basic context used by all images, so it
// contains all the IO context, plus some basic image information
typedef struct
{
   koi__uint32 img_x, img_y;
   int img_n, img_out_n;

   koi_io_callbacks io;
   void *io_user_data;

   int read_from_callbacks;
   int buflen;
   koi_uc buffer_start[128];
   int callback_already_read;

   koi_uc *img_buffer, *img_buffer_end;
   koi_uc *img_buffer_original, *img_buffer_original_end;
} koi__context;

static void koi__refill_buffer(koi__context *s);

// initialize a memory-decode context
static void koi__start_mem(koi__context *s, koi_uc const *buffer, int len)
{
   s->io.read = NULL;
   s->read_from_callbacks = 0;
   s->callback_already_read = 0;
   s->img_buffer = s->img_buffer_original = (koi_uc*)buffer;
   s->img_buffer_end = s->img_buffer_original_end = (koi_uc*)buffer + len;
}

// initialize a callback-based context
static void koi__start_callbacks(koi__context *s, koi_io_callbacks *c, void *user)
{
   s->io = *c;
   s->io_user_data = user;
   s->buflen = sizeof(s->buffer_start);
   s->read_from_callbacks = 1;
   s->callback_already_read = 0;
   s->img_buffer = s->img_buffer_original = s->buffer_start;
   koi__refill_buffer(s);
   s->img_buffer_original_end = s->img_buffer_end;
}

#if !defined(KOI_NO_STDIO)
static int koi__stdio_read(void *user, char *data, int size)
{
   return (int)fread(data, 1, size, (FILE*)user);
}

static void koi__stdio_skip(void *user, int n)
{
   int ch;
   fseek((FILE*)user, n, SEEK_CUR);
   ch = fgetc((FILE*)user);      /* have to read a byte to reset feof()'s flag */
   if (ch != EOF) {
      ungetc(ch, (FILE*)user);   /* push byte back onto stream if valid. */
   }
}

static koi_io_callbacks koi__stdio_callbacks =
{
   koi__stdio_read,
   koi__stdio_skip,
};

static void koi__start_file(koi__context *s, FILE *f)
{
   koi__start_callbacks(s, &koi__stdio_callbacks, (void*)f);
}

#endif // !KOI_NO_STDIO

static void koi__rewind(koi__context *s)
{
   // conceptually rewind SHOULD rewind to the beginning of the stream,
   // but we just rewind to the beginning of the initial buffer, because
   // we only use it after doing 'test', which only ever looks at at most 92 bytes
   s->img_buffer = s->img_buffer_original;
   s->img_buffer_end = s->img_buffer_original_end;
}

typedef struct
{
   int bits_per_channel;
   int num_channels;
} koi__result_info;

#if !defined(KOI_NO_QOI)
static int     koi__qoi_test(koi__context *s);
static void   *koi__qoi_load(koi__context *s, int *x, int *y, int *comp, int req_comp, koi__result_info *ri);
static int     koi__qoi_info(koi__context *s, int *x, int *y, int *comp);
#endif

static
#if defined(KOI_THREAD_LOCAL)
KOI_THREAD_LOCAL
#endif
const char *koi__g_failure_reason;

KOIDEF const char *koi_failure_reason(void)
{
   return koi__g_failure_reason;
}

#if !defined(KOI_NO_FAILURE_STRINGS)
static int koi__err(const char *str)
{
   koi__g_failure_reason = str;
   return 0;
}
#endif

static void *koi__malloc(size_t size)
{
   return KOI_MALLOC(size);
}

// koi_image uses ints pervasively, including for offset calculations.
// therefore the largest decoded image size we can support with the
// current code, even on 64-bit targets, is INT_MAX. this is not a
// significant limitation for the intended use case.
//
// we do, however, need to make sure our size calculations don't
// overflow. hence a few helper functions for size calculations that
// multiply integers together, making sure that they're non-negative
// and no overflow occurs.

// return 1 if the sum is valid, 0 on overflow.
// negative terms are considered invalid.
static int koi__addsizes_valid(int a, int b)
{
   if (b < 0) return 0;
   // now 0 <= b <= INT_MAX, hence also
   // 0 <= INT_MAX - b <= INTMAX.
   // And "a + b <= INT_MAX" (which might overflow) is the
   // same as a <= INT_MAX - b (no overflow)
   return a <= INT_MAX - b;
}

// returns 1 if the product is valid, 0 on overflow.
// negative factors are considered invalid.
static int koi__mul2sizes_valid(int a, int b)
{
   if (a < 0 || b < 0) return 0;
   if (b == 0) return 1; // mul-by-0 is always safe
   // portable way to check for no overflows in a*b
   return a <= INT_MAX / b;
}

// returns 1 if "a*b*c + add" has no negative terms/factors and doesn't overflow
static int koi__mad3sizes_valid(int a, int b, int c, int add)
{
   return koi__mul2sizes_valid(a, b) && koi__mul2sizes_valid(a * b, c) &&
      koi__addsizes_valid(a * b * c, add);
}

// returns 1 if "a*b*c*d + add" has no negative terms/factors and doesn't overflow
#if !defined(KOI_NO_LINEAR)
static int koi__mad4sizes_valid(int a, int b, int c, int d, int add)
{
   return koi__mul2sizes_valid(a, b) && koi__mul2sizes_valid(a * b, c) &&
      koi__mul2sizes_valid(a * b * c, d) && koi__addsizes_valid(a * b * c * d, add);
}
#endif

static void *koi__malloc_mad3(int a, int b, int c, int add)
{
   if (!koi__mad3sizes_valid(a, b, c, add)) return NULL;
   return koi__malloc((size_t)a * b * c + add);
}

#if !defined(KOI_NO_LINEAR)
static void *koi__malloc_mad4(int a, int b, int c, int d, int add)
{
   if (!koi__mad4sizes_valid(a, b, c, d, add)) return NULL;
   return koi__malloc((size_t)a * b * c * d + add);
}
#endif

// koi__err - error
// koi__errpf - error returning pointer to float
// koi__errpuc - error returning pointer to unsigned char

#if defined(KOI_NO_FAILURE_STRINGS)
   #define koi__err(x,y)  0
#elif defined(KOI_FAILURE_USERMSG)
   #define koi__err(x,y)  koi__err(y)
#else
   #define koi__err(x,y)  koi__err(x)
#endif

#define koi__errpf(x,y)   ((float*)(size_t)(koi__err(x,y) ? NULL : NULL))
#define koi__errpuc(x,y)  ((unsigned char*)(size_t)(koi__err(x,y) ? NULL : NULL))

KOIDEF void koi_image_free(void *retval_from_koi_load)
{
   KOI_FREE(retval_from_koi_load);
}

#if !defined(KOI_NO_LINEAR)
static float *koi__ldr_to_hdr(koi_uc *data, int x, int y, int comp);
#endif

static int koi__vertically_flip_on_load_global = 0;

KOIDEF void koi_set_flip_vertically_on_load(int flag_true_if_should_flip)
{
   koi__vertically_flip_on_load_global = flag_true_if_should_flip;
}

#if !defined(KOI_THREAD_LOCAL)
   #define koi__vertically_flip_on_load  koi__vertically_flip_on_load_global
#else
static KOI_THREAD_LOCAL int koi__vertically_flip_on_load_local, koi__vertically_flip_on_load_set;

KOIDEF void koi_set_flip_vertically_on_load_thread(int flag_true_if_should_flip)
{
   koi__vertically_flip_on_load_local = flag_true_if_should_flip;
   koi__vertically_flip_on_load_set = 1;
}

#define koi__vertically_flip_on_load  (koi__vertically_flip_on_load_set \
                         ? koi__vertically_flip_on_load_local \
                         : koi__vertically_flip_on_load_global)
#endif // KOI_THREAD_LOCAL

static void *koi__load_main(koi__context *s, int *x, int *y, int *comp, int req_comp, koi__result_info *ri)
{
   memset(ri, 0, sizeof(*ri)); // make sure it's initialized if we add new fields
   ri->bits_per_channel = 8; // default is 8 so most paths don't have to be changed
   ri->num_channels = 0;

   #if !defined(KOI_NO_QOI)
   if (koi__qoi_test(s)) return koi__qoi_load(s, x, y, comp, req_comp, ri);
   #endif

   return koi__errpuc("unknown image type", "Image not of any known type, or corrupt");
}

static koi__uint16 *koi__convert_8_to_16(koi_uc *orig, int w, int h, int channels)
{
   int i;
   int img_len;
   koi__uint16 *enlarged;

   enlarged = (koi__uint16*)koi__malloc_mad4(w, h, channels, 2, 0);
   if (enlarged == NULL) {
       KOI_FREE(orig);
       return (koi__uint16*)koi__errpuc("outofmem", "Out of memory");
   }

   img_len = w * h * channels;
   for (i = 0; i < img_len; ++i)
     enlarged[i] = (koi__uint16)((orig[i] << 8) + orig[i]); // replicate to high and low byte, maps 0->0, 255->0xffff

   KOI_FREE(orig);
   return enlarged;
}

static void koi__vertical_flip(void *image, int w, int h, int bytes_per_pixel)
{
   int row;
   size_t bytes_per_row = (size_t)w * bytes_per_pixel;
   koi_uc temp[2048];
   koi_uc *bytes = (koi_uc*)image;

   for (row = 0; row < (h >> 1); row++) {
      koi_uc *row0 = bytes + row * bytes_per_row;
      koi_uc *row1 = bytes + (size_t)(h - row - 1) * bytes_per_row;
      // swap row0 with row1
      size_t bytes_left = bytes_per_row;
      while (bytes_left) {
         size_t bytes_copy = (bytes_left < sizeof(temp)) ? bytes_left : sizeof(temp);
         memcpy(temp, row0, bytes_copy);
         memcpy(row0, row1, bytes_copy);
         memcpy(row1, temp, bytes_copy);
         row0 += bytes_copy;
         row1 += bytes_copy;
         bytes_left -= bytes_copy;
      }
   }
}

static unsigned char *koi__load_and_postprocess_8bit(koi__context *s, int *x, int *y, int *comp, int req_comp)
{
   koi__result_info ri;
   void *result = koi__load_main(s, x, y, comp, req_comp, &ri);

   if (result == NULL)
      return NULL;

   // it is the responsibility of the loaders to make sure we get 8 bit.
   KOI_ASSERT(ri.bits_per_channel == 8);

   if (koi__vertically_flip_on_load) {
      int channels = req_comp ? req_comp : *comp;
      koi__vertical_flip(result, *x, *y, channels * sizeof(koi_uc));
   }

   return (unsigned char*)result;
}

static koi__uint16 *koi__load_and_postprocess_16bit(koi__context *s, int *x, int *y, int *comp, int req_comp)
{
   koi__result_info ri;
   void *result = koi__load_main(s, x, y, comp, req_comp, &ri);

   if (result == NULL)
      return NULL;

   // it is the responsibility of the loaders to make sure we get either 8 or 16 bit.
   KOI_ASSERT(ri.bits_per_channel == 8 || ri.bits_per_channel == 16);

   if (ri.bits_per_channel != 16) {
      result = koi__convert_8_to_16((koi_uc*)result, *x, *y, req_comp == 0 ? *comp : req_comp);
      ri.bits_per_channel = 16;
   }

   if (koi__vertically_flip_on_load) {
      int channels = req_comp ? req_comp : *comp;
      koi__vertical_flip(result, *x, *y, channels * sizeof(koi__uint16));
   }

   return (koi__uint16*)result;
}

#if defined(KOI_NO_LINEAR)
static void koi__float_postprocess(float *result, int *x, int *y, int *comp, int req_comp)
{
   if (koi__vertically_flip_on_load && result != NULL) {
      int channels = req_comp ? req_comp : *comp;
      koi__vertical_flip(result, *x, *y, channels * sizeof(float));
   }
}
#endif

#if !defined(KOI_NO_STDIO)

#if defined(_WIN32) && defined(KOI_WINDOWS_UTF8)
KOI_EXTERN __declspec(dllimport) int __stdcall MultiByteToWideChar(unsigned int cp, unsigned long flags, const char *str, int cbmb, wchar_t *widestr, int cchwide);
KOI_EXTERN __declspec(dllimport) int __stdcall WideCharToMultiByte(unsigned int cp, unsigned long flags, const wchar_t *widestr, int cchwide, char *str, int cbmb, const char *defchar, int *used_default);

KOIDEF int koi_convert_wchar_to_utf8(char *buffer, size_t bufferlen, const wchar_t *input)
{
   int len = (bufferlen > 0x7FFFFFFF) ? 0x7FFFFFFF : (int)bufferlen;
   return WideCharToMultiByte(65001 /* UTF8 */, 0, input, -1, buffer, len, NULL, NULL);
}
#endif

static FILE *koi__fopen(char const *filename, char const *mode)
{
   FILE *f;
#if defined(_WIN32) && defined(KOI_WINDOWS_UTF8)
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

KOIDEF koi_uc *koi_load(char const *filename, int *x, int *y, int *comp, int req_comp)
{
   FILE *f = koi__fopen(filename, "rb");
   unsigned char *result;
   if (f == NULL) return koi__errpuc("can't fopen", "Unable to open file");
   result = koi_load_from_file(f, x, y, comp, req_comp);
   fclose(f);
   return result;
}

KOIDEF koi_uc *koi_load_from_file(FILE *f, int *x, int *y, int *comp, int req_comp)
{
   unsigned char *result;
   koi__context s;
   koi__start_file(&s, f);
   result = koi__load_and_postprocess_8bit(&s, x, y, comp, req_comp);
   if (result) {
      // need to 'unget' all the characters in the IO buffer
      fseek(f, -(int)(s.img_buffer_end - s.img_buffer), SEEK_CUR);
   }
   return result;
}

KOIDEF koi__uint16 *koi_load_from_file_16(FILE *f, int *x, int *y, int *comp, int req_comp)
{
   koi__uint16 *result;
   koi__context s;
   koi__start_file(&s, f);
   result = koi__load_and_postprocess_16bit(&s, x, y, comp, req_comp);
   if (result) {
      // need to 'unget' all the characters in the IO buffer
      fseek(f, -(int)(s.img_buffer_end - s.img_buffer), SEEK_CUR);
   }
   return result;
}

KOIDEF koi_us *koi_load_16(char const *filename, int *x, int *y, int *comp, int req_comp)
{
   FILE *f = koi__fopen(filename, "rb");
   koi__uint16 *result;
   if (f == NULL) return (koi_us*)koi__errpuc("can't fopen", "Unable to open file");
   result = koi_load_from_file_16(f, x, y, comp, req_comp);
   fclose(f);
   return result;
}

#endif // !KOI_NO_STDIO

KOIDEF koi_us *koi_load_16_from_memory(koi_uc const *buffer, int len, int *x, int *y, int *channels_in_file, int desired_channels)
{
   koi__context s;
   koi__start_mem(&s, buffer, len);
   return koi__load_and_postprocess_16bit(&s, x, y, channels_in_file, desired_channels);
}

KOIDEF koi_us *koi_load_16_from_callbacks(koi_io_callbacks const *clbk, void *user, int *x, int *y, int *channels_in_file, int desired_channels)
{
   koi__context s;
   koi__start_callbacks(&s, (koi_io_callbacks*)clbk, user);
   return koi__load_and_postprocess_16bit(&s, x, y, channels_in_file, desired_channels);
}

KOIDEF koi_uc *koi_load_from_memory(koi_uc const *buffer, int len, int *x, int *y, int *comp, int req_comp)
{
   koi__context s;
   koi__start_mem(&s, buffer, len);
   return koi__load_and_postprocess_8bit(&s, x, y, comp, req_comp);
}

KOIDEF koi_uc *koi_load_from_callbacks(koi_io_callbacks const *clbk, void *user, int *x, int *y, int *comp, int req_comp)
{
   koi__context s;
   koi__start_callbacks(&s, (koi_io_callbacks*)clbk, user);
   return koi__load_and_postprocess_8bit(&s, x, y, comp, req_comp);
}

#if !defined(KOI_NO_LINEAR)
static float *koi__loadf_main(koi__context *s, int *x, int *y, int *comp, int req_comp)
{
   unsigned char *data;
   data = koi__load_and_postprocess_8bit(s, x, y, comp, req_comp);
   if (data)
      return koi__ldr_to_hdr(data, *x, *y, req_comp ? req_comp : *comp);
   return koi__errpf("unknown image type", "Image not of any known type, or corrupt");
}

KOIDEF float *koi_loadf_from_memory(koi_uc const *buffer, int len, int *x, int *y, int *comp, int req_comp)
{
   koi__context s;
   koi__start_mem(&s,buffer,len);
   return koi__loadf_main(&s, x, y, comp, req_comp);
}

KOIDEF float *koi_loadf_from_callbacks(koi_io_callbacks const *clbk, void *user, int *x, int *y, int *comp, int req_comp)
{
   koi__context s;
   koi__start_callbacks(&s, (koi_io_callbacks*)clbk, user);
   return koi__loadf_main(&s, x, y, comp, req_comp);
}

#if !defined(KOI_NO_STDIO)
KOIDEF float *koi_loadf(char const *filename, int *x, int *y, int *comp, int req_comp)
{
   float *result;
   FILE *f = koi__fopen(filename, "rb");
   if (f == NULL) return koi__errpf("can't fopen", "Unable to open file");
   result = koi_loadf_from_file(f, x, y, comp, req_comp);
   fclose(f);
   return result;
}

KOIDEF float *koi_loadf_from_file(FILE *f, int *x, int *y, int *comp, int req_comp)
{
   koi__context s;
   koi__start_file(&s,f);
   return koi__loadf_main(&s, x, y, comp, req_comp);
}
#endif // !KOI_NO_STDIO

#endif // !KOI_NO_LINEAR

#if !defined(KOI_NO_LINEAR)
static float koi__l2h_gamma = 2.2f, koi__l2h_scale = 1.0f;

KOIDEF void   koi_ldr_to_hdr_gamma(float gamma) { koi__l2h_gamma = gamma; }
KOIDEF void   koi_ldr_to_hdr_scale(float scale) { koi__l2h_scale = scale; }
#endif

//////////////////////////////////////////////////////////////////////////////
//
// Common code used by all image loaders
//

enum
{
   KOI__SCAN_load = 0,
   KOI__SCAN_type,
   KOI__SCAN_header
};

static void koi__refill_buffer(koi__context *s)
{
   int n = (s->io.read)(s->io_user_data, (char*)s->buffer_start, s->buflen);
   s->callback_already_read += (int)(s->img_buffer - s->img_buffer_original);
   if (n == 0) {
      // at end of file, treat same as if from memory, but need to handle case
      // where s->img_buffer isn't pointing to safe memory, e.g. 0-byte file
      s->read_from_callbacks = 0;
      s->img_buffer = s->buffer_start;
      s->img_buffer_end = s->buffer_start + 1;
      *s->img_buffer = 0;
   }
   else {
      s->img_buffer = s->buffer_start;
      s->img_buffer_end = s->buffer_start + n;
   }
}

koi_inline static koi_uc koi__get8(koi__context *s)
{
   if (s->img_buffer < s->img_buffer_end)
      return *s->img_buffer++;
   if (s->read_from_callbacks) {
      koi__refill_buffer(s);
      return *s->img_buffer++;
   }
   return 0;
}

static int koi__get16be(koi__context *s)
{
   int z = koi__get8(s) << 8;
   return z + koi__get8(s);
}

static koi__uint32 koi__get32be(koi__context *s)
{
   koi__uint32 z = koi__get16be(s) << 16;
   z += (koi__uint32)koi__get16be(s);
   return z;
}

static koi_uc koi__compute_y(int r, int g, int b)
{
   return (koi_uc)(((r * 77) + (g * 150) + (29 * b)) >> 8);
}

static unsigned char *koi__convert_format(unsigned char *data, int img_n, int req_comp, unsigned int x, unsigned int y)
{
   int i, j;
   unsigned char *good;

   if (req_comp == img_n) return data;
   KOI_ASSERT(req_comp >= 1 && req_comp <= 4);

   good = (unsigned char*)koi__malloc_mad3(x, y, req_comp, 0);
   if (good == NULL) {
      KOI_FREE(data);
      return koi__errpuc("outofmem", "Out of memory");
   }

   for (j = 0; j < (int)y; ++j) {
      unsigned char *src = data + j * x * img_n;
      unsigned char *dest = good + j * x * req_comp;

#define KOI__COMBO(a, b)  ((a) * 8 + (b))
#define KOI__CASE(a, b)   case KOI__COMBO(a, b): for(i = x - 1; i >= 0; --i, src += a, dest += b)
      // convert source image with img_n components to one with req_comp components;
      // avoid switch per pixel, so use switch per scanline and massive macros
      switch (KOI__COMBO(img_n, req_comp)) {
         KOI__CASE(1, 2) { dest[0] = src[0]; dest[1] = 255; } break;
         KOI__CASE(1, 3) { dest[0] = dest[1] = dest[2] = src[0]; } break;
         KOI__CASE(1, 4) { dest[0] = dest[1] = dest[2] = src[0]; dest[3] = 255; } break;
         KOI__CASE(2, 1) { dest[0] = src[0]; } break;
         KOI__CASE(2, 3) { dest[0] = dest[1] = dest[2] = src[0]; } break;
         KOI__CASE(2, 4) { dest[0] = dest[1] = dest[2] = src[0]; dest[3] = src[1]; } break;
         KOI__CASE(3, 4) { dest[0] = src[0]; dest[1] = src[1]; dest[2] = src[2]; dest[3] = 255; } break;
         KOI__CASE(3, 1) { dest[0] = koi__compute_y(src[0], src[1], src[2]); } break;
         KOI__CASE(3, 2) { dest[0] = koi__compute_y(src[0], src[1], src[2]); dest[1] = 255; } break;
         KOI__CASE(4, 1) { dest[0] = koi__compute_y(src[0], src[1], src[2]); } break;
         KOI__CASE(4, 2) { dest[0] = koi__compute_y(src[0], src[1], src[2]); dest[1] = src[3]; } break;
         KOI__CASE(4, 3) { dest[0] = src[0]; dest[1] = src[1]; dest[2] = src[2]; } break;
         default: KOI_ASSERT(0); KOI_FREE(data); KOI_FREE(good); return koi__errpuc("unsupported", "Unsupported format conversion");
      }
#undef KOI__CASE
#undef KOI__COMBO
   }

   KOI_FREE(data);
   return good;
}

#if !defined(KOI_NO_LINEAR)
static float *koi__ldr_to_hdr(koi_uc *data, int x, int y, int comp)
{
   int i, k, n;
   float *output;
   if (data == NULL) return NULL;
   output = (float*)koi__malloc_mad4(x, y, comp, sizeof(float), 0);
   if (output == NULL) {
       KOI_FREE(data);
       return koi__errpf("outofmem", "Out of memory");
   }
   // compute number of non-alpha components
   if (comp & 1) n = comp; else n = comp - 1;
   for (i = 0; i < x * y; ++i) {
      for (k = 0; k < n; ++k) {
         output[i * comp + k] = (float)(pow(data[i * comp + k] / 255.0f, koi__l2h_gamma) * koi__l2h_scale);
      }
   }
   if (n < comp) {
      for (i = 0; i < x * y; ++i) {
         output[i * comp + n] = data[i * comp + n] / 255.0f;
      }
   }

   KOI_FREE(data);
   return output;
}
#endif

//////////////////////////////////////////////////////////////////////////////
//
//  QOI - The "Quite OK Image Format" decoder
//
#if !defined(KOI_NO_QOI)
static int koi__qoi_test_raw(koi__context *s)
{
   int size = s->img_buffer_original_end - s->img_buffer_original;
   if (size < 14 + 8) return 0; // QOI header size 14 bytes and 8 bytes padding
   if (koi__get8(s) != 'q') return 0;
   if (koi__get8(s) != 'o') return 0;
   if (koi__get8(s) != 'i') return 0;
   if (koi__get8(s) != 'f') return 0;
   return 1;
}

static int koi__qoi_test(koi__context *s)
{
   int r = koi__qoi_test_raw(s);
   koi__rewind(s);
   return r;
}

typedef struct
{
   koi_uc ch_n, cspace;
} koi__qoi_data;

static void *koi__qoi_parse_header(koi__context *s, koi__qoi_data *info)
{
   if (koi__get8(s) != 'q' || koi__get8(s) != 'o' || koi__get8(s) != 'i' || koi__get8(s) != 'f') 
      return koi__errpuc("not QOI", "Corrupt QOI");
   s->img_x = koi__get32be(s);
   s->img_y = koi__get32be(s);

   // 'The colorspace and channel fields are purely informative. They do not change the way data chunks are encoded.'
   // ~ qoi specification Version 1.0
   info->ch_n = koi__get8(s);

   if (info->ch_n != 3 && info->ch_n != 4) return koi__errpuc("QOI CHANNELS", "QOI only support: 4 and 3 channels");

   info->cspace = koi__get8(s);

   if (info->cspace != 0 && info->cspace != 1) return koi__errpuc("QOI COLORSPACE", "QOI only support: 0 and 1 colorspace");

   return (void*)1;
}

typedef struct {
   koi_uc r, g, b, a;
} koi__qoi_pixel;

static void *koi__qoi_load(koi__context *s, int *x, int *y, int *comp, int req_comp, koi__result_info *ri)
{
   koi_uc *out;
   koi__qoi_pixel index[64], prev_px;
   koi__uint32 i, pos, len;
   koi_uc target;
   koi__qoi_data info;
   KOI_NOTUSED(ri);

   if (koi__qoi_parse_header(s, &info) == NULL)
      return NULL; // error code already set

   if (s->img_y > KOI_MAX_DIMENSIONS) return koi__errpuc("too large", "Very large image (corrupt?)");
   if (s->img_x > KOI_MAX_DIMENSIONS) return koi__errpuc("too large", "Very large image (corrupt?)");

   s->img_n = info.ch_n;

   if (req_comp && req_comp >= 3) // we can directly decode 3 or 4
      target = req_comp;
   else
      target = s->img_n;         // if they want monochrome, we'll post-convert

   // sanity-check size
   out = (koi_uc*)koi__malloc_mad3(s->img_x, s->img_y, target, 0);
   if (out == NULL) return koi__errpuc("outofmem", "Out of memory");

   prev_px.r = 0;
   prev_px.g = 0;
   prev_px.b = 0;
   prev_px.a = 255;

   memset(index, 0, sizeof(index));

#define KOI_QOI_COLOR_HASH(px) (px.r * 3 + px.g * 5 + px.b * 7 + px.a * 11)

   len = s->img_y * s->img_x;
   for (i = 0; i < len; ++i) {
      pos = i * target;
      koi_uc tag = koi__get8(s);

      if (tag == 0xfe /*QOI_OP_RGB*/) {
         prev_px.r = koi__get8(s);
         prev_px.g = koi__get8(s);
         prev_px.b = koi__get8(s);
      }
      else if (tag == 0xff /*QOI_OP_RGBA*/) {
         prev_px.r = koi__get8(s);
         prev_px.g = koi__get8(s);
         prev_px.b = koi__get8(s);
         prev_px.a = koi__get8(s);
      }
      else {
         koi_uc t = tag & 0xc0;
         if (t == 0x00 /*QOI_OP_INDEX*/) {
            prev_px = index[tag];
         }
         else if (t == 0x40 /*QOI_OP_DIFF*/) {
            koi_uc d = tag ^ 0x40;
            prev_px.r += ((d >> 4) & 0x03) - 2;
            prev_px.g += ((d >> 2) & 0x03) - 2;
            prev_px.b += ( d       & 0x03) - 2;
         }
         else if (t == 0x80 /*QOI_OP_LUMA*/) {
            koi_uc dg = (tag ^ 0x80) - 32;
            koi_uc d2 = koi__get8(s);
            prev_px.r += dg - 8 + ((d2 >> 4) & 0x0f);
            prev_px.g += dg;
            prev_px.b += dg - 8 + ( d2       & 0x0f);
         }
         else if (t == 0xc0 /*QOI_OP_RUN*/) {
            koi_uc run = (tag ^ 0xc0) + 1;
            index[KOI_QOI_COLOR_HASH(prev_px) & (64 - 1)] = prev_px;
            while (run--) {
               out[pos++] = prev_px.r;
               out[pos++] = prev_px.g;
               out[pos]   = prev_px.b;
               if (target == 4) out[++pos] = prev_px.a;
               if (run > 0) {
                  ++i; ++pos;
               }
            }
            continue;
         }
      }
      
      index[KOI_QOI_COLOR_HASH(prev_px) & (64 - 1)] = prev_px;

      out[pos++] = prev_px.r;
      out[pos++] = prev_px.g;
      out[pos]   = prev_px.b;
      if(target == 4) out[++pos] = prev_px.a;
   }

#undef KOI_QOI_COLOR_HASH
   
   if (req_comp && req_comp != target) {
      out = koi__convert_format(out, target, req_comp, s->img_x, s->img_y);
      if (out == NULL) return out; // koi__convert_format frees input on failure
   }

   *x = s->img_x;
   *y = s->img_y;
   if (comp) *comp = s->img_n;
   return out;
}

static int koi__qoi_info(koi__context *s, int *x, int *y, int *comp)
{
   void *p;
   koi__qoi_data info;

   p = koi__qoi_parse_header(s, &info);
   if (p == NULL) {
      koi__rewind(s);
      return 0;
   }
   if (x) *x = s->img_x;
   if (y) *y = s->img_y;
   if (comp) *comp = info.ch_n;
   return 1;
}
#endif

static int koi__info_main(koi__context *s, int *x, int *y, int *comp)
{
   #if !defined(KOI_NO_QOI)
   if (koi__qoi_info(s, x, y, comp)) return 1;
   #endif

   return koi__err("unknown image type", "Image not of any known type, or corrupt");
}

#if !defined(KOI_NO_STDIO)
KOIDEF int koi_info(char const *filename, int *x, int *y, int *comp)
{
   FILE *f = koi__fopen(filename, "rb");
   int result;
   if (f == NULL) return koi__err("can't fopen", "Unable to open file");
   result = koi_info_from_file(f, x, y, comp);
   fclose(f);
   return result;
}

KOIDEF int koi_info_from_file(FILE *f, int *x, int *y, int *comp)
{
   int r;
   koi__context s;
   long pos = ftell(f);
   koi__start_file(&s, f);
   r = koi__info_main(&s, x, y, comp);
   fseek(f, pos, SEEK_SET);
   return r;
}
#endif // !KOI_NO_STDIO

KOIDEF int koi_info_from_memory(koi_uc const *buffer, int len, int *x, int *y, int *comp)
{
   koi__context s;
   koi__start_mem(&s, buffer, len);
   return koi__info_main(&s, x, y, comp);
}

KOIDEF int koi_info_from_callbacks(koi_io_callbacks const *c, void *user, int *x, int *y, int *comp)
{
   koi__context s;
   koi__start_callbacks(&s, (koi_io_callbacks*)c, user);
   return koi__info_main(&s, x, y, comp);
}

#endif // KOI_IMAGE_IMPLEMENTATION

/*
   revision history:
      1.02  (2026-04-30) Improved memory safety and made Windows file handling more robust
      1.01  (2025-11-20) Unified formatting of functions and tabs
      1.00  (2025-05-09) QOI file loader
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