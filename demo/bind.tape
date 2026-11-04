# The README demo. Render from the repo root:
#
#   vhs demo/bind.tape
#
# It records a throwaway Rex config (demo/setup.sh) in your own Neovim, so
# what you see is lua-language-server answering, not a mock-up.

Output "demo/bind.gif"

Set Shell bash
Set FontSize 15
Set Width 1100
Set Height 560
Set Padding 18
Set Theme "Catppuccin Mocha"
Set TypingSpeed 50ms
Set Framerate 20

# Set the stage off-camera: build the config, open it, let lua_ls attach.
Hide
Type 'cd "$(./demo/setup.sh)" && clear' Enter
Sleep 1s
Type "nvim -n init.lua" Enter  # -n: no swapfile, so a stale one cannot prompt
Sleep 14s
Show

Sleep 1500ms

# 1. Bind a key: every action name, fuzzy, with Rex's own title underneath.
Type "Go"
Sleep 300ms
Type 'rex.bind(P .. "g", "")'
Left
Left
Sleep 600ms
Type "panesp"
Sleep 2s
Ctrl+Space
Sleep 2500ms
Ctrl+Y
Sleep 1800ms

# 2. Run one: the overload resolves, so the arguments are typed too.
Escape
Type "o"
Type 'rex.invoke("")'
Left
Left
Type "paneresize"
Sleep 1500ms
Ctrl+Y
Sleep 1800ms
Type ', { direction = "" }'
Left
Left
Left
Sleep 400ms
Ctrl+Space
Sleep 2500ms
Escape
Sleep 1200ms

# 3. Hover: documentation straight from the server's own API description.
Type "?focus_direction"
Enter
Sleep 600ms
Type "K"
Sleep 4s
Escape
Sleep 1500ms
