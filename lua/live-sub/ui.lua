local UI = {}
local UiHandle = {}
UiHandle.__index = UiHandle

local function safe_call(fn, ...)
  if type(fn) == "function" then
    return fn(...)
  end
end

function UiHandle:get_input()
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return ""
  end
  return (vim.api.nvim_buf_get_lines(self.bufnr, 0, 1, false)[1] or "")
end

function UiHandle:set_status(status)
  if self.closed or not self.winid or not vim.api.nvim_win_is_valid(self.winid) then
    return
  end
  local title = self.prompt or ":%s"
  if status and status ~= "" then
    title = title .. "  — " .. status
  end
  pcall(vim.api.nvim_win_set_config, self.winid, { title = title })
end

function UiHandle:close()
  if self.closed then
    return
  end
  self.closed = true
  if self.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
  end
  if self.winid and vim.api.nvim_win_is_valid(self.winid) then
    pcall(vim.api.nvim_win_close, self.winid, true)
  end
  if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
    pcall(vim.api.nvim_buf_delete, self.bufnr, { force = true })
  end
end

function UI.open(config, callbacks)
  callbacks = callbacks or {}
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "prompt", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
  vim.fn.prompt_setprompt(bufnr, "")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })

  local width = math.min(config.width or 60, math.max(20, vim.o.columns - 4))
  local height = 1
  local row = math.floor((vim.o.lines - height) / 3)
  local col = math.floor((vim.o.columns - width) / 2)
  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(row, 0),
    col = math.max(col, 0),
    style = "minimal",
    border = config.border or "rounded",
    title = config.prompt or ":%s",
    title_pos = "left",
  })

  local handle = setmetatable({
    bufnr = bufnr,
    winid = winid,
    callbacks = callbacks,
    closed = false,
    prompt = config.prompt or ":%s",
  }, UiHandle)

  local group = vim.api.nvim_create_augroup("LiveSubUI" .. bufnr, { clear = true })
  handle.augroup = group
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if handle.closed then
        return
      end
      safe_call(callbacks.on_change, handle:get_input())
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if handle.closed then
        return
      end
      handle.closed = true
      safe_call(callbacks.on_cancel)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(winid),
    callback = function()
      if handle.closed then
        return
      end
      handle.closed = true
      safe_call(callbacks.on_cancel)
    end,
  })

  vim.keymap.set({ "n", "i" }, config.accept or "<CR>", function()
    safe_call(callbacks.on_accept, handle:get_input())
  end, { buffer = bufnr, nowait = true, silent = true })
  vim.keymap.set({ "n", "i" }, config.cancel or "<Esc>", function()
    safe_call(callbacks.on_cancel)
  end, { buffer = bufnr, nowait = true, silent = true })

  vim.cmd.startinsert()
  return handle
end

return UI
