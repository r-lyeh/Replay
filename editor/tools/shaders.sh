#!/bin/sh
# shaders.sh - editor/shaders/*.vert, *.frag (GLSL 450) -> checked-in headers (docs/3D.md 9.2):
#   SPIR-V (Vulkan): glslangValidator      MSL (Metal): spirv-cross, from the SPIR-V
# DXIL (D3D12) is editor/tools/shaders.bat's (DXC, the Windows SDK). Run from the repo's root:
#   sh editor/tools/shaders.sh        (apt-get install glslang-tools spirv-cross)
# Variants: mesh.vert again with SKIN defined -> mesh_skin_vert.h (skinned on the GPU).
set -e
cd "$(dirname "$0")/../shaders"
build() {   # source, header name, glslang's extra arguments
  src=$1; name=$2; shift 2
  glslangValidator -V "$@" "$src" -o "$name.spv" > /dev/null
  spirv-cross "$name.spv" --msl --msl-version 20000 --msl-decoration-binding --output "$name.msl"   # (the bindings as SDL_gpu numbers them: texture(n) / buffer(n) = binding n, not the order of use)
  {
    echo "// $name.h - made by editor/tools/shaders.sh from $src${*:+ ($*)}: don't edit (edit $src, run it again)"
    printf "static const unsigned char %s_spv[] = {\n" "$name"
    od -An -v -tx1 "$name.spv" | sed 's/ *\([0-9a-f][0-9a-f]\)/0x\1,/g'
    echo "};"
    printf "static const char %s_msl[] =\n" "$name"
    sed 's/\\/\\\\/g; s/"/\\"/g; s/^/  "/; s/$/\\n"/' "$name.msl"
    echo ";"
  } > "$name.h"
  rm -f "$name.spv" "$name.msl"
  echo "editor/shaders/$name.h"
}
for src in *.vert *.frag; do build "$src" "$(echo "$src" | tr '.' '_')"; done
build mesh.vert mesh_skin_vert -DSKIN
