local Parser = require("live-sub.parser")
local UI = require("live-sub.ui")

local Session = {}
Session.__index = Session

local function notify(msg, level)
  vim.notify("live-sub.nvim: " .. msg, level or vim.log.levels.INFO)
end

function Session.new(config, opts)
  opts = opts or {}
  return setmetatable({
    bufnr = opts.bufnr or vim.api.nvim_get_current_buf(),
    winid = opts.winid or vim.api.nvim_get_current_win(),
    config = config,
    ns = vim.api.nvim_create_namespace(config.preview.namespace),
    ui = nil,
    input = "",
    parsed = nil,
    debounce_timer = nil,
    closed = false,
    last_preview_version = 0,
    last_preview_error = nil,
    augroup = nil,
  }, Session)
end

function Session:start()
  if not vim.api.nvim_buf_is_valid(self.bufnr) or not vim.api.nvim_win_is_valid(self.winid) then
    notify("target buffer/window is invalid", vim.log.levels.ERROR)
    return false
  end

  self.augroup = vim.api.nvim_create_augroup("LiveSubSession" .. self.bufnr .. "_" .. self.winid, { clear = true })
  local buffer_refresh_events = { "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI" }
  vim.api.nvim_create_autocmd(buffer_refresh_events, {
    group = self.augroup,
    buffer = self.bufnr,
    callback = function()
      if self.closed then
        return
      end
      self:schedule_preview()
    end,
  })
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = self.augroup,
    callback = function(args)
      if self.closed or tonumber(args.match) ~= self.winid then
        return
      end
      self:schedule_preview()
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    group = self.augroup,
    buffer = self.bufnr,
    callback = function()
      self:cancel()
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = self.augroup,
    pattern = tostring(self.winid),
    callback = function()
      self:cancel()
    end,
  })

  local ok, ui_or_err = pcall(UI.open, {
    width = self.config.ui.width,
    border = self.config.ui.border,
    prompt = self.config.ui.prompt,
    accept = self.config.keymaps.accept,
    cancel = self.config.keymaps.cancel,
  }, {
    on_change = function(input)
      self:update_input(input)
    end,
    on_accept = function(input)
      self.input = input
      self.parsed = Parser.parse(input)
      self:commit()
    end,
    on_cancel = function()
      self:cancel()
    end,
  })
  if not ok then
    notify("failed to open prompt: " .. tostring(ui_or_err), vim.log.levels.ERROR)
    self:close()
    return false
  end
  self.ui = ui_or_err
  self:update_input("")
  return true
end

function Session:update_input(input)
  if self.closed then
    return
  end
  self.input = input or ""
  self.parsed = Parser.parse(self.input)
  self:schedule_preview()
end

function Session:schedule_preview()
  if self.closed then
    return
  end
  self.last_preview_version = self.last_preview_version + 1
  local version = self.last_preview_version
  if self.debounce_timer then
    self.debounce_timer:stop()
    self.debounce_timer:close()
    self.debounce_timer = nil
  end
  local timer = vim.uv.new_timer()
  self.debounce_timer = timer
  timer:start(
    self.config.debounce_ms or 80,
    0,
    vim.schedule_wrap(function()
      if self.debounce_timer == timer then
        self.debounce_timer = nil
      end
      timer:stop()
      timer:close()
      if self.closed or version ~= self.last_preview_version then
        return
      end
      if not vim.api.nvim_buf_is_valid(self.bufnr) or not vim.api.nvim_win_is_valid(self.winid) then
        return
      end
      self:refresh_preview()
    end)
  )
end

function Session:refresh_preview()
  local ok, Preview = pcall(require, "live-sub.preview")
  if not ok then
    return
  end
  Preview.clear(self.bufnr, self.ns)
  self.last_preview_error = nil
  if self.parsed and self.parsed.valid then
    local preview_result = Preview.render(self.bufnr, self.winid, self.ns, self.parsed, self.config)
    self.last_preview_error = preview_result and preview_result.error or nil
  end
end

function Session:commit()
  local ok, Preview = pcall(require, "live-sub.preview")
  if not ok then
    notify("preview module is unavailable: " .. tostring(Preview), vim.log.levels.ERROR)
    return
  end
  if not self.parsed or not self.parsed.valid then
    notify((self.parsed and self.parsed.error) or "invalid substitution", vim.log.levels.ERROR)
    return
  end
  if self.parsed.flags.confirm then
    notify("confirmation flag c is not supported", vim.log.levels.ERROR)
    return
  end
  if
    not vim.api.nvim_buf_is_valid(self.bufnr) or not vim.api.nvim_get_option_value("modifiable", { buf = self.bufnr })
  then
    notify("target buffer is not modifiable", vim.log.levels.ERROR)
    return
  end
  local replacements, err = Preview.compute_replacements(self.bufnr, self.parsed)
  if not replacements then
    notify(err or "failed to compute replacements", vim.log.levels.ERROR)
    return
  end
  if #replacements == 0 then
    notify("No matches")
    self:close()
    return
  end
  for i = #replacements, 1, -1 do
    local r = replacements[i]
    vim.api.nvim_buf_set_text(self.bufnr, r.start_row, r.start_col, r.end_row, r.end_col, { r.replacement })
  end
  self:close()
end

function Session:cancel()
  self:close()
end

function Session:close()
  if self.closed then
    return
  end
  self.closed = true
  if self.debounce_timer then
    self.debounce_timer:stop()
    self.debounce_timer:close()
    self.debounce_timer = nil
  end
  pcall(function()
    require("live-sub.preview").clear(self.bufnr, self.ns)
  end)
  if self.ui then
    self.ui:close()
    self.ui = nil
  end
  if self.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
    self.augroup = nil
  end
end

return Session
