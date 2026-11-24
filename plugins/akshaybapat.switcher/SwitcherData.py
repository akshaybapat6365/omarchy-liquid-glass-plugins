#!/usr/bin/env python3
"""Fast live Hyprland MRU window & icon engine for Omarchy Liquid Glass Switcher.

Pure Python stdlib, zero external dependencies, <20 ms live execution via direct
Hyprland UNIX socket IPC and compact cached desktop/icon indexing.
"""

import json
import os
import re
import socket
import sys
from pathlib import Path

HOME = Path.home()
SHELF_WORKSPACES = frozenset(("special:omarchy-minimized", "special:omarchy-window-peek"))
CACHE_PATH = Path("/tmp/omarchy-switcher-icons.json")
CACHE_VERSION = 3

ADDRESS_RE = re.compile(r"^(?:0x)?[0-9a-fA-F]+$")
BROWSER_WEBAPP_RE = re.compile(r"^(?:chrome|chromium|brave)-(.+)-(?:Default|Profile_[0-9]+)$")
URL_HOST_PATH_RE = re.compile(r"^https?://([^/?#]+)([^?#]*)")
ICON_SIZE_RE = re.compile(r"/(\d+)x\d+(@2x?|@2)?/")
CLASS_SUFFIX_RE = re.compile(r"[-_](?:desktop|bin|gtk|wayland|client)$", re.IGNORECASE)
CLASS_SEP_RE = re.compile(r"[-_.]+")
WORD_SPLIT_RE = re.compile(r"[\s\-_/.]+")

# Curated human-readable app names (keyed by lowercase class / id)
DISPLAY_NAME_OVERRIDES = {
    "com.mitchellh.ghostty": "Ghostty",
    "ghostty": "Ghostty",
    "brave-browser": "Brave",
    "brave-origin": "Brave",
    "brave-origin-beta": "Brave",
    "com.brave.origin": "Brave",
    "com.brave.origin.beta": "Brave",
    "chromium": "Chromium",
    "chromium-browser": "Chromium",
    "google-chrome": "Chrome",
    "org.gnome.nautilus": "Files",
    "nautilus": "Files",
    "thunar": "Files",
    "dolphin": "Files",
    "chatgpt": "ChatGPT",
    "antigravity": "Antigravity",
    "claude": "Claude",
    "cursor": "Cursor",
    "code": "VS Code",
    "code-oss": "VS Code",
    "vscodium": "VSCodium",
    "obsidian": "Obsidian",
    "spotify": "Spotify",
    "discord": "Discord",
    "vesktop": "Discord",
    "firefox": "Firefox",
    "zen": "Zen",
    "zen-browser": "Zen",
    "alacritty": "Alacritty",
    "kitty": "Kitty",
    "foot": "Foot",
    "footclient": "Foot",
    "wezterm": "WezTerm",
    "org.wezfurlong.wezterm": "WezTerm",
    "slack": "Slack",
    "org.telegram.desktop": "Telegram",
    "telegramdesktop": "Telegram",
    "vlc": "VLC",
    "mpv": "mpv",
    "gimp": "GIMP",
    "inkscape": "Inkscape",
    "figma": "Figma",
    "ai.opencode.desktop": "OpenCode",
    "opencode-desktop": "OpenCode",
    "codex": "Codex",
    "cherry-studio": "Cherry Studio",
    "1password": "1Password",
    "bitwarden": "Bitwarden",
    "pavucontrol": "Audio",
    "org.pulseaudio.pavucontrol": "Audio",
    "blueman-manager": "Bluetooth",
    "btop": "btop",
    "imv": "imv",
    "evince": "Documents",
    "org.gnome.evince": "Documents",
    "org.pwmt.zathura": "Zathura",
}

