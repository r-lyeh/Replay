# modelview

A model viewer: glTF 2.0 files (`.gltf`, `.glb`) open in a Lite tab.

- LMB drag: orbit. MMB (or SHIFT + LMB) drag: pan. The wheel: zoom.
- Double-click or F: fit. G: a floor under the model, S: the sun's shadows
  (both on at first).
- A skinned model: its joints and clips; the first clip plays at once. Pick a
  clip, Play / Pause (SPACE), scrub its time, or Rest pose.
- Blend shapes (face expressions): a slider each, over what the clip sets; From
  the clip gives them back. Right-click: Front / Side / Top, Reload.
- The panel: vertices, triangles, size in meters, its parts (triangles, colour,
  texture) and its textures (sizes).
- The file is read again when it changes on disk.

The 3D isn't drawn by Lite: the tab leaves a hole in Lite's picture
(`renderer.clear_rect`) and asks the host to draw the model under it
(`host_view3d`, `host_model_info`: editor.h). The GPU draws it (SDL_gpu), or the
CPU rasterizer when there's none (`REPLAY_3D=cpu`). See docs/3D.md, phase 7.

- `files.lua`: which extensions open here
- `editor.lua`: the viewer (runs in Lite)

Keys (Alt+ letter: letters alone are the fly camera's): Alt+F fit, Alt+G floor,
Alt+S shadows, Alt+M the model, Alt+O its outline (off at first), Alt+K skeleton,
Alt+W wireframe, Alt+N normals, SPACE play / pause. RMB held in the picture: fly
(the mouse looks, W A S D Q E move, C as Q, Shift faster); a right-click without moving: the
menu. Clips: a click plays one, faded in (Blend, 0.25 s); + adds it to the Sequence
(clips and pauses in order, Loop).

## Camera and Benchmark

- **Camera** (right panel): field of view (10..120 degrees), near and far planes (m), until the depth is reversed-z.
- **Benchmark**: *Copies* puts the model that many times on a grid round it (rings outwards, the floor grown to
  fit), the camera backed off to see them. An animated model plays its clip (the first, if none was picked), each
  copy from its own time (64 poses at most, shared round, skinned on the GPU). Over the picture: copies drawn / in
  all (culled: out of view), triangles, draw calls, the CPU's ms to draw it, frames a second. The GPU's own time
  isn't shown: SDL_gpu has no timer queries. *Levels of detail* (on at first): copies 5, 12 and 30 radii away drawn simpler
  (mesh3d_lod's copies): the triangles they save, the time; *Tint the levels* (off at first) colours them by level
  (green, yellow, orange). *Stats* (on at first): the numbers over the picture, one copy or many. host: `host_view3d{ copies =, near =, far =, fov = }`,
  `host_view3d_stats(key)`.
