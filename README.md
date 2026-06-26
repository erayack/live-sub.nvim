# live-sub.nvim

Interactive live substitution for Neovim 0.10+.

Type a `:substitute`-style expression, see replacements previewed in the buffer, then press Enter to apply.

## Install

```lua
{
  "your-name/live-sub.nvim",
  config = function()
    require("live-sub").setup()
  end,
}
```

## Usage

Run `:LiveSub` in a modifiable buffer, then type:

```text
/pattern/replacement/flags
```

Example: `/foo/bar/g` replaces every `foo` with `bar`.

| Key | Action |
| --- | --- |
| `<Enter>` | Apply to the whole buffer |
| `<Esc>` | Cancel and clear previews |

**Flags:** `g` (all matches on a line), `i` (ignore case). The `c` flag is not supported.

## Configuration

`setup()` works out of the box. Override only what you need:

```lua
require("live-sub").setup({
  debounce_ms = 80,
  ui = { width = 60, prompt = ":%s" },
  keymaps = { accept = "<CR>", cancel = "<Esc>" },
})
```

## Notes

- Previews update as you type (viewport only by default).
- Commit applies across the full buffer, like `:%s`.
- v1: single buffer, single-line matches, no ranges or `c` confirmation.
