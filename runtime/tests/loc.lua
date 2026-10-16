-- loc.lua - localization (runtime/loc.lua): the CSV, plurals per language,
-- {n} / {name}, w:tr / w:language / w:languages / w:tr_file, missing and long
-- texts, .po export / import.   cd runtime/tests && luajit loc.lua   (or lua5.4)
package.path = "../?.lua;" .. package.path
local ecs = require "ecs"
local L = require "loc"
local n, fails = 0, 0
local function check(c, m) n = n + 1; if not c then fails = fails + 1; print("  FAIL: " .. m) end end

local TEXT = 'key,en,es,ru,#note\n' ..
  'title,Hop!,"Salta, salta",Pryg,the window\'s title\n' ..
  'hello,"Hi, {name}!",Hola {name},Privet {name}\n' ..
  'gems|one,{n} gem,{n} gema,{n} kamen\n' ..
  'gems|few,,,{n} kamnya\n' ..
  'gems|many,,,{n} kamney\n' ..
  'gems|other,{n} gems,{n} gemas,\n' ..
  'quote,"say ""yes""",di "si",\n' ..
  'multi,"two\nlines",dos lineas,\n' ..
  '@sign,sign.png,sign_es.png,\n'

-- CSV
local rows = L.csv_parse(TEXT)
check(#rows == 10 and rows[2][3] == "Salta, salta" and rows[8][2] == 'say "yes"' and rows[9][2] == "two\nlines", "CSV: commas, quotes, line breaks")
check(#L.csv_parse(L.csv_encode(rows)) == 10 and L.csv_parse(L.csv_encode(rows))[9][2] == "two\nlines", "CSV out and back")
local t = L.parse(TEXT)
check(#t.langs == 3 and t.langs[2] == "es" and t.notes[1] == "#note" and #t.keys == 9, "the table: 3 languages, a note column, 9 keys")
check(t.rows.title["#note"] == "the window's title", "notes kept")
check(L.parse(L.encode(t)).rows.multi.en == "two\nlines" and L.encode(L.parse(L.encode(t))) == L.encode(t), "encode -> parse: the same")

-- plurals
check(L.plural("en", 1) == "one" and L.plural("en", 0) == "other" and L.plural("fr", 0) == "one", "en / fr")
check(L.plural("ru", 1) == "one" and L.plural("ru", 3) == "few" and L.plural("ru", 5) == "many" and L.plural("ru", 21) == "one" and L.plural("ru", 12) == "many", "ru")
check(L.plural("pl", 22) == "few" and L.plural("ja", 1) == "other" and L.plural("ar", 2) == "two", "pl, ja, ar")
check(table.concat(L.categories("ru"), ",") == "one,few,many" and table.concat(L.categories("en"), ",") == "one,other", "the forms a language has")

-- texts
check(L.text(t, "en", "gems", 1) == "1 gem" and L.text(t, "en", "gems", 4) == "4 gems", "en: 1 gem, 4 gems")
check(L.text(t, "ru", "gems", 3) == "3 kamnya" and L.text(t, "ru", "gems", 7) == "7 kamney", "ru: few, many")
check(L.text(t, "es", "hello", { name = "Ana" }) == "Hola Ana", "{name}")
check(L.text(t, "ru", "quote") == 'say "yes"', "missing: the first language's")
check(L.text(t, "es", "nope") == "nope", "no key: the key")
local missing, long = L.check(t)
check(#missing >= 4, "missing found: " .. #missing)
check(#long >= 1 and long[1][1] == "title", "a text much longer than the first language's: " .. tostring(long[1] and long[1][1]))

-- .po
local po = L.po_export(t, "es")
check(po:find('msgctxt "title"', 1, true) and po:find('msgstr "Salta, salta"', 1, true) and po:find("msgid_plural", 1, true), ".po out")
local t2 = L.parse("key,en\ntitle,Hop!\ngems|one,{n} gem\ngems|other,{n} gems\n")
local got, lang = L.po_import(t2, po)
check(lang == "es" and t2.rows.title.es == "Salta, salta" and t2.rows["gems|other"].es == "{n} gemas", ".po in: " .. tostring(got) .. " " .. tostring(lang))
local bare = 'msgid ""\nmsgstr "Language: fr\\n"\n\nmsgid "Hop!"\nmsgstr "Saute !"\n'
L.po_import(t2, bare)
check(t2.rows.title.fr == "Saute !", ".po in, no msgctxt: matched by the first language's text")

-- a game
local store = {}
ecs.saves = { read = function(k) return store[k] end, write = function(k, v) store[k] = v; return true end }
local files = { ["strings.loc"] = TEXT, ["es/sign.png"] = "PNG" }
ecs.assets.read = function(name) return files[name] end
local w = ecs.world()
check(w:language() == "en" and #w:languages() == 3, "the first language by default")
check(w:tr("gems", 2) == "2 gems" and w:tr("hello", { name = "Bo" }) == "Hi, Bo!", "w:tr")
w:language("es")
check(w:tr("title") == "Salta, salta" and w:tr("gems", 1) == "1 gema", "w:language('es')")
check(store.language and ecs.decode(store.language) == "es", "saved for this machine")
local w2 = ecs.world()
check(w2:language() == "es", "read back")
check(w2:tr_file("sign.png") == "/assets/es/sign.png" and w2:tr_file("ship.png") == "/assets/ship.png", "w:tr_file: the language's file when there is one")
check(w2:tr_file("@sign") == "/assets/sign_es.png", "an @ row: that language's file")
w2:spawn("/config", { language = { default = "ru" } })
store.language = nil
local w3 = ecs.world()
w3:spawn("/config", { language = { default = "ru" } })
check(w3:language() == "ru", "/config's default")

print(string.format("loc: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