ICON_ALIASES = {
    "com.mitchellh.ghostty": ("com.mitchellh.ghostty", "ghostty"),
    "ghostty": ("com.mitchellh.ghostty", "ghostty"),
    "brave-browser": ("brave-browser", "brave-desktop", "brave-origin", "brave-origin-beta"),
    "brave-origin": ("brave-origin", "brave-browser", "brave-desktop"),
    "brave-origin-beta": ("brave-origin-beta", "brave-origin", "brave-browser"),
    "com.brave.origin.beta": ("brave-origin-beta", "brave-origin", "brave-browser"),
    "chromium": ("chromium", "chromium-browser"),
    "org.gnome.nautilus": ("org.gnome.nautilus", "nautilus", "system-file-manager"),
    "nautilus": ("org.gnome.nautilus", "nautilus", "system-file-manager"),
    "cursor": ("co.anysphere.cursor", "cursor"),
    "code": ("visual-studio-code", "code", "com.visualstudio.code"),
    "code-oss": ("code-oss", "visual-studio-code", "code"),
    "chatgpt": ("chatgpt", "ChatGPT", "codex-desktop-chatgpt"),
    "claude": ("Claude", "claude"),
    "antigravity": ("antigravity", "Antigravity"),
    "obsidian": ("obsidian",),
    "spotify": ("spotify", "spotify-client"),
    "alacritty": ("Alacritty", "alacritty", "utilities-terminal"),
    "kitty": ("kitty", "utilities-terminal"),
    "foot": ("foot", "utilities-terminal"),
    "firefox": ("firefox",),
    "discord": ("discord",),
    "vesktop": ("vesktop", "discord"),
    "vlc": ("vlc",),
    "mpv": ("mpv",),
}


def normalize_address(addr):
    raw = str(addr or "").strip()
    if not raw or not ADDRESS_RE.match(raw):
        return ""
    if not raw.startswith("0x"):
        raw = "0x" + raw
    return raw.lower()


def find_hypr_socket():
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    hypr_dir = os.path.join(runtime_dir, "hypr")

    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "").strip()
    if sig:
        candidate = os.path.join(hypr_dir, sig, ".socket.sock")
        if os.path.exists(candidate):
            return candidate

    if not os.path.isdir(hypr_dir):
        return ""

    best_sock = ""
    best_mtime = -1.0
    try:
        with os.scandir(hypr_dir) as it:
            for entry in it:
                if not entry.is_dir():
                    continue
                sock = os.path.join(entry.path, ".socket.sock")
                if os.path.exists(sock):
                    try:
                        mtime = entry.stat().st_mtime
                    except OSError:
                        mtime = 0.0
                    if mtime >= best_mtime:
                        best_mtime = mtime
                        best_sock = sock
    except OSError:
        return ""
    return best_sock


def hypr_socket_send(sock_path, payload, timeout=0.6):
    if not sock_path:
        return None
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect(sock_path)
            s.sendall(payload.encode("utf-8"))
            chunks = []
            while True:
                data = s.recv(65536)
                if not data:
                    break
                chunks.append(data)
        return b"".join(chunks).decode("utf-8", errors="replace").strip()
    except OSError:
        return None


def _hyprctl_run(args, timeout=1.2):
    import subprocess
    try:
        res = subprocess.run(
            ["hyprctl"] + args,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout,
            check=False,
        )
        if res.returncode == 0:
            return res.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return None


def hypr_json(sock_path, command):
    raw = hypr_socket_send(sock_path, f"j/{command}")
    if raw is None:
        raw = _hyprctl_run(["-j", command])
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def hypr_dispatch(sock_path, lua_expr, classic_expr=""):
    """Dispatch via Hyprland 0.56 Lua expression, with classic & hyprctl fallback."""
    candidates = [lua_expr]
    if classic_expr:
        candidates.append(classic_expr)

    for expr in candidates:
        if sock_path:
            reply = hypr_socket_send(sock_path, f"/dispatch {expr}")
            if reply is not None and reply.lower() == "ok":
                return True
        out = _hyprctl_run(["dispatch", expr], timeout=1.5)
        if out is not None and out.lower() == "ok":
            return True
    return False


def _extract_web_identities(exec_str):
    if not exec_str:
        return []
    tokens = exec_str.replace('"', " ").replace("'", " ").split()
    launch_webapp = any(os.path.basename(t) == "omarchy-launch-webapp" for t in tokens)
    identities = []
    for tok in tokens:
        if tok.startswith("--app-id="):
            identities.append(tok[9:].lower())
        url = tok[6:] if tok.startswith("--app=") else (tok if launch_webapp and tok.startswith(("http://", "https://")) else "")
        if url:
            m = URL_HOST_PATH_RE.match(url)
            if m:
                host = m.group(1).lower()
                path_part = (m.group(2) or "/").replace("/", "_")
                identities.append(f"{host}_{path_part}")
    return identities


