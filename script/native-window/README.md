# Native Wine window adapter — isolated experiment

Build with `bash script/build_native_window_adapter.sh` from the repository root.
Requires Xcode and the project-local pinned llvm-mingw compiler. Outputs remain
under ignored `LocalRuntimes/Experiments/native-window-adapter`.

## Opt-in contract

Set `MGB_NATIVE_WINDOW=1`, `MGB_NATIVE_WINDOW_TITLE` to exact window titles
separated by `|`, and `DYLD_INSERT_LIBRARIES` to the built adapter before starting
Wine. These variables must reach the actual game process. Do not enable globally.

Run the built `window-flags.exe '<exact title>' --watch` in the **same isolated
Wine prefix**. It only adds resize/maximize flags to an already-windowed,
non-popup top-level window. After discovering a game it tracks only that process,
checks once per second, and exits when the game exits. Unchanged styles are not
rewritten. This is necessary because Star Rail resets its styles after startup.

The AppKit adapter forwards Wine's delegate callbacks through a narrow proxy,
changing only the fullscreen presentation policy to auto-hide the toolbar.
It adds a native compact toolbar,
native fullscreen participation, frame restoration and two menu commands:

- Control–Command–F: toggle native fullscreen.
- Control–Command–0: exit fullscreen and recover a 1280×720-point window within
  the current screen's usable frame.

The green system button also exits fullscreen. In fullscreen, a nonactivating
native NSPanel provides standard system controls below the menu bar. Its buttons
target the game (close, exit-and-minimize, exit fullscreen), not the small panel.
It is a child of the game window, shown only near the screen top and removed on
fullscreen exit. A 100 ms timer runs only during fullscreen; moving away hides
the whole panel rather than leaving a permanent white strip. This avoids Wine's
offscreen transparent AppKit toolbar, without drawing fake traffic lights or
using private APIs. The original toolbar's automatic hiding remains enabled.

## Observed validation (2026-09-06)

Latest panel revision: real Star Rail screenshots `starrail-panel-hidden-top.png`
and `starrail-panel-hidden-bottom.png` show no persistent white borders;
`starrail-panel-buttons.png` shows the native controls. Clicking green exited
fullscreen. Clicking yellow minimized the game after fullscreen exit; Win32
`IsIconic` read 1 and returned to 0 after restoration. The game remains running.
This revision was checked at the authenticated entry screen, not sustained play.
The nonactivating panel has inactive-gray title text, and its standard green
button uses the native zoom glyph although its action exits fullscreen.
Earlier compact-toolbar-only results below do not prove the white-border fix.

- Geometry assertions and universal arm64/x86_64 dylib build/signature passed.
- A Retina Wine test window entered/exited fullscreen and restored its frame.
- Star Rail CN 4.5.0, M5 Pro, macOS 27 beta, isolated CrossOver 11 + DXMT 0.80:
  screenshot confirmed menu bar, toolbar and system buttons in separate rows;
  clicking the real green button restored the prior 1919×1119-point window.
- Simulating Star Rail's style reset to `16ca0000` was automatically repaired to
  `16cf0000` by the watcher within two seconds.
- Original adapter reached actual gameplay; toolbar revision reached the
  already-authenticated entry screen. Neither is a new performance acceptance.

Evidence logs/screenshots are in the ignored output directory. Do not publish
full screenshots or registry logs containing account information.

## Boundaries and recovery

The launcher now integrates this adapter for all four game launch paths (2026-09-07).
Star Rail retains its previous profile; Genshin, ZZZ and Honkai Impact 3 use the
shared NativeGameWindowSupport configuration. The helper accepts exact titles
separated by `|`; Genshin's fullscreen preference uses `MGB_NATIVE_FULLSCREEN=1`
after windowed startup. Honkai Impact 3 runtime events confirm attachment,
fullscreen entry and restored window on exit. Genshin and ZZZ were not reinstalled
or newly runtime-tested in this change. Do not claim four-game
compatibility, tested multi-monitor transitions, stable 4K internal rendering or
performance gains. The user's panel is 3840×2160; macOS's 5120×2880 Retina backing
surface is not the hardware resolution. Fullscreen may resize that surface.

`prepare-starrail-trial.rb` only changes the cloned `starrail-prefix`; it sets
3840×2160 windowed startup and Retina mode, not an enforced fullscreen render cap.
To revert, quit the isolated game/prefix and launch using the original playable
prefix without the adapter variables/helper. No original game assets or fixed
runtime binary are replaced. Temporary dispatch setup is separate from this
window adapter and must restore hosts after startup.
