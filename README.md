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

Run `:LiveSub` in a modifiable buffer to apply across the whole buffer, then type:

```text
/pattern/replacement/flags
```

Example: `/foo/bar/g` replaces every `foo` with `bar`.

Use an explicit range to limit the substitution to selected lines:

```vim
:2,5LiveSub
```

Or visually select lines and run `:LiveSub` to apply only within that selection.

| Key | Action |
| --- | --- |
| `<Enter>` | Apply to the command range, or the whole buffer when no range was provided |
| `<Esc>` | Cancel and clear previews |

The prompt title shows parse errors and live match counts as you type.

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

- Previews update as you type (viewport only by default) and are constrained to the active range when one is supplied.
- Commit applies across the full buffer, like `:%s`, unless `:LiveSub` was started with a range.
- v1: single buffer, single-line matches, no `c` confirmation.
