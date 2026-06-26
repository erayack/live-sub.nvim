if vim.g.loaded_live_sub == 1 then
  return
end
vim.g.loaded_live_sub = 1

vim.api.nvim_create_user_command("LiveSub", function()
  require("live-sub").start()
end, {})

pcall(vim.api.nvim_set_hl, 0, "LiveSubReplacement", { link = "IncSearch", default = true })