def _parse_desktop_file(path_str):
    try:
        with open(path_str, "r", encoding="utf-8", errors="ignore") as fh:
            text = fh.read()
    except OSError:
        return None

    in_entry = False
    name = ""
    icon = ""
    wm_class = ""
    exec_line = ""
    no_display = False

    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if s.startswith("["):
            if s == "[Desktop Entry]":
                in_entry = True
                continue
            if in_entry:
                break
            continue
        if not in_entry or "=" not in s:
            continue
        key, val = s.split("=", 1)
        key = key.strip()
        val = val.strip()
        if key == "Name" and not name:
            name = val
        elif key == "Icon" and not icon:
            icon = val
        elif key == "StartupWMClass" and not wm_class:
            wm_class = val
        elif key == "Exec" and not exec_line:
            exec_line = val
        elif key == "NoDisplay":
            no_display = val.lower() == "true"

    if not name and not icon:
        return None

    stem = os.path.splitext(os.path.basename(path_str))[0]
    return {
        "id": stem,
        "name": name,
        "icon": icon,
        "wmClass": wm_class,
        "webIds": _extract_web_identities(exec_line),
        "noDisplay": no_display,
    }


def _icon_rank(path_str):
    low = path_str.lower()
    is_symbolic = 1 if "symbolic" in low else 0
    ext_score = 3 if low.endswith(".svg") else (2 if low.endswith(".png") else 1)
    cat_score = 2 if ("/apps/" in low or "/applications/icons/" in low or "/pixmaps/" in low) else 1

    size_score = 48
    if "scalable" in low:
        size_score = 260
    else:
        m = ICON_SIZE_RE.search(low)
        if m:
            px = int(m.group(1))
            if m.group(2):
                px *= 2
            size_score = min(px, 512)
        elif "/applications/icons/" in low or "/pixmaps/" in low:
            size_score = 160

    theme_bonus = 0
    if "/.local/share/applications/icons/" in low or "/.local/share/icons/" in low:
        theme_bonus = 60
    elif "/papirus" in low:
        theme_bonus = 50
    elif "/hicolor/" in low:
        theme_bonus = 45
    elif "/yaru" in low:
        theme_bonus = 35
    elif "/breeze" in low:
        theme_bonus = 30
    elif "/adwaita/" in low:
        theme_bonus = 25

    return (1 - is_symbolic, cat_score, theme_bonus + ext_score * 10 + size_score)


def _dir_fingerprint(paths):
    fp = []
    for p in paths:
        try:
            fp.append([p, os.stat(p).st_mtime_ns])
        except OSError:
            fp.append([p, 0])
    return fp


def _resolve_icon_name(icon_name, icons_map):
    if not icon_name:
        return ""
    if os.path.isabs(icon_name):
        return icon_name if os.path.isfile(icon_name) else ""

    low = icon_name.lower()
    hit = icons_map.get(low)
    if hit:
        return hit

    stem = os.path.splitext(low)[0]
    hit = icons_map.get(stem)
    if hit:
        return hit

    if "." in stem:
        tail = stem.rsplit(".", 1)[-1]
        hit = icons_map.get(tail)
        if hit:
            return hit
    return ""


