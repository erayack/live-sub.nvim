std = "lua51"

ignore = {
  "631", -- max line length is handled by StyLua
}

globals = {
  "vim",
}

files["tests/**/*.lua"] = {
  globals = {
    "vim",
  },
}
