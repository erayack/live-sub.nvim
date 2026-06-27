local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(
      (message or "assertion failed") .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual),
      2
    )
  end
end

local function assert_truthy(value, message)
  if not value then
    error(message or "expected truthy value", 2)
  end
end

local function title_text(value)
  if type(value) ~= "table" then
    return tostring(value)
  end
  local parts = {}
  for _, chunk in ipairs(value) do
    if type(chunk) == "table" then
      table.insert(parts, chunk[1] or "")
    else
      table.insert(parts, tostring(chunk))
    end
  end
  return table.concat(parts, "")
end

local function assert_contains(value, expected, message)
  if not title_text(value):find(expected, 1, true) then
    error(
      (message or "expected substring") .. ": expected " .. vim.inspect(value) .. " to contain " .. vim.inspect(expected),
      2
    )
  end
end

local function new_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

local Parser = require("live-sub.parser")
local Preview = require("live-sub.preview")
local Session = require("live-sub.session")
local UI = require("live-sub.ui")

vim.cmd("runtime plugin/live-sub.lua")

local function test_ui_status_updates_window_title()
  local handle = UI.open({ width = 30, border = "single", prompt = ":%s" }, {})

  handle:set_status("3 matches")
  local status_title = vim.api.nvim_win_get_config(handle.winid).title
  assert_contains(status_title, "3 matches", "status title")

  handle:set_status(nil)
  local reset_title = vim.api.nvim_win_get_config(handle.winid).title
  assert_equal(title_text(reset_title), ":%s", "reset title")

  handle:close()
end

local function test_parser_accepts_escaped_delimiters_and_flags()
  local parsed = Parser.parse("/a\\/b/c\\/d/gi")

  assert_truthy(parsed.valid, parsed.error)
  assert_equal(parsed.pattern, "a/b", "parsed pattern")
  assert_equal(parsed.replacement, "c/d", "parsed replacement")
  assert_equal(parsed.flags.global, true, "global flag")
  assert_equal(parsed.flags.ignorecase, true, "ignorecase flag")
end

