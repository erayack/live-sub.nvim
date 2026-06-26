#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

nvim --clean \
  -c 'set rtp+=.' \
  -c 'runtime plugin/live-sub.lua' \
  -c 'enew' \
  -c "call setline(1, ['foo foo', 'bar foo', 'FOO foo', 'no match', '', 'Type in the floating prompt:', '  slash f-o-o slash b-a-z slash g', '  slash f-o-o slash b-a-z slash g-i', '  slash f-o-o slash [ampersand] slash g'])" \
  -c 'setlocal buftype= noswapfile modifiable' \
  -c 'normal! gg' \
  -c 'LiveSub'
