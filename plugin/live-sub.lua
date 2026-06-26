if vim.g.loaded_live_sub == 1 then
  return
end
vim.g.loaded_live_sub = 1

vim.api.nvim_create_user_command("LiveSub", function(args)
  local range = nil
  if args.range and args.range > 0 then
    local first = math.min(args.line1, args.line2) - 1
    local last = math.max(args.line1, args.line2) - 1
    range = { first = first, last = last }
  end
  require("live-sub").start({ range = range })
end, { range = true })

pcall(vim.api.nvim_set_hl, 0, "LiveSubReplacement", { link = "IncSearch", default = true })
