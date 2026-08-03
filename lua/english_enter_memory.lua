local M = {}

local DATA_FILE =
  rime_api.get_user_data_dir() .. "/enter_english.learned.tsv"

local MIN_COUNT = 2
local counts = {}
local loaded = false

local function log_message(message)
  pcall(function()
    log.warning("[EEM] " .. tostring(message))
  end)
end

local function is_learnable(input)
  if not input or #input < 2 then
    return false
  end

  if not input:match("^[A-Za-z][A-Za-z0-9_'%-]*$") then
    return false
  end

  if input:match("['_%-]$") then
    return false
  end

  if input:find("''", 1, true)
      or input:find("--", 1, true)
      or input:find("__", 1, true) then
    return false
  end

  return true
end

local function load_data()
  if loaded then
    return
  end

  loaded = true

  local file = io.open(DATA_FILE, "r")
  if not file then
    log_message("new data file: " .. DATA_FILE)
    return
  end

  for line in file:lines() do
    local word, increment =
      line:match("^([^\t]+)\t(%d+)$")

    if word and increment then
      counts[word] =
        (counts[word] or 0) + tonumber(increment)
    end
  end

  file:close()
  log_message("loaded learned words")
end

local function append_occurrence(word)
  load_data()

  counts[word] = (counts[word] or 0) + 1

  local file, err = io.open(DATA_FILE, "a")
  if not file then
    log.error(
      "[EEM] cannot open data file: "
        .. tostring(err)
    )
    return false
  end

  file:write(word, "\t1\n")
  file:close()

  log_message(
    string.format(
      "learned %q count=%d",
      word,
      counts[word]
    )
  )

  return true
end

local processor = {}

function processor.init(env)
  load_data()
  log_message("processor initialized")
end

function processor.func(key, env)
  if key:release()
      or key:ctrl()
      or key:alt()
      or key:super() then
    return 2
  end

  local repr = key:repr()

  -- 避免 minus 被 key_binder 当作候选翻页键
  -- if repr == "minus" and context:is_composing() then
  --   context:push_input("-")
  --   return 1
  -- end

  if repr ~= "Return"
      and repr ~= "KP_Enter"
      and repr ~= "ISO_Enter" then
    return 2
  end

  local context = env.engine.context

  if not context:is_composing() then
    return 2
  end

  local input = context.input or ""

  if not is_learnable(input) then
    return 2
  end

  append_occurrence(input)

  env.engine:commit_text(input)
  context:clear()

  return 1
end

local translator = {}

function translator.init(env)
  load_data()
  log_message("translator initialized")
end

function translator.func(input, segment, env)
  load_data()

  if not input or input == "" then
    return
  end

  if not input:match("^[A-Za-z][A-Za-z0-9_'%-]*$") then
    return
  end

  local matches = {}

  for word, count in pairs(counts) do
    if count >= MIN_COUNT
        and word:sub(1, #input) == input then
      table.insert(matches, {
        word = word,
        count = count,
      })
    end
  end

  table.sort(matches, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end

    if #a.word ~= #b.word then
      return #a.word < #b.word
    end

    return a.word < b.word
  end)

  for index, item in ipairs(matches) do
    local candidate = Candidate(
      "enter_english",
      segment.start,
      segment._end,
      item.word,
      "〔Enter ×" .. tostring(item.count) .. "〕"
    )

    candidate.quality =
      1000 + item.count * 10 - index

    yield(candidate)
  end
end

return {
  processor = processor,
  translator = translator,
}
