// gpu.h - the window's renderer on SDL_gpu (docs/3D.md, phase 1). Part of
// replay.c: included once, before main.
//
// The 2D drawing (render.h, the editor, lite's texture) is SDL's renderer, as
// always; what changes is under it: SDL_CreateGPURenderer runs it on an
// SDL_gpu device of ours (Vulkan, D3D12, Metal), which the 3D passes will
// share (g_gpu). No GPU (or --gpu off, or its renderer fails): SDL's own
// renderer, as before, and g_gpu stays NULL (3D then draws on the CPU).
//   --gpu auto | off | vulkan | direct3d12 | metal     (default auto)
#pragma once

static SDL_GPUDevice *g_gpu;                       // the device the renderer runs on (NULL: none)
static char g_gpu_arg[32] = "auto";
// the shader formats the 3D passes ship (editor/shaders: precompiled, checked in;
// docs/3D.md 9.2): SPIR-V and MSL. DXIL joins when editor/tools/shaders.bat makes it
// (DXC: Windows SDK); until then Windows runs on Vulkan, never D3D12 without shaders.
#define GPU_SHADER_FORMATS (SDL_GPU_SHADERFORMAT_SPIRV | SDL_GPU_SHADERFORMAT_MSL)

static SDL_Renderer *gpu_create_renderer(SDL_Window *win) {
  if (SDL_strcmp(g_gpu_arg, "off")) {
    if (SDL_strcmp(g_gpu_arg, "auto")) SDL_SetHint(SDL_HINT_GPU_DRIVER, g_gpu_arg);   // (a backend asked for)
    g_gpu = SDL_CreateGPUDevice(GPU_SHADER_FORMATS, false, NULL);
    if (g_gpu) {
      SDL_Renderer *r = SDL_CreateGPURenderer(g_gpu, win);
      if (r) return r;
      SDL_Log("gpu: its renderer failed (%s): SDL's own renderer instead", SDL_GetError());
      SDL_DestroyGPUDevice(g_gpu);
      g_gpu = NULL;
    } else if (SDL_strcmp(g_gpu_arg, "auto")) SDL_Log("gpu: no %s device (%s): SDL's own renderer instead", g_gpu_arg, SDL_GetError());
  }
  return SDL_CreateRenderer(win, NULL);
}
static const char *gpu_driver(void) { return g_gpu ? SDL_GetGPUDeviceDriver(g_gpu) : "none"; }
static void (*g_gpu_release)(void);                // (render3d.h: its buffers, textures, pipeline: before the device goes)
static void gpu_shutdown(SDL_Renderer *r) {        // (the renderer first: it uses the device)
  if (g_gpu && g_gpu_release) g_gpu_release();
  if (r) SDL_DestroyRenderer(r);
  if (g_gpu) { SDL_DestroyGPUDevice(g_gpu); g_gpu = NULL; }
}
