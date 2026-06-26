local Preview = {}

local function regex_pattern(parsed)
  if parsed.flags and parsed.flags.ignorecase then
    return "\\c" .. parsed.pattern
  end
  return parsed.pattern
end

local function result(count, truncated, error)
  return { match_count = count or 0, truncated = truncated or false, error = error }
end

function Preview.clear(bufnr, ns)
  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
  end
end

local function expand_replacement(replacement, match)
  local out = replacement:gsub("\\0", function()
    return match
  end)
  out = out:gsub("&", function()
    return match
  end)
  return out
end

local function padded_overlay(replacement, match)
  local match_width = vim.fn.strdisplaywidth(match)
  local repl_width = vim.fn.strdisplaywidth(replacement)
  if repl_width < match_width then
    return replacement .. string.rep(" ", match_width - repl_width)
  end
  return replacement
end

local function find_line_matches(line, row, parsed, max_remaining)
  local matches = {}
  local pat = regex_pattern(parsed)
  local start = 0
  while start <= #line and #matches < max_remaining do
    local ok, found = pcall(vim.fn.matchstrpos, line, pat, start)
    if not ok then
      return nil, tostring(found)
    end
    local text, s, e = found[1], found[2], found[3]
    if s == -1 or e == -1 then
      break
    end
    local replacement = expand_replacement(parsed.replacement, text)
    table.insert(matches, {
      start_row = row,
      start_col = s,
      end_row = row,
      end_col = e,
      match = text,
      replacement = replacement,
    })
    if not (parsed.flags and parsed.flags.global) then
      break
    end
    if e <= s then
      start = s + 1
    else
      start = e
    end
  end
  return matches, nil
end

local function compute_in_range(bufnr, parsed, first_row, last_row, max_matches)
  if not parsed or not parsed.valid or parsed.pattern == "" then
    return {}, nil, false
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  first_row = math.max(0, first_row or 0)
  last_row = math.min(line_count - 1, last_row or (line_count - 1))
  if last_row < first_row then
    return {}, nil, false
  end

  local replacements = {}
  local truncated = false
  local lines = vim.api.nvim_buf_get_lines(bufnr, first_row, last_row + 1, false)
  for offset, line in ipairs(lines) do
    local remaining = (max_matches or math.huge) - #replacements
    if remaining <= 0 then
      truncated = true
      break
    end
    local row = first_row + offset - 1
    local line_matches, err = find_line_matches(line, row, parsed, remaining)
    if err then
      return nil, err, false
    end
    for _, m in ipairs(line_matches) do
      table.insert(replacements, m)
    end
    if max_matches and #replacements >= max_matches then
      truncated = true
      break
    end
  end
  return replacements, nil, truncated
end

function Preview.render(bufnr, winid, ns, parsed, config, range)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_win_is_valid(winid) then
    return result(0, false, "invalid buffer/window")
  end
  if not parsed or not parsed.valid or parsed.pattern == "" then
    return result(0, false, parsed and parsed.error or nil)
  end

  config = config or {}
  local preview_config = config.preview or {}
  local context = preview_config.context_lines or 0
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local top
  local bottom
  if preview_config.visible_only == false then
    top = 0
    bottom = line_count - 1
  else
    top = vim.fn.line("w0", winid) - 1
    bottom = vim.fn.line("w$", winid) - 1
  end
  top = math.max(0, top - context)
  bottom = math.min(line_count - 1, bottom + context)
  if range then
    local range_first = range.first or range[1]
    local range_last = range.last or range[2]
    if type(range_first) == "number" and type(range_last) == "number" then
      range_first = math.max(0, range_first)
      range_last = math.min(line_count - 1, range_last)
      top = math.max(top, range_first)
      bottom = math.min(bottom, range_last)
    end
  end

  local replacements, err, truncated = compute_in_range(bufnr, parsed, top, bottom, preview_config.max_matches or 500)
  if err then
    return result(0, false, err)
  end

  local hl = (config.highlight and config.highlight.replacement) or "LiveSubReplacement"
  for _, r in ipairs(replacements) do
    local text = padded_overlay(r.replacement, r.match)
    vim.api.nvim_buf_set_extmark(bufnr, ns, r.start_row, r.start_col, {
      virt_text = { { text, hl } },
      virt_text_pos = "overlay",
      hl_mode = "combine",
    })
  end
  return result(#replacements, truncated, nil)
end

function Preview.compute_replacements(bufnr, parsed, range)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil, "invalid buffer"
  end
  local first = range and (range.first or range[1]) or 0
  local last = range and (range.last or range[2]) or (vim.api.nvim_buf_line_count(bufnr) - 1)
  local replacements, err = compute_in_range(bufnr, parsed, first, last, nil)
  if err then
    return nil, err
  end
  return replacements, nil
end

return Preview
