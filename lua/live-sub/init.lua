local M = {}

local defaults = {
  debounce_ms = 80,
  preview = {
    visible_only = true,
    context_lines = 0,
    max_matches = 500,
    namespace = "live-sub-preview",
  },
  ui = {
    width = 60,
    border = "rounded",
    prompt = ":%s",
  },
  keymaps = {
    accept = "<CR>",
    cancel = "<Esc>",
  },
  highlight = {
    replacement = "LiveSubReplacement",
  },
}

local config = vim.deepcopy(defaults)
local current_session = nil

local function merge_config(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(config), opts or {})
end

local function normalize_range(range)
  if range == nil then
    return nil, nil
  end
  local first = range.first or range[1]
  local last = range.last or range[2]
  if type(first) ~= "number" or type(last) ~= "number" then
    return nil, "invalid range"
  end
  return { first = math.min(first, last), last = math.max(first, last) }, nil
end

local function notify(msg, level)
  vim.notify("live-sub.nvim: " .. msg, level or vim.log.levels.INFO)
end

local function has_nvim_010()
  return vim.fn.has("nvim-0.10") == 1
end

local function ensure_highlight(cfg)
  pcall(vim.api.nvim_set_hl, 0, cfg.highlight.replacement, { link = "IncSearch", default = true })
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  ensure_highlight(config)
end

function M.start(opts)
  if not has_nvim_010() then
    notify("Neovim 0.10+ is required", vim.log.levels.ERROR)
    return nil
  end

  local bufnr = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_get_option_value("modifiable", { buf = bufnr }) then
    notify("current buffer is not modifiable", vim.log.levels.ERROR)
    return nil
  end

  if current_session then
    current_session:close()
    current_session = nil
  end

  local start_opts = opts or {}
  local range, range_err = normalize_range(start_opts.range)
  if range_err then
    notify(range_err, vim.log.levels.ERROR)
    return nil
  end
  local cfg_opts = vim.deepcopy(start_opts)
  cfg_opts.range = nil
  local cfg = merge_config(cfg_opts)
  ensure_highlight(cfg)

  local ok, Session = pcall(require, "live-sub.session")
  if not ok then
    notify("session module is unavailable: " .. tostring(Session), vim.log.levels.ERROR)
    return nil
  end

  local session = Session.new(cfg, { range = range })
  current_session = session
  local started = session:start()
  if not started then
    current_session = nil
    return nil
  end
  return session
end

function M.stop()
  if current_session then
    current_session:close()
    current_session = nil
  end
end

function M._get_config()
  return config
end

return M
