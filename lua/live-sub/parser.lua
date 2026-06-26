local M = {}

local function result(pattern, replacement, flags, valid, error)
  return {
    pattern = pattern or "",
    replacement = replacement or "",
    flags = flags or { global = false, ignorecase = false, confirm = false },
    valid = valid,
    error = error,
  }
end

local function read_part(input, start)
  local out = {}
  local escaped = false
  local i = start
  while i <= #input do
    local ch = input:sub(i, i)
    if escaped then
      if ch == "/" then
        table.insert(out, "/")
      else
        table.insert(out, "\\")
        table.insert(out, ch)
      end
      escaped = false
    elseif ch == "\\" then
      escaped = true
    elseif ch == "/" then
      return table.concat(out), i + 1, true
    else
      table.insert(out, ch)
    end
    i = i + 1
  end
  if escaped then
    table.insert(out, "\\")
  end
  return table.concat(out), i, false
end

local function parse_flags(raw)
  local flags = { global = false, ignorecase = false, confirm = false }
  for i = 1, #raw do
    local ch = raw:sub(i, i)
    if ch == "g" then
      flags.global = true
    elseif ch == "i" then
      flags.ignorecase = true
    elseif ch == "c" then
      flags.confirm = true
    else
      return flags, "unknown flag: " .. ch
    end
  end
  return flags, nil
end

function M.parse(input)
  input = input or ""
  if input:sub(1, 1) ~= "/" then
    return result("", "", nil, false, "input must start with /")
  end

  local pattern, next_index, has_pattern_delim = read_part(input, 2)
  if not has_pattern_delim then
    return result(pattern, "", nil, false, "missing replacement delimiter")
  end

  local replacement, flags_index, has_replacement_delim = read_part(input, next_index)
  if not has_replacement_delim then
    return result(pattern, replacement, nil, false, "missing flags delimiter")
  end

  local flags, flag_error = parse_flags(input:sub(flags_index))
  if pattern == "" then
    return result(pattern, replacement, flags, false, "pattern must not be empty")
  end
  if flag_error then
    return result(pattern, replacement, flags, false, flag_error)
  end

  return result(pattern, replacement, flags, true, nil)
end

return M