def _build_icon_and_desktop_index():
    app_dirs = [
        str(HOME / ".local/share/applications"),
        "/usr/share/applications",
        "/usr/local/share/applications",
        "/var/lib/flatpak/exports/share/applications",
    ]
    icon_roots = [
        str(HOME / ".local/share/applications/icons"),
        str(HOME / ".local/share/icons/hicolor"),
        "/usr/share/icons/Papirus-Dark",
        "/usr/share/icons/Papirus",
        "/usr/share/icons/hicolor",
        "/usr/share/icons/Yaru-dark",
        "/usr/share/icons/Yaru",
        "/usr/share/icons/breeze-dark",
        "/usr/share/icons/breeze",
        "/usr/share/icons/Adwaita",
        "/usr/share/pixmaps",
    ]

    fp = _dir_fingerprint(app_dirs + icon_roots)
    cache_file = str(CACHE_PATH)

    # Compact cache fast-path (<0.8 ms)
    try:
        with open(cache_file, "r", encoding="utf-8") as fh:
            cached = json.load(fh)
        if cached.get("version") == CACHE_VERSION and cached.get("fingerprint") == fp:
            return cached
    except (OSError, ValueError):
        pass

    # 1. Index app icons (focus on apps/applications/pixmaps so cache stays tiny ~50 KB)
    icon_best = {}
    valid_exts = (".svg", ".png", ".webp")
    skip_dirs = frozenset((
        "actions", "animations", "categories", "cursors", "devices",
        "emblems", "emotes", "intl", "mimetypes", "panel", "places",
        "status", "stock", "ui", "legacy", "web",
    ))

    for root in icon_roots:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d.lower() not in skip_dirs]
            for fn in filenames:
                stem, ext = os.path.splitext(fn)
                if ext.lower() not in valid_exts:
                    continue
                full = os.path.join(dirpath, fn)
                rank = _icon_rank(full)
                key = stem.lower()
                prev = icon_best.get(key)
                if prev is None or rank > prev[0]:
                    icon_best[key] = (rank, full)

    icons_map = {k: v[1] for k, v in icon_best.items()}

    # 2. Index desktop entries with pre-resolved icon paths
    by_exact_id = {}
    by_lower_id = {}
    by_wmclass = {}
    by_webid = {}

    for app_dir in app_dirs:
        if not os.path.isdir(app_dir):
            continue
        try:
            names = sorted(fn for fn in os.listdir(app_dir) if fn.endswith(".desktop"))
        except OSError:
            continue
        for fn in names:
            parsed = _parse_desktop_file(os.path.join(app_dir, fn))
            if not parsed:
                continue
            resolved = _resolve_icon_name(parsed["icon"], icons_map)
            compact = {
                "name": parsed["name"],
                "icon": parsed["icon"],
                "iconPath": resolved,
                "noDisplay": parsed["noDisplay"],
            }
            eid = parsed["id"]
            eid_low = eid.lower()
            wm_low = parsed["wmClass"].lower()
            is_visible = not parsed["noDisplay"]

            if eid not in by_exact_id or (is_visible and by_exact_id[eid].get("noDisplay")):
                by_exact_id[eid] = compact
            if eid_low not in by_lower_id or (is_visible and by_lower_id[eid_low].get("noDisplay")):
                by_lower_id[eid_low] = compact
            if wm_low and (wm_low not in by_wmclass or (is_visible and by_wmclass[wm_low].get("noDisplay"))):
                by_wmclass[wm_low] = compact
            for wid in parsed["webIds"]:
                if wid not in by_webid:
                    by_webid[wid] = compact

    index = {
        "version": CACHE_VERSION,
        "fingerprint": fp,
        "icons": icons_map,
        "byExactId": by_exact_id,
        "byLowerId": by_lower_id,
        "byWmClass": by_wmclass,
        "byWebId": by_webid,
    }

    tmp_file = f"/tmp/omarchy-switcher-icons.{os.getpid()}.tmp"
    try:
        with open(tmp_file, "w", encoding="utf-8") as fh:
            json.dump(index, fh, separators=(",", ":"))
        os.chmod(tmp_file, 0o644)
        os.replace(tmp_file, cache_file)
    except OSError:
        try:
            if os.path.exists(tmp_file):
                os.unlink(tmp_file)
        except OSError:
            pass

    return index


