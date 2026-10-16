# Localization

A plugin of Replay's editor (`plugins/localization`): `.loc` files, a game's
texts in several languages, and the files that change with the language.

- `files.lua`: which extensions open here (`loc`)
- `editor.lua`: the tab (runs in Lite)
- `templates/strings.loc`: what *+ loc* in the tree's `/assets` starts from
- the format and the game side: `runtime/loc.lua` (one file for both)

## Using it

- A `.loc` opens as a **table**: a row per key, a column per language (the
  first one is the source the others translate). Red cells: missing; an
  orange mark: much longer than the source (it may not fit where it's shown).
  The header says how many are missing in each language. Click a cell to
  select it; the wheel scrolls; *Find* filters by key or text.
- **On the right**: the selected key's name and its text in each language
  (click a field to type), *Make plural* (the key becomes `key|one`,
  `key|other`... every form any of the languages needs: Russian adds `few`
  and `many`), *Delete*. *+ Key*, *+ Language* (a code: `es`, `fr`,
  `pt-br`), *Remove* (the last language).
- **Files**: *Import...* a `.po` (one language; its `msgctxt` is the key, or
  the source text finds it) or a `.csv` (its columns merged in); *Export .po*
  (`name.<lang>.po` beside it, one a language, plurals as gettext's
  `msgstr[n]`) and *Export .csv*.
- Every edit is a text edit: Ctrl+Z / Ctrl+Y, Ctrl+S. The tab's icon flips
  to the text (plain CSV).

## In a game

`assets/strings.loc` (or `/config language = { file = "...", default = "es" }`):

```lua
w:tr("title")                       -- in the current language
w:tr("gems", 3)                     -- a plural: gems|one / gems|other ... ("3 gems")
w:tr("hello", { name = "Ana" })     -- {name} filled in
w:language("es")                    -- (saved for this machine) ; w:language() ; w:languages()
w:tr_file("sign.png")               -- "/assets/es/sign.png" if there is one
```

`w:asset`, `w:sound` and `w:music` read `assets/<language>/<name>` first
when there is one: a voiced line, a picture with words in it. An options
menu item `type = "language"` lists the game's languages and sets one
(plugins/options). `games/hop` has its texts in English, Spanish and
French.

The 8 x 8 font is ASCII: accents and other scripts show once SDL3_ttf
fonts are in (no `font =`: still the 8 x 8 one).
