# Screenshot Manager (`akshaybapat.screenshot-manager`)

Instant screenshot gallery, fullscreen lightbox, and clipboard manager for the [Omarchy](https://omarchy.org) shell — with optional sub-5 ms Rust `screenshotd` thumbnail acceleration and pure-Python fallback.

Derived from [sahzudin/omarchy-screenshot-manager](https://github.com/sahzudin/omarchy-screenshot-manager) (MIT), fixing clipboard persistence after closing the panel (detached `wl-copy` process group) and adding native `screenshotd` support.

<p align="center">
  <img src="preview.png" alt="Screenshot Manager panel" width="560">
</p>

## Highlights

- **Instant Gallery & Lightbox** — Lists newest screenshots from `$OMARCHY_SCREENSHOT_DIR`, `$XDG_PICTURES_DIR`, or `~/Pictures` with live thumbnails, text filter, and `Esc` / arrow-key fullscreen preview.
- **Reliable Wayland Clipboard Copy** — Streams PNG data via detached `wl-copy -t image/png` so closing the panel never drops the copied screenshot.
- **Safe Recoverable Trash** — Uses `gio trash` with two-step confirmation so nothing is permanently deleted.
- **Rust `screenshotd` + Python Fallback** — Automatically prefers `$HOME/.local/bin/screenshotd` (<5 ms cached 480×270 thumbnails) and falls back cleanly to `screenshotctl.py`.

## Install

```bash
../../install.sh --plugin screenshot-manager --enable
```

Requirements: `wl-copy` (`wl-clipboard`), `gio` (`glib2`), `python3`.

## Bar Interactions & IPC

- **Left-click** — Open the Screenshot Manager gallery panel.
- **Right-click** — Capture a new screenshot (`omarchy capture screenshot`).
- **Middle-click** — Copy the newest screenshot directly to the clipboard.

```bash
omarchy-shell akshaybapat.screenshot-manager toggle
omarchy-shell akshaybapat.screenshot-manager refresh
```

## Settings

| Key | Default | Description |
| --- | --- | --- |
| `showCount` | `true` | Show screenshot count badge next to the bar icon |
| `icon` | `󰄀` | Nerd Font glyph for the bar trigger |

## License

MIT — see [LICENSE](LICENSE). Copyright sahzudin (original) and Akshay Bapat (fork).