def _humanize_class_name(cls):
    if not cls:
        return "Window"
    low = cls.lower().strip()
    if low in DISPLAY_NAME_OVERRIDES:
        return DISPLAY_NAME_OVERRIDES[low]

    m = BROWSER_WEBAPP_RE.match(cls)
    if m:
        domain = m.group(1).split("_")[0]
        parts = [p for p in domain.split(".") if p not in ("www", "app", "web", "com", "org", "io", "ai", "net", "dev")]
        if parts:
            return parts[0].capitalize()

    clean = cls.strip()
    if "." in clean:
        parts = clean.split(".")
        if parts[0].lower() in ("com", "org", "net", "io", "dev", "ai", "co", "app") and len(parts) >= 3:
            clean = parts[-1]
    clean = CLASS_SUFFIX_RE.sub("", clean)
    clean = CLASS_SEP_RE.sub(" ", clean).strip()
    if not clean:
        return "Window"
    if clean.islower():
        return " ".join(w.capitalize() for w in clean.split())
    return clean


def _make_monogram(app_name):
    words = [w for w in WORD_SPLIT_RE.split(app_name.strip()) if w]
    if not words:
        return "W"
    if len(words) == 1:
        return words[0][0].upper()
    return (words[0][0] + words[1][0]).upper()


def _accent_hue(key):
    # Deterministic FNV-1a 32-bit hash -> hue 0..359
    h = 2166136261
    for ch in (key or "window").lower().encode("utf-8"):
        h ^= ch
        h = (h * 16777619) & 0xFFFFFFFF
    return h % 360


def _resolve_desktop_and_icon(cls, initial_cls, index):
    icons_map = index.get("icons", {})
    by_exact = index.get("byExactId", {})
    by_lower = index.get("byLowerId", {})
    by_wm = index.get("byWmClass", {})
    by_web = index.get("byWebId", {})

    candidates = []
    for raw in (cls, initial_cls):
        c = str(raw or "").strip()
        if c.endswith(".desktop"):
            c = c[:-8]
        if c and c not in candidates:
            candidates.append(c)

    entry = None
    for c in candidates:
        entry = by_exact.get(c)
        if entry:
            break
    if entry is None:
        for c in candidates:
            low = c.lower()
            entry = by_wm.get(low)
            if entry:
                break
            m = BROWSER_WEBAPP_RE.match(c)
            if m:
                entry = by_web.get(m.group(1).lower())
                if entry:
                    break
    if entry is None:
        for c in candidates:
            low = c.lower()
            entry = by_lower.get(low)
            if entry:
                break
            if "." in low:
                entry = by_lower.get(low.rsplit(".", 1)[-1])
                if entry:
                    break

    app_name = ""
    for c in candidates:
        override = DISPLAY_NAME_OVERRIDES.get(c.lower())
        if override:
            app_name = override
            break
    if not app_name and entry and entry.get("name"):
        app_name = str(entry["name"]).strip()
    if not app_name:
        app_name = _humanize_class_name(candidates[0] if candidates else "")

    icon_path = ""
    if entry:
        icon_path = str(entry.get("iconPath") or "")
        if not icon_path and entry.get("icon"):
            icon_path = _resolve_icon_name(str(entry["icon"]), icons_map)

    if not icon_path:
        for c in candidates:
            low = c.lower()
            for alias in ICON_ALIASES.get(low, (low,)):
                icon_path = _resolve_icon_name(alias, icons_map)
                if icon_path:
                    break
            if icon_path:
                break

    if not icon_path and app_name:
        icon_path = _resolve_icon_name(app_name.lower().replace(" ", "-"), icons_map)

    return app_name, icon_path


def _canonical_app_key(cls, initial_cls, app_name):
    raw = (cls or initial_cls or app_name or "").strip().lower()
    if raw in ("brave-origin", "brave-origin-beta", "com.brave.origin", "com.brave.origin.beta", "brave-browser"):
        return "brave"
    if raw in ("com.mitchellh.ghostty", "ghostty"):
        return "ghostty"
    if raw in ("org.gnome.nautilus", "nautilus"):
        return "nautilus"
    if raw in ("foot", "footclient"):
        return "foot"
    return raw


def _workspace_label(ws_name, ws_id, minimized):
    if minimized:
        return "Shelf"
    name = str(ws_name or "").strip()
    if name.isdigit():
        return f"Desk {name}"
    if name:
        return name
    if ws_id > 0:
        return f"Desk {ws_id}"
    return "Desk"


