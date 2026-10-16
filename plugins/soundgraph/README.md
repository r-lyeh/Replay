# soundgraph

A sound effect editor where a sound is a node graph: `.soundgraph` files. Tones,
noise, envelopes, slides and LFOs go through filters, echoes, a reverb, a
vocoder... into one **Output**. Every change renders it again and plays it.
Games play them by name like any sound: `w:sound("laser")` plays
`assets/laser.soundgraph` (when there's no `laser.sfx`).

- `synth.lua`: the renderer, which is `runtime/soundgraph.lua` (no Lite in
  it: games render the same sound, once, when it's first played)
- `editor.lua`: the tab (runs in Lite), on `canvas.GraphView` like the
  material editor: wires, ties, the selection box, Align come with it
- `files.lua`: the extensions it opens (`soundgraph`)
- `config.lua`: `autoplay` (every change plays it)
- `templates/soundgraph.soundgraph`: what `+ soundgraph` in the tree's `/assets` makes
- `samples/*.soundgraph`: a laser, an explosion, a bell, a robot (the vocoder)

In a tab: RMB adds a node (type to find it). Each node's settings are
sliders inside it: drag one sideways (SHIFT: finely), double-click it for its
default; a list (a wave, a filter's type) changes with a click (SHIFT+click:
back). Drag from a pin to a pin to wire them. The sound is drawn in the strip
at the bottom: SPACE or a click there plays it. CTRL+Z / CTRL+Y undo and
redo, CTRL+S saves, *Export .wav* (RMB) writes `<name>.wav` beside it.

## The nodes

Two kinds of wire: **audio** (blue: a sound) and **control** (yellow: a
value that moves). Any output goes into any input: a control input says what
it does with what it gets.

| node | what it does | inputs |
|---|---|---|
| Output | what you hear: its length (s) and volume | in |
| Oscillator | a tone: sine, square, saw, triangle; freq, duty, level | pitch (+ octaves), amp (x) |
| Noise | white, pink (softer) or brown (a rumble); the same hiss every time (seed) | amp |
| Envelope | attack, decay, sustain, hold, release: 0..1 over time | |
| Slide | from one value to another over a time (curve: fast or slow at first) | |
| LFO | a slow wave: vibrato into a pitch, tremolo into an amp, wah into a cutoff | |
| Value | a constant | |
| Gain | louder or softer; an envelope into `amount` shapes it | in, amount |
| Mix | three sounds into one | a, b, c |
| Ring mod | two sounds multiplied: metallic, robotic | a, b |
| Filter | lowpass, highpass, bandpass, notch, peak, low / high shelf (RBJ biquads) | in, cutoff (+ octaves) |
| Echo | repeats: time apart, feedback, mix | in |
| Reverb | a room (Freeverb): size, damping, mix | in |
| Distortion | overdrive: rounds the peaks off | in |
| Bitcrush | fewer bits, fewer samples: 8-bit grit | in |
| Vocoder | the carrier (a buzz) takes the modulator's shape (noise, a voice): bands, range, release | carrier, modulator |
| Sample | a file beside it: a `.wav` (PCM 8-32 bit or float, any rate or channels), an `.sfx` (sfxr) or another `.soundgraph`; level, speed, start, once / loop | amp |
| Paulstretch | a file stretched up to 50 times slower, its phases blurred: a pad from anything (Paul Nasca's algorithm, written here with our own FFT) | |
| Chorus | three copies a little late and wavering: wide, thick | in |
| Flanger | a very short echo sweeping, with feedback: a jet passing | in |
| Phaser | all-pass stages swept between two frequencies, feedback | in |
| Compressor | loud parts turned down above a threshold (ratio, attack, release, makeup gain) | in |

Nothing that doesn't reach the Output is rendered. A wire that loops back
is read a sample late (feedback works). Too loud: rounded off (the strip says
so). Up to 10 seconds.

A `.soundgraph` file is Lua data, canvas.GraphView's graph: `return { nodes = { {
id, kind, x, y, data = { setting = value } } }, links = { { from, out, to,
input } } }`.

The filters follow Robert Bristow-Johnson's Audio EQ Cookbook; the reverb is
Jezar's Freeverb (public domain); the rest is textbook DSP, written here.

A file setting (Sample, Paulstretch) picks one of the files beside the
`.soundgraph` with a click (SHIFT+click: back); in a game, from its assets.
`.ogg` / `.mp3` / `.flac` aren't read here (Lua only): turn them into a `.wav`.
`samples/pad.soundgraph`: the bell, stretched into a pad.

Not yet (docs/ROADMAP.md, Sound graphs): a phase vocoder, `.ogg` / `.mp3`
sources, sound graphs that run live in a game (these render once, as a sound
effect).
