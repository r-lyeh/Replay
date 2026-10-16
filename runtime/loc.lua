-- loc.lua - localization: a game's texts in several languages (plugins/
-- localization edits them; games read them with w:tr). One file for both.
--
-- The file: a .loc of assets/ (strings.loc by default), CSV (UTF-8, commas,
-- "quoted" when a text has a comma, a quote or a line break):
--   key,en,es,#note
--   title,Hop!,¡Salta!,the window's title
--   gems|one,{n} gem,{n} gema
--   gems|other,{n} gems,{n} gemas
--   @sign,sign.png,sign_es.png          (a file: a picture, a sound per language)
-- The first row names the languages (codes: en, es, fr, pt-br...); a column
-- starting with # is a note (not a language). A key with |one, |few, |other...
-- is a plural form (CLDR's categories: zero, one, two, few, many, other; each
-- language's rule below). {n} and {name} in a text are filled in.
--
-- In a game:
--   w:tr("title") -> the text in the current language (else the first
--     language's, else the key)
--   w:tr("gems", 3) -> the plural form for 3 ("3 gems"); w:tr("hi", { name = "Ana" })
--   w:tr("gems", 3, { ... }) -> both
--   w:language() -> the current one; w:language("es") sets it (saved for this
--     machine: saves/language.sav); w:languages() -> { "en", "es", ... }
--   files: w:asset, w:sound, w:music read assets/<language>/<name> first when
--     there is one (assets/es/sign.png); w:tr_file("sign.png") -> "/assets/es/sign.png"
--     or "/assets/sign.png" (for an image component); "@sign" rows: w:tr_file("@sign")
--   /config: language = { file = "strings.loc", default = "en" }
local M = {}

-- CSV ------------------------------------------------------------------------
function M.csv_parse(text)                         -- -> rows (lists of fields)
  text = tostring(text or ""):gsub("^\239\187\191", ""):gsub("\r\n?", "\n")   -- (a BOM; CRLF)
  local rows, row, field, i, n = {}, {}, {}, 1, #text
  local quoted = false
  while i <= n do
    local c = text:sub(i, i)
    if quoted then
      if c == '"' then
        if text:sub(i + 1, i + 1) == '"' then field[#field + 1] = '"'; i = i + 1 else quoted = false end
      else field[#field + 1] = c end
    elseif c == '"' then quoted = true
    elseif c == "," then row[#row + 1] = table.concat(field); field = {}
    elseif c == "\n" then
      row[#row + 1] = table.concat(field); field = {}
      rows[#rows + 1] = row; row = {}
    else field[#field + 1] = c end
    i = i + 1
  end
  if #field > 0 or #row > 0 then row[#row + 1] = table.concat(field); rows[#rows + 1] = row end
  local out = {}                                   -- (blank lines dropped)
  for _, r in ipairs(rows) do if not (#r == 1 and r[1] == "") then out[#out + 1] = r end end
  return out
end
local function csv_field(s)
  s = tostring(s or "")
  if s:find('[,"\n\r]') or s:match("^%s") or s:match("%s$") then return '"' .. s:gsub('"', '""') .. '"' end
  return s
end
function M.csv_encode(rows)
  local out = {}
  for _, r in ipairs(rows) do
    local f = {}
    for i, v in ipairs(r) do f[i] = csv_field(v) end
    out[#out + 1] = table.concat(f, ",")
  end
  return table.concat(out, "\n") .. "\n"
end

-- plural rules (CLDR, integers): language -> n -> category ----------------------
local function mod(n, m) return n % m end
local RULES = {
  one_other = function(n) return n == 1 and "one" or "other" end,                 -- en, de, es, it, nl, sv, pt-pt...
  zero_one = function(n) return (n == 0 or n == 1) and "one" or "other" end,      -- fr, pt (Brazil)
  none = function() return "other" end,                                           -- ja, zh, ko, th, vi, id
  slavic = function(n)                                                            -- ru, uk, be, sr, hr, bs
    local a, b = mod(n, 10), mod(n, 100)
    if a == 1 and b ~= 11 then return "one" end
    if a >= 2 and a <= 4 and not (b >= 12 and b <= 14) then return "few" end
    return "many"
  end,
  polish = function(n)
    if n == 1 then return "one" end
    local a, b = mod(n, 10), mod(n, 100)
    if a >= 2 and a <= 4 and not (b >= 12 and b <= 14) then return "few" end
    return "many"
  end,
  czech = function(n) if n == 1 then return "one" elseif n >= 2 and n <= 4 then return "few" end return "other" end,   -- cs, sk
  arabic = function(n)
    if n == 0 then return "zero" elseif n == 1 then return "one" elseif n == 2 then return "two" end
    local b = mod(n, 100)
    if b >= 3 and b <= 10 then return "few" elseif b >= 11 and b <= 99 then return "many" end
    return "other"
  end,
  welsh = function(n) return ({ [0] = "zero", [1] = "one", [2] = "two", [3] = "few", [6] = "many" })[n] or "other" end,
  irish = function(n) if n == 1 then return "one" elseif n == 2 then return "two" elseif n >= 3 and n <= 6 then return "few" elseif n >= 7 and n <= 10 then return "many" end return "other" end,
  romanian = function(n) if n == 1 then return "one" end local b = mod(n, 100); if n == 0 or (b >= 2 and b <= 19) then return "few" end return "other" end,
  lithuanian = function(n) local a, b = mod(n, 10), mod(n, 100); if a == 1 and not (b >= 11 and b <= 19) then return "one" elseif a >= 2 and not (b >= 11 and b <= 19) then return "few" end return "other" end,
}
local LANG_RULE = {
  fr = "zero_one", ["pt-br"] = "zero_one", hy = "zero_one",
  ja = "none", zh = "none", ko = "none", th = "none", vi = "none", id = "none", ms = "none", tr = "one_other",
  ru = "slavic", uk = "slavic", be = "slavic", sr = "slavic", hr = "slavic", bs = "slavic",
  pl = "polish", cs = "czech", sk = "czech", ar = "arabic", cy = "welsh", ga = "irish", ro = "romanian", lt = "lithuanian",
}
M.CATEGORIES = { "zero", "one", "two", "few", "many", "other" }
function M.rule(lang)
  lang = tostring(lang or ""):lower()
  return RULES[LANG_RULE[lang] or LANG_RULE[lang:match("^(%a+)") or ""] or "one_other"]
end
function M.plural(lang, n) return M.rule(lang)(math.floor(math.abs(tonumber(n) or 0))) end
function M.categories(lang)                        -- the forms a language uses, in order
  local r, seen, out = M.rule(lang), {}, {}
  for n = 0, 200 do seen[r(n)] = true end
  for _, c in ipairs(M.CATEGORIES) do if seen[c] then out[#out + 1] = c end end
  return out
end

-- a table ----------------------------------------------------------------------
-- text -> t = { langs = { "en", "es" }, notes = { "#note" }, cols = { header }, keys = { key... },
--   rows = { [key] = { lang = text, ["#note"] = text } }, errors }
function M.parse(text)
  local rows = M.csv_parse(text)
  local t = { langs = {}, notes = {}, cols = {}, keys = {}, rows = {}, errors = {} }
  local head = rows[1] or { "key" }
  for i, h in ipairs(head) do
    h = h:gsub("^%s+", ""):gsub("%s+$", "")
    t.cols[i] = h
    if i > 1 and h ~= "" then
      if h:sub(1, 1) == "#" then t.notes[#t.notes + 1] = h else t.langs[#t.langs + 1] = h end
    end
  end
  for r = 2, #rows do
    local row = rows[r]
    local key = (row[1] or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if key ~= "" then
      if t.rows[key] then t.errors[#t.errors + 1] = { r, "key " .. key .. " again (the first one counts)" }
      else
        local e = {}
        for i = 2, #t.cols do if t.cols[i] ~= "" and row[i] and row[i] ~= "" then e[t.cols[i]] = row[i] end end
        t.rows[key] = e
        t.keys[#t.keys + 1] = key
      end
    end
  end
  return t
end
function M.encode(t)
  local cols = { "key" }
  for _, l in ipairs(t.langs) do cols[#cols + 1] = l end
  for _, n in ipairs(t.notes or {}) do cols[#cols + 1] = n end
  local rows = { cols }
  for _, k in ipairs(t.keys) do
    local r = { k }
    for i = 2, #cols do r[i] = t.rows[k] and t.rows[k][cols[i]] or "" end
    rows[#rows + 1] = r
  end
  return M.csv_encode(rows)
end
local function fill(s, vars)
  return (s:gsub("{([%w_]+)}", function(k) local v = vars[k]; if v == nil then return nil end return tostring(v) end))
end
-- the text of a key in a language: its plural form for n, filled in
function M.text(t, lang, key, n, vars)
  if type(n) == "table" and vars == nil then vars, n = n, nil end
  vars = vars or {}
  local first = t.langs[1]
  local function get(k, l) local e = t.rows[k]; return e and l and e[l] end
  local s
  if n ~= nil then
    vars.n = vars.n == nil and n or vars.n
    local c = M.plural(lang, n)
    s = get(key .. "|" .. c, lang) or get(key .. "|other", lang)
    if not s then local c1 = M.plural(first, n); s = get(key .. "|" .. c1, first) or get(key .. "|other", first) end
  end
  s = s or get(key, lang) or get(key, first) or key
  return fill(s, vars)
end
-- what's missing: { { key, lang } }, and texts much longer than the first language's
function M.check(t)
  local missing, long = {}, {}
  local first = t.langs[1]
  for _, k in ipairs(t.keys) do
    local e = t.rows[k]
    local src = first and e[first]
    for _, l in ipairs(t.langs) do
      local s = e[l]
      if not s or s == "" then missing[#missing + 1] = { k, l }
      elseif src and l ~= first and #src > 0 and M.width(s) > M.width(src) * 1.3 + 2 then long[#long + 1] = { k, l, M.width(s) / M.width(src) } end
    end
  end
  return missing, long
end
function M.width(s)                                -- letters, not bytes (UTF-8)
  local n = 0
  for _ in tostring(s):gmatch("[^\128-\191]") do n = n + 1 end
  return n
end

-- gettext .po: one language at a time (msgctxt: the key) -------------------------
local function po_quote(s) return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\t", "\\t") .. '"' end
local function po_unquote(s)
  return (s:gsub('^"', ""):gsub('"$', ""):gsub("\\(.)", { n = "\n", t = "\t", ['"'] = '"', ["\\"] = "\\" }))
end
function M.po_export(t, lang)
  local first = t.langs[1]
  local out = { 'msgid ""', 'msgstr ""', po_quote("Language: " .. lang .. "\n"), po_quote("Content-Type: text/plain; charset=UTF-8\n"), "" }
  local plural_done = {}
  for _, k in ipairs(t.keys) do
    local base = k:match("^(.-)|%a+$")
    local e = t.rows[k]
    if base then                                   -- (a plural: once, all its forms)
      if not plural_done[base] then
        plural_done[base] = true
        local cats = M.categories(lang)
        out[#out + 1] = "msgctxt " .. po_quote(base)
        out[#out + 1] = "msgid " .. po_quote((t.rows[base .. "|one"] or {})[first] or (t.rows[base .. "|other"] or {})[first] or base)
        out[#out + 1] = "msgid_plural " .. po_quote((t.rows[base .. "|other"] or {})[first] or base)
        for i, c in ipairs(cats) do out[#out + 1] = "msgstr[" .. (i - 1) .. "] " .. po_quote((t.rows[base .. "|" .. c] or {})[lang] or "") end
        out[#out + 1] = ""
      end
    else
      out[#out + 1] = "msgctxt " .. po_quote(k)
      out[#out + 1] = "msgid " .. po_quote(first and e[first] or k)
      out[#out + 1] = "msgstr " .. po_quote(e[lang] or "")
      out[#out + 1] = ""
    end
  end
  return table.concat(out, "\n")
end
-- a .po's entries into t's column `lang` (made if new): -> how many, the language it says
function M.po_import(t, text, lang)
  local entries, cur, last = {}, nil, nil
  local function flush() if cur then entries[#entries + 1] = cur end; cur = nil end
  for line in (tostring(text):gsub("\r\n?", "\n") .. "\n"):gmatch("([^\n]*)\n") do
    local kw, rest = line:match("^(msg[%w_%[%]]*)%s+(\".*\")%s*$")
    if kw then
      if kw == "msgctxt" or (kw == "msgid" and not (cur and cur.ctxt and not cur.msgid)) then
        if kw == "msgctxt" or (cur and cur.msgid) then flush() end
      end
      cur = cur or { str = {} }
      local v = po_unquote(rest)
      if kw == "msgctxt" then cur.ctxt = v
      elseif kw == "msgid" then cur.msgid = v
      elseif kw == "msgid_plural" then cur.plural = v
      elseif kw == "msgstr" then cur.str[0] = v
      else local i = tonumber(kw:match("%[(%d+)%]")); if i then cur.str[i] = v end end
      last = { cur, kw }
    elseif line:match('^%s*".*"%s*$') and last then   -- (a continued string)
      local e, k = last[1], last[2]
      local v = po_unquote(line:match('^%s*(".*")%s*$'))
      if k == "msgctxt" then e.ctxt = e.ctxt .. v elseif k == "msgid" then e.msgid = e.msgid .. v
      elseif k == "msgid_plural" then e.plural = e.plural .. v
      else local i = k == "msgstr" and 0 or tonumber(k:match("%[(%d+)%]")); e.str[i] = (e.str[i] or "") .. v end
    end
  end
  flush()
  local said
  for _, e in ipairs(entries) do if e.msgid == "" and e.str[0] then said = e.str[0]:match("Language:%s*([%w%-_]+)") end end
  lang = lang or said or "xx"
  local has = false
  for _, l in ipairs(t.langs) do if l == lang then has = true end end
  if not has then t.langs[#t.langs + 1] = lang end
  local first, n = t.langs[1], 0
  local by_src = {}                                -- (no msgctxt: matched by the first language's text)
  for _, k in ipairs(t.keys) do local s = first and t.rows[k][first]; if s then by_src[s] = by_src[s] or k end end
  local function put(k, v)
    if v == "" then return end
    if not t.rows[k] then t.rows[k] = {}; t.keys[#t.keys + 1] = k end
    t.rows[k][lang] = v
    n = n + 1
  end
  for _, e in ipairs(entries) do
    if e.msgid and e.msgid ~= "" then
      local key = e.ctxt or by_src[e.msgid] or e.msgid
      if e.plural then
        local cats = M.categories(lang)
        for i, c in ipairs(cats) do if e.str[i - 1] then put(key .. "|" .. c, e.str[i - 1]) end end
      elseif e.str[0] then put(key, e.str[0]) end
    end
  end
  return n, lang
end

-- games ----------------------------------------------------------------------------
local ok, ecs = pcall(require, "ecs")
if ok and type(ecs) == "table" and ecs.assets then
  local cache, has = {}, {}
  local function conf(w)
    local cfg = w.node and w:node("/config")
    local c = cfg and type(cfg.c.language) == "table" and cfg.c.language or {}
    return tostring(c.file or "strings.loc"), c.default
  end
  local function table_of(w)
    local file = conf(w)
    local text = ecs.assets.read(file)
    if not text then return nil end
    local c = cache[file]
    if not c or c.text ~= text then c = { text = text, t = M.parse(text) }; cache[file] = c end
    return c.t
  end
  M.table_of = table_of
  function ecs.lang_of(w)                          -- the current language (this machine's, saved; else /config's; else the first)
    if w._lang == nil then
      local saved = ecs.saves and ecs.saves.read and ecs.saves.read("language")
      local v = saved and ecs.decode(saved, "language")
      w._lang = type(v) == "string" and v or false
    end
    local lang = w._lang
    if not lang then
      local _, def = conf(w)
      local t = table_of(w)
      lang = def or (t and t.langs[1]) or "en"
    end
    ecs.lang = lang                                -- (the files: assets/<language>/ first: boot.lua's assets_in)
    return lang
  end
  local World = getmetatable(ecs.world()).__index
  function World:tr(key, n, vars)
    local t = table_of(self)
    if not t then return tostring(key) end
    return M.text(t, ecs.lang_of(self), tostring(key), n, vars)
  end
  function World:language(code)
    if code == nil then return ecs.lang_of(self) end
    self._lang = tostring(code)
    ecs.lang = self._lang                          -- (the files: assets/<language>/ first)
    if ecs.saves and ecs.saves.write then ecs.saves.write("language", ecs.encode(self._lang)) end
    return self._lang
  end
  function World:languages()
    local t = table_of(self)
    local out = {}
    for _, l in ipairs(t and t.langs or {}) do out[#out + 1] = l end
    return out
  end
  function World:tr_file(name)                     -- "/assets/<language>/name" when there is one, else "/assets/name"
    name = tostring(name)
    if name:sub(1, 1) == "@" then name = self:tr(name) end
    name = name:gsub("^/assets/", ""):gsub("^/", "")
    local lang = ecs.lang_of(self)
    local k = lang .. "/" .. name
    if has[k] == nil then has[k] = ecs.assets.exists and ecs.assets.exists(k) or (ecs.assets.read(k) ~= nil) end
    if has[k] then return "/assets/" .. k end
    return "/assets/" .. name
  end
  M.ecs = ecs
end
return M