def collect_switcher_data(same_app=False):
    sock = find_hypr_socket()
    clients = hypr_json(sock, "clients") or []
    active_win = hypr_json(sock, "activewindow") or {}
    active_ws = hypr_json(sock, "activeworkspace") or {}
    workspaces = hypr_json(sock, "workspaces") or []

    if not isinstance(clients, list):
        clients = []
    if not isinstance(active_win, dict):
        active_win = {}
    if not isinstance(active_ws, dict):
        active_ws = {}
    if not isinstance(workspaces, list):
        workspaces = []

    ws_name_by_id = {}
    for ws in workspaces:
        if isinstance(ws, dict) and "id" in ws:
            try:
                ws_name_by_id[int(ws["id"])] = str(ws.get("name") or ws["id"])
            except (TypeError, ValueError):
                pass

    index = _build_icon_and_desktop_index()

    active_addr = normalize_address(str(active_win.get("address") or ""))
    active_class = str(active_win.get("class") or active_win.get("initialClass") or "").strip()

    raw_rows = []
    for c in clients:
        if not isinstance(c, dict) or not c.get("mapped", False):
            continue
        addr = normalize_address(str(c.get("address") or ""))
        if not addr:
            continue

        ws = c.get("workspace") or {}
        ws_id = int(ws.get("id", 0)) if isinstance(ws, dict) else 0
        ws_name = str(ws.get("name") or ws_name_by_id.get(ws_id, "")).strip()

        is_special = ws_name.startswith("special:") or ws_id < 0
        is_minimized = ws_name in SHELF_WORKSPACES
        if is_special and not is_minimized:
            continue

        size = c.get("size")
        if isinstance(size, list) and len(size) >= 2 and size[0] == 0 and size[1] == 0:
            continue

        cls = str(c.get("class") or "").strip()
        initial_cls = str(c.get("initialClass") or "").strip()
        title = str(c.get("title") or "").strip()
        if not cls and not initial_cls and not title:
            continue

        app_name, icon_path = _resolve_desktop_and_icon(cls, initial_cls, index)
        if not title:
            title = app_name

        fhid_raw = c.get("focusHistoryID", 999999)
        try:
            fhid = int(fhid_raw)
        except (TypeError, ValueError):
            fhid = 999999
        if fhid < 0:
            fhid = 999999

        is_focused = bool(active_addr and addr == active_addr) or (not active_addr and fhid == 0 and not is_minimized)
        fhid_sort = -1 if (active_addr and addr == active_addr) else fhid

        ws_label = _workspace_label(ws_name, ws_id, is_minimized)
        app_key = _canonical_app_key(cls, initial_cls, app_name)

        item = {
            "address": addr,
            "class": cls or initial_cls,
            "appName": app_name,
            "title": title,
            "workspaceId": ws_id,
            "workspaceLabel": ws_label,
            "minimized": is_minimized,
            "focused": is_focused,
            "floating": bool(c.get("floating", False)),
            "iconPath": icon_path,
            "monogram": _make_monogram(app_name),
            "accentHue": _accent_hue(app_key or app_name),
            "_appKey": app_key,
        }
        sort_key = (fhid_sort, 1 if is_minimized else 0, ws_id if ws_id >= 0 else 9999, addr)
        raw_rows.append((sort_key, item))

    raw_rows.sort(key=lambda pair: pair[0])
    windows = [row[1] for row in raw_rows]

    active_app_name = ""
    active_app_key = ""
    if active_addr:
        for w in windows:
            if w["address"] == active_addr:
                active_class = active_class or w["class"]
                active_app_name = w["appName"]
                active_app_key = w["_appKey"]
                break
    if not active_app_key and active_class:
        active_app_name, _ = _resolve_desktop_and_icon(active_class, active_class, index)
        active_app_key = _canonical_app_key(active_class, active_class, active_app_name)
    if not active_app_key and windows:
        active_class = windows[0]["class"]
        active_app_name = windows[0]["appName"]
        active_app_key = windows[0]["_appKey"]

    if same_app and active_app_key:
        windows = [
            w for w in windows
            if w["_appKey"] == active_app_key
            or (active_app_name and w["appName"].lower() == active_app_name.lower())
        ]

    for w in windows:
        w.pop("_appKey", None)

    return {
        "activeAddress": active_addr,
        "activeClass": active_class,
        "activeAppName": active_app_name,
        "activeWorkspaceId": int(active_ws.get("id", 0)) if active_ws else 0,
        "sameApp": bool(same_app),
        "windows": windows,
    }


