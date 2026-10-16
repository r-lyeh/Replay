-- types.lua: the content browser's kinds of files, their colours (after UE5's
-- Content Browser: textures red, static meshes cyan, skeletal meshes pink,
-- materials green, sounds purple, scripts blue as Blueprints, levels orange...)
-- and the extensions each takes. The first that lists an extension wins; the
-- last ones have none (found otherwise). Edit it in the tree
-- (/plugins/content: types) and Save, or here.
return {
  { key = "texture",   name = "Texture",         color = { 192, 64, 64 },   exts = { "png", "jpg", "jpeg", "bmp", "tga", "gif", "qoi", "webp", "pug", "psd", "hdr" } },
  { key = "mesh",      name = "Static Mesh",     color = { 0, 255, 255 },   exts = { "glb", "gltf", "fbx", "vox", "obj", "iqm" } },
  { key = "anim",      name = "Animation",       color = { 80, 123, 72 },   exts = { "anim", "ase", "aseprite" } },
  { key = "material",  name = "Material",        color = { 64, 192, 64 },   exts = { "mat" } },
  { key = "sound",     name = "Sound Wave",      color = { 97, 85, 212 },   exts = { "wav", "ogg", "mp3", "flac" } },
  { key = "cue",       name = "Sound Cue",       color = { 0, 175, 255 },   exts = { "sfx", "soundgraph" } },
  { key = "code",      name = "Script",          color = { 63, 126, 255 },  exts = { "lua", "tl", "hurdy", "c", "h", "py", "sh", "bat" } },
  { key = "particles", name = "Particle System", color = { 255, 255, 255 }, exts = { "pfx", "bullets", "flock" } },
  { key = "map",       name = "Level",           color = { 255, 156, 0 },   exts = { "tmap", "tmx", "terrain", "dungeon" } },
  { key = "data",      name = "Data Table",      color = { 62, 140, 35 },   exts = { "atlas.lua", "json", "csv", "loc", "po", "options", "dialog", "toml", "ini", "xml" } },
  { key = "font",      name = "Font",            color = { 128, 128, 64 },  exts = { "ttf", "otf", "fnt" } },
  { key = "doc",       name = "Document",        color = { 160, 160, 170 }, exts = { "md", "txt", "license", "pdf", "html" } },
  { key = "skeletal",  name = "Skeletal Mesh",   color = { 255, 0, 255 } },   -- (a mesh with a skeleton: known once its thumbnail is drawn)
  { key = "game",      name = "Game",            color = { 255, 156, 0 } },   -- (a folder that is a game: UE's World orange)
  { key = "folder",    name = "Folder",          color = { 200, 160, 90 } },
  { key = "other",     name = "File",            color = { 110, 110, 120 } },
}