local function test_percent_match_expands_without_crashing()
  local bufnr = new_buffer({ "100% done" })
  local parsed = Parser.parse("/%/[&]/g")
  assert_truthy(parsed.valid, parsed.error)

  local replacements, err = Preview.compute_replacements(bufnr, parsed)
  assert_truthy(replacements, err)
  assert_equal(#replacements, 1, "replacement count")
  assert_equal(replacements[1].replacement, "[%]", "replacement text")
end

local function test_replacement_expands_first_capture_group()
  local bufnr = new_buffer({ "hello world" })
  local parsed = Parser.parse([[/\(hello\) world/\1/]])
  assert_truthy(parsed.valid, parsed.error)

  local replacements, err = Preview.compute_replacements(bufnr, parsed)
  assert_truthy(replacements, err)
  assert_equal(#replacements, 1, "replacement count")
  assert_equal(replacements[1].replacement, "hello", "replacement text")
end

local function test_replacement_expands_second_capture_group()
  local bufnr = new_buffer({ "first second" })
  local parsed = Parser.parse([[/\(first\) \(second\)/\2-\1/]])
  assert_truthy(parsed.valid, parsed.error)

  local replacements, err = Preview.compute_replacements(bufnr, parsed)
  assert_truthy(replacements, err)
  assert_equal(#replacements, 1, "replacement count")
  assert_equal(replacements[1].replacement, "second-first", "replacement text")
end

local function test_replacement_preserves_escaped_backslashes()
  local bufnr = new_buffer({ "path file" })
  local parsed = Parser.parse([[/\(path\) \(file\)/\1\\\2/]])
  assert_truthy(parsed.valid, parsed.error)

  local replacements, err = Preview.compute_replacements(bufnr, parsed)
  assert_truthy(replacements, err)
  assert_equal(#replacements, 1, "replacement count")
  assert_equal(replacements[1].replacement, [[path\file]], "replacement text")
end

local function test_replacement_expands_unmatched_capture_to_empty_string()
  local bufnr = new_buffer({ "foo", "foobar" })
  local parsed = Parser.parse([[/foo\(bar\)\=/[\1]/g]])
  assert_truthy(parsed.valid, parsed.error)

  local replacements, err = Preview.compute_replacements(bufnr, parsed)
  assert_truthy(replacements, err)
  assert_equal(#replacements, 2, "replacement count")
  assert_equal(replacements[1].replacement, "[]", "unmatched replacement text")
  assert_equal(replacements[2].replacement, "[bar]", "matched replacement text")
end

local function test_replacement_does_not_evaluate_expression_replacement()
  vim.fn.setreg("a", "unchanged")
  local bufnr = new_buffer({ "foo" })
  local parsed = Parser.parse([[/foo/\=setreg('a', 'changed')/]])
  assert_truthy(parsed.valid, parsed.error)

  local replacements, err = Preview.compute_replacements(bufnr, parsed)
  assert_truthy(replacements, err)
  assert_equal(#replacements, 1, "replacement count")
  assert_equal(replacements[1].replacement, [[\=setreg('a', 'changed')]], "literal expression replacement text")
  assert_equal(vim.fn.getreg("a"), "unchanged", "expression replacement should not run")
end

local function test_replacement_uses_full_line_context_for_captures()
  local bufnr = new_buffer({ "foobar" })
  local parsed = Parser.parse([[/\(foo\)\zsbar/\1-&/]])
  assert_truthy(parsed.valid, parsed.error)

  local replacements, err = Preview.compute_replacements(bufnr, parsed)
  assert_truthy(replacements, err)
  assert_equal(#replacements, 1, "replacement count")
  assert_equal(replacements[1].replacement, "foo-bar", "context-sensitive replacement text")
end

local function test_preview_render_respects_explicit_range()
  local bufnr = new_buffer({ "foo", "foo", "foo" })
  vim.api.nvim_set_current_buf(bufnr)
  local parsed = Parser.parse("/foo/bar/g")
  assert_truthy(parsed.valid, parsed.error)
  local ns = vim.api.nvim_create_namespace("live-sub-preview-range-test")

  local rendered = Preview.render(bufnr, vim.api.nvim_get_current_win(), ns, parsed, {
    preview = { visible_only = false, max_matches = 500 },
    highlight = { replacement = "LiveSubReplacement" },
  }, { first = 1, last = 1 })

  assert_equal(rendered.match_count, 1, "range-limited preview count")
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
  assert_equal(#marks, 1, "range-limited preview extmarks")
  assert_equal(marks[1][2], 1, "range-limited preview row")
end

local function make_test_session(lines, opts)
  opts = opts or {}
  local target = new_buffer(lines)
  vim.api.nvim_set_current_buf(target)
  return Session.new({
    debounce_ms = 80,
    preview = {
      namespace = "live-sub-test",
      visible_only = true,
      max_matches = opts.max_matches or 500,
    },
    ui = { width = 30, border = "single", prompt = ":%s" },
    keymaps = { accept = "<CR>", cancel = "<Esc>" },
    highlight = { replacement = "LiveSubReplacement" },
  }, { bufnr = target, winid = vim.api.nvim_get_current_win(), range = opts.range })
end

local function test_session_ignores_text_changes_in_unrelated_buffers()
  local session = make_test_session({ "foo" })

  local scheduled = 0
  session.schedule_preview = function()
    scheduled = scheduled + 1
  end

  assert_truthy(session:start(), "session should start")
  scheduled = 0

  local unrelated = new_buffer({ "bar" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = unrelated })
  assert_equal(scheduled, 0, "unrelated buffer change should not schedule preview")

  session:close()
end

local function test_session_exposes_preview_regex_errors()
  local session = make_test_session({ "foo" })
  assert_truthy(session:start(), "session should start")
  session:update_input("/\\(/x/")
  session:refresh_preview()

  local title = vim.api.nvim_win_get_config(session.ui.winid).title
  assert_contains(title, "E54:", "regex error status")
  session:close()
end

local function test_session_shows_parse_error_status()
  local session = make_test_session({ "foo" })
  assert_truthy(session:start(), "session should start")
  session:update_input("foo")

  local title = vim.api.nvim_win_get_config(session.ui.winid).title
  assert_contains(title, "input must start with /", "parse error status")
  session:close()
end

local function test_session_shows_preview_match_count_status()
  local session = make_test_session({ "foo foo" })
  assert_truthy(session:start(), "session should start")
  session:update_input("/foo/bar/g")
  session:refresh_preview()

  local title = vim.api.nvim_win_get_config(session.ui.winid).title
  assert_contains(title, "2 matches", "match count status")
  session:close()
end

local function test_session_shows_confirm_flag_status()
  local session = make_test_session({ "foo" })
  assert_truthy(session:start(), "session should start")
  session:update_input("/foo/bar/c")
  session:refresh_preview()

  local title = vim.api.nvim_win_get_config(session.ui.winid).title
  assert_contains(title, "confirmation flag c is not supported", "confirm flag status")
  session:close()
end

local function test_session_shows_truncated_match_count_status()
  local session = make_test_session({ "foo foo foo" }, { max_matches = 2 })
  assert_truthy(session:start(), "session should start")
  session:update_input("/foo/bar/g")
  session:refresh_preview()

  local title = vim.api.nvim_win_get_config(session.ui.winid).title
  assert_contains(title, "2+ matches", "truncated match count status")
  session:close()
end

local function test_session_commit_matches_computed_replacements()
  local session = make_test_session({ "foo foo", "FOO" })
  assert_truthy(session:start(), "session should start")
  session:update_input("/foo/bar/gi")
  session:commit()

  local lines = vim.api.nvim_buf_get_lines(session.bufnr, 0, -1, false)
  assert_equal(table.concat(lines, "\n"), "bar bar\nbar", "committed buffer text")
end

local function test_session_commit_respects_explicit_range()
  local session = make_test_session({ "foo", "foo", "foo" }, { range = { first = 1, last = 1 } })
  assert_truthy(session:start(), "session should start")
  session:update_input("/foo/bar/g")
  session:commit()

  local lines = vim.api.nvim_buf_get_lines(session.bufnr, 0, -1, false)
  assert_equal(table.concat(lines, "\n"), "foo\nbar\nfoo", "range-limited committed buffer text")
end

local function test_live_sub_command_passes_explicit_range()
  local captured
  local original = package.loaded["live-sub"]
  package.loaded["live-sub"] = {
    start = function(opts)
      captured = opts
    end,
  }
  local bufnr = new_buffer({ "one", "two", "three" })
  vim.api.nvim_set_current_buf(bufnr)

  vim.cmd("2,3LiveSub")

  package.loaded["live-sub"] = original
  assert_truthy(captured, "command should call start")
  assert_equal(captured.range.first, 1, "command range first row")
  assert_equal(captured.range.last, 2, "command range last row")
end

local function test_live_sub_command_passes_visual_range()
  local captured
  local original = package.loaded["live-sub"]
  package.loaded["live-sub"] = {
    start = function(opts)
      captured = opts
    end,
  }
  local bufnr = new_buffer({ "one", "two", "three" })
  vim.api.nvim_set_current_buf(bufnr)
  vim.fn.setpos("'<", { bufnr, 2, 1, 0 })
  vim.fn.setpos("'>", { bufnr, 3, 1, 0 })

  vim.cmd("'<,'>LiveSub")

  package.loaded["live-sub"] = original
  assert_truthy(captured, "visual command should call start")
  assert_equal(captured.range.first, vim.fn.line("'<") - 1, "visual range first row")
  assert_equal(captured.range.last, vim.fn.line("'>") - 1, "visual range last row")
end

local tests = {
  test_ui_status_updates_window_title = test_ui_status_updates_window_title,
  test_parser_accepts_escaped_delimiters_and_flags = test_parser_accepts_escaped_delimiters_and_flags,
  test_percent_match_expands_without_crashing = test_percent_match_expands_without_crashing,
  test_replacement_expands_first_capture_group = test_replacement_expands_first_capture_group,
  test_replacement_expands_second_capture_group = test_replacement_expands_second_capture_group,
  test_replacement_preserves_escaped_backslashes = test_replacement_preserves_escaped_backslashes,
  test_replacement_expands_unmatched_capture_to_empty_string = test_replacement_expands_unmatched_capture_to_empty_string,
  test_replacement_does_not_evaluate_expression_replacement = test_replacement_does_not_evaluate_expression_replacement,
  test_replacement_uses_full_line_context_for_captures = test_replacement_uses_full_line_context_for_captures,
  test_preview_render_respects_explicit_range = test_preview_render_respects_explicit_range,
  test_session_ignores_text_changes_in_unrelated_buffers = test_session_ignores_text_changes_in_unrelated_buffers,
  test_session_exposes_preview_regex_errors = test_session_exposes_preview_regex_errors,
  test_session_shows_parse_error_status = test_session_shows_parse_error_status,
  test_session_shows_preview_match_count_status = test_session_shows_preview_match_count_status,
  test_session_shows_confirm_flag_status = test_session_shows_confirm_flag_status,
  test_session_shows_truncated_match_count_status = test_session_shows_truncated_match_count_status,
  test_session_commit_matches_computed_replacements = test_session_commit_matches_computed_replacements,
  test_session_commit_respects_explicit_range = test_session_commit_respects_explicit_range,
  test_live_sub_command_passes_explicit_range = test_live_sub_command_passes_explicit_range,
  test_live_sub_command_passes_visual_range = test_live_sub_command_passes_visual_range,
}

for name, fn in pairs(tests) do
  fn()
  print("PASS " .. name)
end