def _resolve_active_regular_workspace(sock_path):
    active_ws = hypr_json(sock_path, "activeworkspace")
    if isinstance(active_ws, dict):
        name = str(active_ws.get("name") or "").strip()
        ws_id = active_ws.get("id")
        if name and not name.startswith("special:"):
            return name
        if isinstance(ws_id, int) and ws_id > 0:
            return str(ws_id)

    monitors = hypr_json(sock_path, "monitors")
    if isinstance(monitors, list):
        for mon in monitors:
            if isinstance(mon, dict) and mon.get("focused"):
                aws = mon.get("activeWorkspace") or {}
                name = str(aws.get("name") or "").strip()
                if name and not name.startswith("special:"):
                    return name
                ws_id = aws.get("id")
                if isinstance(ws_id, int) and ws_id > 0:
                    return str(ws_id)
    return "1"


def focus_window(raw_address):
    addr = normalize_address(raw_address)
    if not addr:
        return 2
    sock = find_hypr_socket()
    clients = hypr_json(sock, "clients") or []

    is_minimized = False
    if isinstance(clients, list):
        for c in clients:
            if isinstance(c, dict) and normalize_address(str(c.get("address") or "")) == addr:
                ws = c.get("workspace") or {}
                ws_name = str(ws.get("name") or "").strip() if isinstance(ws, dict) else ""
                if ws_name in SHELF_WORKSPACES:
                    is_minimized = True
                break

    if is_minimized:
        target_ws = _resolve_active_regular_workspace(sock)
        hypr_dispatch(
            sock,
            f'hl.dsp.window.move({{ workspace = "{target_ws}", window = "address:{addr}", follow = true }})',
            f"movetoworkspace {target_ws},address:{addr}",
        )

    ok = hypr_dispatch(
        sock,
        f'hl.dsp.focus({{ window = "address:{addr}" }})',
        f"focuswindow address:{addr}",
    )
    hypr_dispatch(
        sock,
        f'hl.dsp.window.alter_zorder({{ mode = "top", window = "address:{addr}" }})',
        f"alterzorder top,address:{addr}",
    )
    return 0 if ok else 1


def close_window(raw_address):
    addr = normalize_address(raw_address)
    if not addr:
        return 2
    sock = find_hypr_socket()
    ok = hypr_dispatch(
        sock,
        f'hl.dsp.window.close({{ window = "address:{addr}" }})',
        f"closewindow address:{addr}",
    )
    return 0 if ok else 1


def hide_window(raw_address):
    addr = normalize_address(raw_address)
    if not addr:
        return 2
    sock = find_hypr_socket()
    ok = hypr_dispatch(
        sock,
        f'hl.dsp.window.move({{ workspace = "special:omarchy-minimized", window = "address:{addr}", follow = false }})',
        f"movetoworkspacesilent special:omarchy-minimized,address:{addr}",
    )
    return 0 if ok else 1


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    if not args or args[0] in ("-h", "--help"):
        sys.stdout.write(
            "Usage: SwitcherData.py --json [--same-app] | --focus <addr> | --close <addr> | --hide <addr>\n"
        )
        return 0

    mode = ""
    same_app = False
    target = ""
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--json":
            mode = "json"
        elif a == "--same-app":
            same_app = True
        elif a in ("--focus", "--close", "--hide") and i + 1 < len(args):
            mode = a[2:]
            target = args[i + 1]
            i += 1
        else:
            sys.stderr.write(f"SwitcherData.py: unrecognized argument '{a}'\n")
            return 2
        i += 1

    if mode == "json":
        data = collect_switcher_data(same_app=same_app)
        sys.stdout.write(json.dumps(data, ensure_ascii=False))
        sys.stdout.write("\n")
        return 0
    if mode == "focus":
        return focus_window(target)
    if mode == "close":
        return close_window(target)
    if mode == "hide":
        return hide_window(target)

    sys.stderr.write("SwitcherData.py: specify --json, --focus, --close, or --hide\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
