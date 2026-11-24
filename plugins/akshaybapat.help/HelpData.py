#!/usr/bin/env python3
"""Live data engine for the Omarchy Liquid Glass Shortcuts, Gestures & Help Center.

Pure Python standard library, <35ms typical wall time, zero dGPU wakes.
Modes:
  --json       Emit complete JSON payload for Help.qml
  --run <cmd>  Safely launch a validated detached command
"""

import json
import os
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
OMARCHY_PATH = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))
DEFAULT_BINDINGS_DIR = OMARCHY_PATH / "default" / "hypr" / "bindings"
USER_BINDINGS_FILE = HOME / ".config" / "hypr" / "bindings.lua"

MOD_BITS = {
    "SHIFT": 1,
    "CTRL": 4,
    "CONTROL": 4,
    "ALT": 8,
    "SUPER": 64,
    "META": 64,
}

MOD_ORDER = (
    (64, "Super"),
    (4, "Ctrl"),
    (8, "Alt"),
    (1, "Shift"),
)

KEYCODE_MAP = {
    "10": "1",
    "11": "2",
    "12": "3",
    "13": "4",
    "14": "5",
    "15": "6",
    "16": "7",
    "17": "8",
    "18": "9",
    "19": "0",
    "20": "-",
    "21": "=",
    "34": "[",
    "35": "]",
    "59": ",",
    "60": ".",
    "61": "/",
}

KEY_LABELS = {
    "RETURN": "↵",
    "ENTER": "↵",
    "SPACE": "Space",
    "TAB": "Tab",
    "ESCAPE": "Esc",
    "BACKSPACE": "⌫",
    "DELETE": "Del",
    "PRINT": "PrtSc",
    "HOME": "Home",
    "END": "End",
    "LEFT": "←",
    "RIGHT": "→",
    "UP": "↑",
    "DOWN": "↓",
    "COMMA": ",",
    "PERIOD": ".",
    "SLASH": "/",
    "BACKSLASH": "\\",
    "GRAVE": "`",
    "MINUS": "-",
    "EQUAL": "=",
    "ALT_R": "Right Alt",
    "ISO_LEVEL3_SHIFT": "Right Alt",
    "MOUSE:272": "Left Drag",
    "MOUSE:273": "Right Drag",
    "MOUSE:274": "Middle Click",
    "MOUSE_DOWN": "Scroll ↓",
    "MOUSE_UP": "Scroll ↑",
    "XF86AUDIORAISEVOLUME": "Vol +",
    "XF86AUDIOLOWERVOLUME": "Vol −",
    "XF86AUDIOMUTE": "Mute",
    "XF86AUDIOMICMUTE": "Mic Mute",
    "XF86MONBRIGHTNESSUP": "Bright +",
    "XF86MONBRIGHTNESSDOWN": "Bright −",
    "XF86KBDBRIGHTNESSUP": "Kbd +",
    "XF86KBDBRIGHTNESSDOWN": "Kbd −",
    "XF86KBDLIGHTONOFF": "Kbd Light",
    "XF86TOUCHPADTOGGLE": "Pad Toggle",
    "XF86TOUCHPADON": "Pad On",
    "XF86TOUCHPADOFF": "Pad Off",
    "XF86AUDIONEXT": "Next",
    "XF86AUDIOPREV": "Prev",
    "XF86AUDIOPLAY": "Play",
    "XF86AUDIOPAUSE": "Pause",
    "XF86EJECT": "Eject",
    "XF86POWEROFF": "Power",
    "XF86CALCULATOR": "Calc",
}

CATEGORIES = (
    {"id": "all", "label": "All", "fullLabel": "All Shortcuts"},
    {"id": "apps", "label": "Apps", "fullLabel": "Apps & Launchers"},
    {"id": "windows", "label": "Windows", "fullLabel": "Windows & Tiling"},
    {"id": "workspaces", "label": "Workspaces", "fullLabel": "Workspaces & Desks"},
    {"id": "ai", "label": "AI", "fullLabel": "AI & Productivity"},
    {"id": "capture", "label": "Capture & Media", "fullLabel": "Capture & Media"},
    {"id": "system", "label": "System", "fullLabel": "System & Hardware"},
)
CATEGORY_FULL_LABEL = {c["id"]: c["fullLabel"] for c in CATEGORIES}

# Never allow destructive or window-state-destructive commands to execute on click.
FORBIDDEN_ACTION_PATTERNS = (
    "omarchy-system-lock",
    "omarchy-system-shutdown",
    "omarchy-system-reboot",
    "omarchy-system-logout",
    "omarchy-system-suspend",
    "omarchy-system-hibernate",
    "systemctl poweroff",
    "systemctl reboot",
    "omarchy-hyprland-window-close",
    "omarchy-reminder clear",
    "omarchy-toggle-touchpad off",
    "omarchy-hyprland-monitor-internal",
    "notifications dismissAll",
    "notifications dismissOne",
    "notifications act",
    "super-shortcut",
    "smooth-volume-glide",
    "omarchy-dictation start",
    "omarchy-dictation stop",
    "eject",
    "rm -rf",
    "shutdown",
    "reboot",
    "poweroff",
    "loginctl",
)

FORBIDDEN_TITLE_SUBSTRINGS = (
    "lock system",
    "power menu",
    "shutdown",
    "reboot",
    "logout",
    "close window",
    "close all windows",
    "clear reminders",
    "disable touchpad",
    "toggle laptop display",
    "dismiss all",
    "dismiss last",
    "dismiss, invoke",
    "eject media",
    "push-to-talk",
    "cut",
    "undo",
    "redo",
    "select all",
    "universal copy",
    "universal paste",
    "new window",
)

DELAYED_CAPTURE_TOKENS = (
    "omarchy-shot",
    "omarchy-capture",
    "rollingshot",
    "hyprpicker",
    "wayscriber",
)


def detect_hypr_session():
    """Resolve HYPRLAND_INSTANCE_SIGNATURE and hypr runtime directory."""
    env = os.environ.copy()
    runtime_dir = env.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    extra_paths = (
        str(HOME / ".local" / "bin"),
        str(HOME / ".local" / "share" / "mise" / "shims"),
        str(HOME / ".local" / "share" / "mise" / "installs" / "codex" / "latest" / "bin"),
        str(OMARCHY_PATH / "bin"),
        "/usr/local/bin",
        "/usr/bin",
    )
    path_parts = [p for p in env.get("PATH", "").split(":") if p]
    for p in extra_paths:
        if p not in path_parts and os.path.isdir(p):
            path_parts.insert(0, p)
    env["PATH"] = ":".join(path_parts)

    hypr_base = os.path.join(runtime_dir, "hypr")
    his = env.get("HYPRLAND_INSTANCE_SIGNATURE", "").strip()
    if his:
        hdir = os.path.join(hypr_base, his)
        if os.path.isdir(hdir):
            return env, hdir

    if os.path.isdir(hypr_base):
        entries = []
        try:
            with os.scandir(hypr_base) as it:
                for e in it:
                    if e.is_dir():
                        has_sock = os.path.exists(os.path.join(e.path, ".socket.sock"))
                        entries.append((has_sock, e.stat().st_mtime, e.name, e.path))
        except OSError:
            entries = []
        if entries:
            entries.sort(reverse=True)
            env["HYPRLAND_INSTANCE_SIGNATURE"] = entries[0][2]
            return env, entries[0][3]
    return env, ""


def query_unix_socket(sock_path: str, payload: str, timeout: float = 0.5, single_read: bool = False):
    if not sock_path or not os.path.exists(sock_path):
        return None
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect(sock_path)
            s.sendall(payload.encode("utf-8"))
            if single_read:
                buf = s.recv(4096)
                return buf.decode("utf-8", errors="replace").strip()
            chunks = []
            while True:
                buf = s.recv(65536)
                if not buf:
                    break
                chunks.append(buf)
        return b"".join(chunks).decode("utf-8", errors="replace").strip()
    except OSError:
        return None


def run_cmd_capture(args, env, timeout: float = 1.0):
    try:
        res = subprocess.run(
            args,
            env=env,
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


def parse_chord(keys_expr: str):
    modmask = 0
    key = ""
    for part in keys_expr.split("+"):
        token = part.strip()
        if not token:
            continue
        bit = MOD_BITS.get(token.upper())
        if bit:
            modmask |= bit
        else:
            key = token
    return modmask, key


def normalize_raw_key(raw_key: str, keycode: int = 0) -> str:
    key = (raw_key or "").strip()
    if " + " in key:
        key = key.split(" + ")[-1].strip()
    if not key and keycode:
        key = f"code:{keycode}"
    if key.lower().startswith("code:"):
        code = key[5:]
        if code == "201":
            return "code:201"
        return KEYCODE_MAP.get(code, f"code:{code}")
    return key


def format_key_label(raw_key: str) -> str:
    if not raw_key:
        return ""
    if raw_key in ("1–0", "1–5", "1–9"):
        return raw_key
    upper = raw_key.upper()
    if upper in KEY_LABELS:
        return KEY_LABELS[upper]
    if len(raw_key) == 1:
        return raw_key.upper()
    if upper.startswith("F") and upper[1:].isdigit():
        return upper
    return raw_key


def build_keycaps(modmask: int, raw_key: str):
    caps = [label for bit, label in MOD_ORDER if modmask & bit]
    key_label = format_key_label(raw_key)
    if key_label:
        caps.append(key_label)
    return caps


def resolve_lua_action(raw_expr: str) -> str:
    expr = raw_expr.strip()
    if not expr:
        return ""
    if expr.startswith("[[") and expr.endswith("]]"):
        return expr[2:-2].strip()
    if len(expr) >= 2 and expr[0] == '"' and expr[-1] == '"':
        return expr[1:-1].replace('\\"', '"').replace("\\\\", "\\").strip()
    if len(expr) >= 2 and expr[0] == "'" and expr[-1] == "'":
        return expr[1:-1].replace("\\'", "'").replace("\\\\", "\\").strip()
    if expr.startswith("o.launch_terminal"):
        return 'ghostty --working-directory="$(omarchy-cmd-terminal-cwd)"'

    m = re.search(r'hl\.dsp\.global\(\s*["\']([^"\']+)["\']\s*\)', expr)
    if m:
        return f"hyprctl dispatch global {m.group(1)}"

    m = re.search(r'hl\.dsp\.workspace\.toggle_special\(\s*["\']([^"\']+)["\']\s*\)', expr)
    if m:
        return f"hyprctl dispatch togglespecialworkspace {m.group(1)}"

    if expr.startswith("{") and expr.endswith("}"):
        m = re.search(r'menu\s*=\s*["\']([^"\']+)["\']', expr)
        if m:
            return f"omarchy-menu toggle {m.group(1)}"
        m = re.search(r'panel\s*=\s*["\']([^"\']+)["\']', expr)
        if m:
            return f"omarchy-shell shell toggle {m.group(1)}"
        m = re.search(r'tui\s*=\s*["\']([^"\']+)["\']', expr)
        if m:
            return f"omarchy-launch-tui {m.group(1)}"
        m = re.search(r'ipc\s*=\s*["\']([^"\']+)["\']', expr)
        if m:
            target, _, method = m.group(1).partition(".")
            if target and method:
                return f"omarchy-shell -q {target} {method}"
        m = re.search(r'omarchy\s*=\s*["\']([^"\']+)["\']', expr)
        if m:
            val = m.group(1)
            if val.startswith("browser"):
                return f"omarchy-launch-{val}"
            if val == "nautilus":
                return "nautilus --new-window"
            if val == "editor":
                return "omarchy-launch-editor"
            if val == "spotify":
                return "omarchy-launch-or-focus spotify"
            if val == "signal":
                return "omarchy-launch-or-focus ^signal$ signal-desktop"
            if val == "1password":
                return "1password"
        m = re.search(r'webapp\s*=\s*["\']([^"\']+)["\']', expr)
        if m:
            return f'omarchy-launch-webapp "{m.group(1)}"'
        m = re.search(r'launch\s*=\s*["\']([^"\']+)["\']', expr)
        if m:
            return m.group(1)
    return ""


def _split_top_level_args(arg_str: str):
    args = []
    buf = []
    depth_paren = 0
    depth_brace = 0
    in_str = None
    in_long = False
    i = 0
    n = len(arg_str)
    while i < n:
        ch = arg_str[i]
        if in_long:
            if ch == "]" and i + 1 < n and arg_str[i + 1] == "]":
                buf.append("]]")
                in_long = False
                i += 2
                continue
            buf.append(ch)
            i += 1
            continue
        if in_str:
            buf.append(ch)
            if ch == "\\" and i + 1 < n:
                buf.append(arg_str[i + 1])
                i += 2
                continue
            if ch == in_str:
                in_str = None
            i += 1
            continue
        if ch == "[" and i + 1 < n and arg_str[i + 1] == "[":
            in_long = True
            buf.append("[[")
            i += 2
            continue
        if ch in ('"', "'"):
            in_str = ch
            buf.append(ch)
            i += 1
            continue
        if ch == "(":
            depth_paren += 1
        elif ch == ")":
            depth_paren = max(0, depth_paren - 1)
        elif ch == "{":
            depth_brace += 1
        elif ch == "}":
            depth_brace = max(0, depth_brace - 1)
        elif ch == "," and depth_paren == 0 and depth_brace == 0:
            args.append("".join(buf).strip())
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    tail = "".join(buf).strip()
    if tail:
        args.append(tail)
    return args


def _unquote(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ('"', "'"):
        return s[1:-1]
    if s.startswith("[[") and s.endswith("]]"):
        return s[2:-2]
    return s


def parse_lua_binding_files():
    by_mod_desc = {}
    by_mod_key = {}
    ordered = []

    files = []
    if DEFAULT_BINDINGS_DIR.is_dir():
        for name in (
            "applications.lua",
            "clipboard.lua",
            "dictation.lua",
            "input-method.lua",
            "media.lua",
            "tiling.lua",
            "utilities.lua",
        ):
            p = DEFAULT_BINDINGS_DIR / name
            if p.is_file():
                files.append((p, "default"))
    if USER_BINDINGS_FILE.is_file():
        files.append((USER_BINDINGS_FILE, "user"))

    for ws in range(1, 11):
        norm = normalize_raw_key(f"code:{ws + 9}")
        for modmask, desc in (
            (64, f"Switch to workspace {ws}"),
            (65, f"Move window to workspace {ws}"),
            (73, f"Move window silently to workspace {ws}"),
        ):
            entry = {
                "modmask": modmask,
                "key": norm,
                "description": desc,
                "action": "",
                "source": "default",
            }
            by_mod_desc[(modmask, desc)] = entry
            by_mod_key[(modmask, norm.upper())] = entry

    for idx in range(1, 6):
        norm = normalize_raw_key(f"code:{idx + 9}")
        desc = f"Switch to group window {idx}"
        entry = {
            "modmask": 72,
            "key": norm,
            "description": desc,
            "action": "",
            "source": "default",
        }
        by_mod_desc[(72, desc)] = entry
        by_mod_key[(72, norm.upper())] = entry

    for panel in range(1, 10):
        norm = normalize_raw_key(f"code:{panel + 9}")
        desc = f"Bar panel {panel}"
        entry = {
            "modmask": 68,
            "key": norm,
            "description": desc,
            "action": f"omarchy-shell -q shell togglePanelAt right {panel}",
            "source": "default",
        }
        by_mod_desc[(68, desc)] = entry
        by_mod_key[(68, norm.upper())] = entry

    call_re = re.compile(r"^(o\.bind_toggle|o\.bind_hold|o\.bind|replace)\s*\((.*)\)\s*$")
    start_re = re.compile(r"^(o\.bind_toggle|o\.bind_hold|o\.bind|replace)\s*\(")

    for path, source in files:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        lines = text.splitlines()
        idx = 0
        total_lines = len(lines)
        while idx < total_lines:
            raw_line = lines[idx].strip()
            idx += 1
            if not raw_line or raw_line.startswith("--") or not start_re.match(raw_line):
                continue

            stmt = raw_line
            while stmt.count("(") > stmt.count(")") and idx < total_lines:
                nxt = lines[idx].strip()
                idx += 1
                if nxt.startswith("--"):
                    continue
                stmt += " " + nxt

            m = call_re.match(stmt)
            if not m:
                continue
            fn_name, arg_blob = m.group(1), m.group(2)
            args = _split_top_level_args(arg_blob)
            if len(args) < 3:
                continue
            keys_raw = _unquote(args[0])
            desc_raw = _unquote(args[1])
            if not keys_raw or not desc_raw or desc_raw == "nil":
                continue
            if ".." in keys_raw or "tostring(" in keys_raw:
                continue

            modmask, raw_key = parse_chord(keys_raw)
            norm_key = normalize_raw_key(raw_key)
            if not norm_key:
                continue

            if fn_name == "o.bind_toggle":
                toggle_name = _unquote(args[2])
                action = f"omarchy-toggle-{toggle_name}" if toggle_name else ""
            else:
                action = resolve_lua_action(args[2])

            entry = {
                "modmask": modmask,
                "key": norm_key,
                "description": desc_raw,
                "action": action,
                "source": source,
            }
            by_mod_desc[(modmask, desc_raw)] = entry
            by_mod_key[(modmask, norm_key.upper())] = entry
            ordered.append(entry)

    return by_mod_desc, by_mod_key, ordered


def is_safe_action(title: str, action: str) -> bool:
    if not action or not action.strip():
        return False
    low_title = title.lower()
    for bad in FORBIDDEN_TITLE_SUBSTRINGS:
        if bad in low_title:
            return False
    low_cmd = action.lower()
    for bad in FORBIDDEN_ACTION_PATTERNS:
        if bad in low_cmd:
            return False
    return True


def needs_capture_delay(action: str) -> int:
    low = action.lower()
    for tok in DELAYED_CAPTURE_TOKENS:
        if tok in low:
            return 140
    return 0


def categorize_shortcut(title: str, key: str, action: str) -> str:
    t = title.lower()
    k = key.upper()
    a = action.lower()

    if (
        t.startswith("ai ")
        or "claude" in t
        or "codex" in t
        or "opencode" in t
        or "hermes" in t
        or "agent" in t
        or "dictation" in t
        or "reminder" in t
        or "obsidian" in t
        or "typora" in t
        or "calendar" in t
        or "email" in t
        or "emoji" in t
        or "clipboard" in t
        or "notes" in t
        or "spend" in t
        or "ask" in t
        or t in ("cut", "undo", "redo", "select all", "universal copy", "universal paste")
    ):
        return "ai"

    if (
        "workspace" in t
        or "overview" in t
        or "hidden window" in t
        or "hide window" in t
        or "quake console" in t
        or "scratchpad" in t
        or "monitor" in t
        or "control laptop display" in t
        or "control tv display" in t
    ):
        return "workspaces"

    if (
        "screenshot" in t
        or "screenrecording" in t
        or "color picker" in t
        or "ocr" in t
        or "annotate" in t
        or "capture" in t
        or "webcam" in t
        or "transcode" in t
        or t == "share"
        or "music" in t
        or "spotify" in t
        or "youtube" in t
        or "volume" in t
        or "mute" in t
        or "track" in t
        or "audio" in t
        or "media" in t
        or t in ("play", "pause")
        or k.startswith("XF86AUDIO")
        or k == "PRINT"
    ):
        return "capture"

    if (
        t in (
            "search apps",
            "search everything",
            "terminal",
            "tmux",
            "browser",
            "browser (private)",
            "file manager",
            "file manager (cwd)",
            "editor",
            "docker",
            "signal",
            "1password",
            "whatsapp",
            "google messages",
            "google photos",
            "x",
            "x post",
            "calculator",
            "activity",
            "omarchy menu",
        )
        or "launch" in a
    ):
        return "apps"

    if (
        "window" in t
        or "full screen" in t
        or "full width" in t
        or "pseudo" in t
        or "split" in t
        or "group" in t
        or "focus on" in t
        or "swap " in t
        or "resize" in t
        or "shrink " in t
        or "expand " in t
        or "pop window" in t
        or "square aspect" in t
        or "transparency" in t
        or "gaps" in t
        or "terminal prefix" in t
    ):
        return "windows"

    return "system"


EXACT_PRIORITY = {
    "search apps": 1,
    "full omarchy menu": 2,
    "search everything": 3,
    "overview": 4,
    "switch windows": 5,
    "switch same app windows": 6,
    "shortcuts & help": 7,
    "keybindings": 8,
    "terminal": 9,
    "browser": 7,
    "file manager": 8,
    "ai claude code": 9,
    "ai codex": 10,
    "ai quick ask": 11,
    "screenshot region (copy + save)": 12,
    "hide window": 13,
    "show hidden windows": 14,
    "close window": 15,
    "full screen": 16,
    "toggle window floating/tiling": 17,
    "clipboard manager": 18,
    "switch to workspace 1–10": 19,
    "next workspace": 20,
    "previous workspace": 21,
    "move window to workspace 1–10": 22,
    "toggle ai spend widget": 23,
    "claude code": 24,
    "codex": 25,
    "ai opencode": 26,
    "ai hermes": 27,
    "tmux": 28,
    "editor": 29,
    "obsidian": 30,
    "1password": 31,
    "music (auto)": 32,
    "spotify": 33,
    "rolling screenshot": 34,
    "wayscriber annotate": 35,
    "extract text (ocr) from screenshot": 36,
    "color picker": 37,
    "theme menu": 38,
    "background picker": 39,
    "aether wallpaper to theme": 40,
    "toggle dictation": 41,
    "audio": 42,
    "bluetooth": 43,
    "network": 44,
    "display": 45,
    "power": 46,
    "activity": 47,
    "calculator": 48,
    "system & power menu": 49,
    "lock system": 50,
}


def shortcut_priority(title: str, modmask: int, key: str, source: str) -> int:
    t = title.lower()
    if t in EXACT_PRIORITY:
        if t == "browser" and key.upper() == "B":
            return 27
        if t == "screenshot region (copy + save)" and key.upper() == "S":
            return 13
        if t == "hide window" and modmask != 64:
            return 45
        if t == "close window" and key.upper() == "Q":
            return 35
        return EXACT_PRIORITY[t]
    if key.upper().startswith("XF86"):
        return 85
    if source == "user":
        return 52
    return 65


def build_shortcuts(raw_binds_json, by_mod_desc, by_mod_key, lua_fallback):
    raw_binds = []
    if raw_binds_json:
        try:
            parsed = json.loads(raw_binds_json)
            if isinstance(parsed, list):
                raw_binds = parsed
        except ValueError:
            raw_binds = []

    normalized_rows = []
    if raw_binds:
        for b in raw_binds:
            if b.get("release"):
                continue
            desc = (b.get("description") or "").strip()
            if not desc or desc == "Reveal active window on top":
                continue
            modmask = int(b.get("modmask") or 0)
            raw_key = normalize_raw_key(str(b.get("key") or ""), int(b.get("keycode") or 0))
            if raw_key.startswith("switch:"):
                continue

            lua_meta = by_mod_desc.get((modmask, desc))
            if not raw_key and lua_meta:
                raw_key = lua_meta["key"]
            if not raw_key or raw_key == "code:201":
                continue

            key_meta = by_mod_key.get((modmask, raw_key.upper()))
            action = ""
            source = "default"
            if lua_meta:
                action = lua_meta.get("action", "")
                source = lua_meta.get("source", "default")
            elif key_meta:
                action = key_meta.get("action", "")
                source = key_meta.get("source", "default")
            elif b.get("dispatcher") == "exec" and b.get("arg"):
                action = str(b["arg"]).strip()

            normalized_rows.append(
                {
                    "modmask": modmask,
                    "rawKey": raw_key,
                    "title": desc,
                    "action": action,
                    "source": source,
                }
            )
    else:
        for e in lua_fallback:
            if e["key"] == "code:201" or e["key"].startswith("switch:"):
                continue
            normalized_rows.append(
                {
                    "modmask": e["modmask"],
                    "rawKey": e["key"],
                    "title": e["description"],
                    "action": e["action"],
                    "source": e["source"],
                }
            )

    deduped_map = {}
    for row in normalized_rows:
        deduped_map[(row["modmask"], row["rawKey"].upper())] = row

    range_specs = (
        (re.compile(r"^Switch to workspace (\d+)$"), 64, "1–0", "Switch to workspace 1–10", "1 2 3 4 5 6 7 8 9 0 10 desk desktop"),
        (re.compile(r"^Move window to workspace (\d+)$"), 65, "1–0", "Move window to workspace 1–10", "1 2 3 4 5 6 7 8 9 0 10 desk send"),
        (re.compile(r"^Move window silently to workspace (\d+)$"), 73, "1–0", "Move window silently to workspace 1–10", "1 2 3 4 5 6 7 8 9 0 10 desk background"),
        (re.compile(r"^Switch to group window (\d+)$"), 72, "1–5", "Switch to group window 1–5", "1 2 3 4 5 tab stack"),
        (re.compile(r"^Bar panel (\d+)$"), 68, "1–9", "Open top bar panel 1–9", "1 2 3 4 5 6 7 8 9 widget popup"),
    )
    emitted_ranges = set()
    shortcuts = []

    for row in deduped_map.values():
        title = row["title"]
        modmask = row["modmask"]
        raw_key = row["rawKey"]
        action = row["action"]
        source = row["source"]
        extra_search = ""

        skip_row = False
        for regex, expected_mod, range_key, range_title, search_extra in range_specs:
            if modmask == expected_mod and regex.match(title):
                if range_title in emitted_ranges:
                    skip_row = True
                    break
                emitted_ranges.add(range_title)
                title = range_title
                raw_key = range_key
                action = ""
                extra_search = search_extra
                break
        if skip_row:
            continue

        caps = build_keycaps(modmask, raw_key)
        if not caps:
            continue

        # Disambiguate Omarchy root menu vs system/power menu for clarity
        if title == "System menu" and "toggle root" in action:
            title = "Full Omarchy menu"
        elif title == "System menu" and "toggle system" in action:
            title = "System & power menu"

        cat_id = categorize_shortcut(title, raw_key, action)
        cat_full = CATEGORY_FULL_LABEL.get(cat_id, "System & Hardware")
        runnable = is_safe_action(title, action)
        safe_action = action if runnable else ""
        delay_ms = needs_capture_delay(safe_action) if runnable else 0
        prio = shortcut_priority(title, modmask, raw_key, source)
        keys_text = " + ".join(caps)

        search_blob = (
            f"{title} {keys_text} {' '.join(caps)} {raw_key} {cat_id} {cat_full} {safe_action} {extra_search}"
        ).lower()

        shortcuts.append(
            {
                "id": f"sc-{modmask}-{raw_key.lower()}",
                "keys": caps,
                "keysText": keys_text,
                "title": title,
                "category": cat_id,
                "categoryLabel": cat_full,
                "action": safe_action,
                "runnable": runnable,
                "delayMs": delay_ms,
                "priority": prio,
                "source": source,
                "searchBlob": search_blob,
            }
        )

    shortcuts.sort(key=lambda x: (x["priority"], x["title"].lower(), x["keysText"]))
    return shortcuts


def build_gestures():
    items = [
        {
            "id": "gesture-overview-open",
            "title": "3 Fingers Up",
            "context": "Trackpad",
            "gestureType": "swipe-up",
            "fingers": 3,
            "description": "Open live finger-tracking Workspace Overview — cards follow your fingers 1:1.",
            "keywords": "overview mission control workspaces spaces expose three fingers swipe up vertical",
        },
        {
            "id": "gesture-overview-close",
            "title": "3 Fingers Down",
            "context": "Trackpad",
            "gestureType": "swipe-down",
            "fingers": 3,
            "description": "Close Workspace Overview smoothly and enter the selected or empty desk.",
            "keywords": "close overview dismiss exit three fingers swipe down vertical",
        },
        {
            "id": "gesture-overview-scroll",
            "title": "2 Fingers Left / Right",
            "context": "In Overview",
            "gestureType": "swipe-lr",
            "fingers": 2,
            "description": "Glide across all desks — including empty desks and the + New desk slot.",
            "keywords": "two fingers horizontal scroll desks empty new desk overview",
        },
        {
            "id": "gesture-overview-drag",
            "title": "Drag Window / Drag Desk",
            "context": "In Overview",
            "gestureType": "drag",
            "fingers": 1,
            "description": "Move any window onto another desk or reorder entire desks by dragging.",
            "keywords": "drag drop reorder move window desk overview arrange",
        },
        {
            "id": "gesture-workspace-switch",
            "title": "3 Fingers Left / Right",
            "context": "Trackpad",
            "gestureType": "swipe-lr",
            "fingers": 3,
            "description": "Switch smoothly to the previous or next desktop workspace.",
            "keywords": "three fingers horizontal workspace switch next previous swipe",
        },
        {
            "id": "gesture-window-carry",
            "title": "4 Fingers Left / Right",
            "context": "Trackpad",
            "gestureType": "swipe-lr",
            "fingers": 4,
            "description": "Carry the active window along with you to the previous or next desktop.",
            "keywords": "four fingers carry move active window workspace horizontal swipe",
        },
        {
            "id": "gesture-pinch-apps",
            "title": "3 Fingers Pinch Out",
            "context": "Trackpad",
            "gestureType": "pinch-out",
            "fingers": 3,
            "description": "Quick-open the Apps search launcher straight from anywhere.",
            "keywords": "three fingers pinch out spread apps search launcher menu",
        },
        {
            "id": "gesture-pinch-in-everything",
            "title": "3 Fingers Pinch In",
            "context": "Trackpad",
            "gestureType": "pinch-in",
            "fingers": 3,
            "description": "Open Search Everything across open windows, browser tabs, agents & files.",
            "keywords": "three fingers pinch in search everything spotlight tabs windows files",
        },
        {
            "id": "gesture-pinch-empty",
            "title": "4 Fingers Pinch Out",
            "context": "Trackpad",
            "gestureType": "pinch-out",
            "fingers": 4,
            "description": "Jump straight to a fresh empty desktop workspace for focused work.",
            "keywords": "four fingers pinch out empty workspace fresh desktop clean",
        },
        {
            "id": "gesture-pinch-in-shelf",
            "title": "4 Fingers Pinch In",
            "context": "Trackpad",
            "gestureType": "pinch-in",
            "fingers": 4,
            "description": "Tuck the active window cleanly onto the Top-Bar Window Shelf.",
            "keywords": "four fingers pinch in hide minimize window shelf top bar",
        },
        {
            "id": "gesture-quick-look",
            "title": "Spacebar in Files",
            "context": "Files App",
            "gestureType": "spacebar",
            "fingers": 0,
            "description": "macOS-style instant Quick Look preview (sushi) for images, PDFs, videos & text.",
            "keywords": "spacebar quick look sushi nautilus files preview pdf image video",
        },
        {
            "id": "gesture-logo-clicks",
            "title": "Top-Left Omarchy Logo",
            "context": "Top Bar",
            "gestureType": "mouse-clicks",
            "fingers": 0,
            "description": "Left-click = Full Omarchy Menu · Middle-click = Apps Search · Right-click = Terminal.",
            "keywords": "omarchy logo top left click menu apps terminal mouse bar",
        },
    ]
    for g in items:
        g["searchBlob"] = f"{g['title']} {g['context']} {g['description']} {g['keywords']}".lower()
    return items


def read_text_file(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="ignore").strip()
    except OSError:
        return ""


def read_cpu_package_temp_c():
    """Safely read CPU package temperature via hwmon coretemp (never debugfs/regmap!)."""
    hwmon_root = Path("/sys/class/hwmon")
    if not hwmon_root.is_dir():
        return None
    for d in sorted(hwmon_root.iterdir()):
        if read_text_file(d / "name") != "coretemp":
            continue
        for label_file in sorted(d.glob("temp*_label")):
            if "package" in read_text_file(label_file).lower():
                input_file = label_file.with_name(label_file.name.replace("_label", "_input"))
                raw = read_text_file(input_file)
                if raw.isdigit():
                    return int(raw) / 1000.0
        fallback = read_text_file(d / "temp1_input")
        if fallback.isdigit():
            return int(fallback) / 1000.0
    return None


def read_codex_version(env) -> str:
    # Zero-fork fast path via mise symlink (matches codex --version identically)
    mise_latest = HOME / ".local" / "share" / "mise" / "installs" / "codex" / "latest"
    if mise_latest.exists():
        resolved = os.path.basename(os.path.realpath(mise_latest))
        if re.match(r"^\d+\.\d+(?:\.\d+)?", resolved):
            return resolved
    out = run_cmd_capture(["codex", "--version"], env, timeout=0.8)
    if out:
        m = re.search(r"(\d+\.\d+(?:\.\d+)?)", out)
        if m:
            return m.group(1)
    return ""


def read_nightlight_status(hypr_dir: str, env):
    # Direct UNIX socket read (<0.2ms) matching omarchy-toggle-nightlight --status
    if hypr_dir:
        raw = query_unix_socket(
            os.path.join(hypr_dir, ".hyprsunset.sock"),
            "temperature",
            timeout=0.3,
            single_read=True,
        )
        if raw:
            m = re.search(r"(\d+)", raw)
            if m:
                temp = int(m.group(1))
                return temp < 6000, temp
    out = run_cmd_capture(["/usr/share/omarchy/bin/omarchy-toggle-nightlight", "--status"], env, timeout=0.8)
    if out:
        try:
            obj = json.loads(out)
            return bool(obj.get("enabled")), obj.get("temperature")
        except ValueError:
            pass
    return False, None


def count_screenshots() -> int:
    env_dir = os.environ.get("OMARCHY_SCREENSHOT_DIR", "")
    candidates = [
        Path(env_dir) if env_dir else None,
        HOME / "Pictures" / "Screenshots",
        HOME / "Pictures",
    ]
    exts = {".png", ".jpg", ".jpeg", ".webp"}
    for folder in candidates:
        if folder and folder.is_dir():
            count = 0
            try:
                with os.scandir(folder) as it:
                    for entry in it:
                        if entry.is_file() and os.path.splitext(entry.name)[1].lower() in exts:
                            count += 1
                return count
            except OSError:
                continue
    return 0


def build_tools(default_sink, workspaces_json, clients_json, codex_ver, nl_enabled, nl_temp):
    # 1. Studio & 3D Speaker Audio
    sink = (default_sink or "").strip()
    spatial_bin = HOME / ".local" / "bin" / "omarchy-audio-spatial"
    speaker_profile = read_text_file(HOME / ".local" / "state" / "omarchy" / "speaker-profile") or "studio-deep"
    if sink == "omarchy_speaker_studio":
        audio_status, audio_tone = "Studio Deep", "ok"
        audio_metric = "AVX2/FMA 7-stage Studio DSP · 82 Hz Klippel bass + ISO 226 live"
    elif sink == "omarchy_speaker_studio_spatial":
        audio_status, audio_tone = "Studio Spatial", "ok"
        audio_metric = "Wide 3D FDTR-XTC cinema stage + anchored physical & harmonic bass"
    elif sink == "omarchy_speaker_studio_ref":
        audio_status, audio_tone = "Studio Reference", "ok"
        audio_metric = "Harman/Olive neutral reference FIR · Klippel excursion guard"
    elif sink == "omarchy_speaker_studio_voice":
        audio_status, audio_tone = "Studio Voice", "ok"
        audio_metric = "Ultra-clear speech & podcast articulation · 95 Hz bass floor"
    elif sink == "omarchy_speaker_spatial":
        audio_status, audio_tone = "Legacy Spatial", "accent"
        audio_metric = "Choueiri FDTR-XTC 2×2 stereo soundstage · Zero mic monitor"
    elif sink == "omarchy_speaker_spatial_71":
        audio_status, audio_tone = "7.1 SOFA Active", "ok"
        audio_metric = "MIT KEMAR 7.1 virtual surround + FDTR-XTC active"
    elif sink in ("easyeffects_sink", "omarchy_speaker_engine") or "warm" in sink:
        audio_status, audio_tone = f"Warm ({speaker_profile})", "accent"
        audio_metric = f"Built-in speaker DSP active · Profile: {speaker_profile}"
    elif sink:
        audio_status, audio_tone = "External Output", "muted"
        audio_metric = f"Active sink: {sink}"
    else:
        audio_status, audio_tone = ("Ready" if spatial_bin.is_file() else "Unavailable"), "muted"
        audio_metric = "XPS 17 9720 Studio Audio DSP (Deep, Spatial, Reference, Voice)"

    # 2. Battery Care
    bat_dir = Path("/sys/class/power_supply/BAT0")
    bat_cap = read_text_file(bat_dir / "capacity")
    bat_state = read_text_file(bat_dir / "status")
    bat_start = read_text_file(bat_dir / "charge_control_start_threshold")
    bat_end = read_text_file(bat_dir / "charge_control_end_threshold")
    travel_active = Path("/run/omarchy-battery-cap.travel").exists() or (bat_end.isdigit() and int(bat_end) >= 95)

    health_str = ""
    for full_name, design_name in (("charge_full", "charge_full_design"), ("energy_full", "energy_full_design")):
        f_raw = read_text_file(bat_dir / full_name)
        d_raw = read_text_file(bat_dir / design_name)
        if f_raw.isdigit() and d_raw.isdigit() and int(d_raw) > 0:
            health_str = f" · Health {round(int(f_raw) * 100 / int(d_raw))}%"
            break

    if not bat_dir.is_dir():
        bat_status, bat_tone = "Desktop AC", "muted"
        bat_metric = "No internal battery sensor detected"
    elif travel_active:
        bat_status, bat_tone = "Travel 100%", "warn"
        bat_metric = f"{bat_cap or '?'}% ({bat_state or 'AC'}) · Full 100% travel charge{health_str}"
    else:
        bat_status, bat_tone = f"Desk {bat_start or '55'}–{bat_end or '80'}%", "ok"
        bat_metric = f"{bat_cap or '?'}% ({bat_state or 'AC'}) · Longevity cap active{health_str}"

    # 3. Workspace Overview
    desk_count = 0
    win_count = 0
    hidden_count = 0
    try:
        if workspaces_json:
            ws = json.loads(workspaces_json)
            desk_count = sum(1 for w in ws if int(w.get("id", 0)) > 0)
        if clients_json:
            cls = json.loads(clients_json)
            win_count = len(cls)
            hidden_count = sum(
                1 for c in cls if str((c.get("workspace") or {}).get("name", "")) == "special:omarchy-minimized"
            )
    except (ValueError, TypeError):
        pass
    ov_extra = f" · {hidden_count} hidden" if hidden_count else ""
    ov_metric = (
        f"{desk_count} active desks · {win_count} windows{ov_extra} · 3-finger swipe up"
        if desk_count
        else "Live finger-tracking overview · Drag windows & reorder desks"
    )

    # 4. Search Everything
    ev_exists = (HOME / ".local" / "bin" / "everythingd").is_file()
    ev_status = "Daemon Ready" if ev_exists else "Plugin Ready"
    ev_tone = "ok" if ev_exists else "accent"

    # 5. Hardware Vitals
    vitals_exists = (HOME / ".local" / "bin" / "vitalsd").is_file()
    cpu_temp = read_cpu_package_temp_c()
    if cpu_temp is not None:
        vit_status = f"{round(cpu_temp)}°C CPU"
        vit_tone = "warn" if cpu_temp >= 78 else "ok"
        vit_metric = f"Rust vitalsd {'ready' if vitals_exists else 'available'} · Safe iGPU sensors · Zero dGPU wake"
    else:
        vit_status = "Ready" if vitals_exists else "Standby"
        vit_tone = "ok" if vitals_exists else "muted"
        vit_metric = "Live CPU, RAM, disk, network & safe sensor telemetry"

    # 6. Screenshot Manager
    shot_exists = (HOME / ".local" / "bin" / "screenshotd").is_file()
    shot_count = count_screenshots()
    shot_status = f"{shot_count} Captures" if shot_count > 0 else ("Ready" if shot_exists else "Standby")
    shot_tone = "ok" if shot_exists else "accent"

    # 7. ChatGPT Desktop & Codex
    gpt_ver = ""
    meta_path = Path("/usr/lib/chatgpt/resources/linux-package-metadata.json")
    if meta_path.is_file():
        try:
            gpt_ver = str(json.loads(meta_path.read_text(encoding="utf-8")).get("version") or "")
        except (OSError, ValueError):
            pass
    short_gpt = ".".join(gpt_ver.split(".")[:2]) if gpt_ver else ""
    if short_gpt and codex_ver:
        ai_status, ai_tone = f"v{short_gpt} · {codex_ver}", "ok"
        ai_metric = f"ChatGPT {gpt_ver} (Wayland) · Codex CLI {codex_ver}"
    elif gpt_ver:
        ai_status, ai_tone = f"v{short_gpt}", "ok"
        ai_metric = f"ChatGPT Desktop {gpt_ver} native Wayland"
    else:
        ai_status, ai_tone = "Installed", "accent"
        ai_metric = "ChatGPT Desktop & Codex CLI workspace tools"

    # 8. Circadian Nightlight
    if nl_enabled:
        nl_status = f"Warm {nl_temp or 4000}K"
        nl_tone = "warn"
    else:
        nl_status = f"Daylight {nl_temp or 6000}K"
        nl_tone = "accent"

    # 9. Liquid Glass OSD & Theme
    osd_shader = (HOME / ".config" / "omarchy" / "plugins" / "akshaybapat.osd" / "shaders" / "glass_pill.frag.qsb").is_file()
    colors_toml = read_text_file(HOME / ".local" / "state" / "omarchy" / "current" / "theme" / "colors.toml")
    accent_hex = ""
    m_acc = re.search(r'^accent\s*=\s*"(#[0-9A-Fa-f]{6})"', colors_toml, re.MULTILINE)
    if m_acc:
        accent_hex = m_acc.group(1).upper()
    glass_status = "Qt 6.12 .qsb" if osd_shader else "Active"
    glass_metric = f"Qt 6.12 Fresnel shaders · Inter 264 PPI{f' · Accent {accent_hex}' if accent_hex else ''}"

    tools = [
        {
            "id": "tool-spatial-audio",
            "title": "Studio Speaker Audio",
            "status": audio_status,
            "tone": audio_tone,
            "metric": audio_metric,
            "actions": [
                {
                    "label": "Studio Deep",
                    "command": f"OMARCHY_NOTIFY=1 {HOME / '.local' / 'bin' / 'speaker-profile'} studio-deep",
                    "active": sink == "omarchy_speaker_studio",
                    "closeOnRun": False,
                    "toast": "Switching speakers to Studio Deep…",
                },
                {
                    "label": "Studio Spatial",
                    "command": f"OMARCHY_NOTIFY=1 {HOME / '.local' / 'bin' / 'speaker-profile'} studio-spatial",
                    "active": sink == "omarchy_speaker_studio_spatial",
                    "closeOnRun": False,
                    "toast": "Switching speakers to Studio Spatial…",
                },
                {
                    "label": "Reference",
                    "command": f"OMARCHY_NOTIFY=1 {HOME / '.local' / 'bin' / 'speaker-profile'} studio-ref",
                    "active": sink == "omarchy_speaker_studio_ref",
                    "closeOnRun": False,
                    "toast": "Switching speakers to Studio Reference…",
                },
                {
                    "label": "Voice",
                    "command": f"OMARCHY_NOTIFY=1 {HOME / '.local' / 'bin' / 'speaker-profile'} studio-voice",
                    "active": sink == "omarchy_speaker_studio_voice",
                    "closeOnRun": False,
                    "toast": "Switching speakers to Studio Voice…",
                },
            ],
        },
        {
            "id": "tool-battery-care",
            "title": "Battery Care",
            "status": bat_status,
            "tone": bat_tone,
            "metric": bat_metric,
            "actions": [
                {
                    "label": "Desk 55–80%",
                    "command": f"{HOME / '.local' / 'bin' / 'omarchy-battery-cap'} desk",
                    "active": not travel_active,
                    "closeOnRun": False,
                    "toast": "Applying Desk 55–80% battery cap…",
                },
                {
                    "label": "Travel 100%",
                    "command": f"{HOME / '.local' / 'bin' / 'omarchy-battery-cap'} travel",
                    "active": travel_active,
                    "closeOnRun": False,
                    "toast": "Enabling Travel 100% charge mode…",
                },
            ],
        },
        {
            "id": "tool-overview",
            "title": "Workspace Overview",
            "status": f"{desk_count} Desks · {win_count} Win" if desk_count else "Live 1:1",
            "tone": "ok",
            "metric": ov_metric,
            "actions": [
                {
                    "label": "Open Overview",
                    "command": "hyprctl dispatch global omarchy-overview:toggle",
                    "active": False,
                    "closeOnRun": True,
                    "delayMs": 50,
                },
            ],
        },
        {
            "id": "tool-everything",
            "title": "Search Everything",
            "status": ev_status,
            "tone": ev_tone,
            "metric": "Windows, browser tabs, tmux panes, AI agents & files · Super+Ctrl+Space",
            "actions": [
                {
                    "label": "Open Everything",
                    "command": "omarchy-shell shell toggle akshaybapat.everything",
                    "active": False,
                    "closeOnRun": True,
                    "delayMs": 40,
                },
            ],
        },
        {
            "id": "tool-vitals",
            "title": "Hardware Vitals",
            "status": vit_status,
            "tone": vit_tone,
            "metric": vit_metric,
            "actions": [
                {
                    "label": "Open Vitals",
                    "command": "omarchy-shell shell toggle akshaybapat.vitals",
                    "active": False,
                    "closeOnRun": True,
                    "delayMs": 40,
                },
            ],
        },
        {
            "id": "tool-screenshots",
            "title": "Screenshot Manager",
            "status": shot_status,
            "tone": shot_tone,
            "metric": "Instant copy + private save with passive preview · Print or Super+Shift+S",
            "actions": [
                {
                    "label": "Region Capture",
                    "command": f"{HOME / '.local' / 'bin' / 'omarchy-shot'} region",
                    "active": False,
                    "closeOnRun": True,
                    "delayMs": 150,
                },
                {
                    "label": "Open Gallery",
                    "command": "omarchy-shell shell toggle akshaybapat.screenshot-manager",
                    "active": False,
                    "closeOnRun": True,
                    "delayMs": 40,
                },
            ],
        },
        {
            "id": "tool-chatgpt",
            "title": "ChatGPT Desktop & Codex",
            "status": ai_status,
            "tone": ai_tone,
            "metric": ai_metric,
            "actions": [
                {
                    "label": "Launch ChatGPT",
                    "command": "/usr/bin/chatgpt --ozone-platform=wayland",
                    "active": False,
                    "closeOnRun": True,
                    "delayMs": 30,
                },
            ],
        },
        {
            "id": "tool-nightlight",
            "title": "Circadian Nightlight",
            "status": nl_status,
            "tone": nl_tone,
            "metric": "Zero-shader KMS CTM warm evening screen tint via Hyprsunset",
            "actions": [
                {
                    "label": "Toggle Nightlight",
                    "command": "/usr/share/omarchy/bin/omarchy-toggle-nightlight",
                    "active": nl_enabled,
                    "closeOnRun": False,
                    "toast": "Toggling Circadian Nightlight…",
                },
            ],
        },
        {
            "id": "tool-liquid-glass",
            "title": "Liquid Glass OSD & Theme",
            "status": glass_status,
            "tone": "accent",
            "metric": glass_metric,
            "actions": [
                {
                    "label": "Open Appearance",
                    "command": "omarchy-menu toggle appearance",
                    "active": False,
                    "closeOnRun": True,
                    "delayMs": 40,
                },
            ],
        },
        {
            "id": "tool-switcher",
            "title": "Visual Window Switcher",
            "status": "Alt+Tab · Alt+`",
            "tone": "ok",
            "metric": f"Liquid Glass MRU switcher across {win_count or 0} windows + Shelf · Type to filter, Q close, H hide",
            "actions": [
                {
                    "label": "All Windows",
                    "command": f"{HOME / '.local' / 'bin' / 'omarchy-switcher'} toggle",
                    "active": False,
                    "closeOnRun": True,
                    "delayMs": 40,
                },
                {
                    "label": "Same App",
                    "command": f"{HOME / '.local' / 'bin' / 'omarchy-switcher'} same-app",
                    "active": False,
                    "closeOnRun": True,
                    "delayMs": 40,
                },
            ],
        },
        {
            "id": "tool-doctor",
            "title": "System Health Doctor",
            "status": "8 Checks Ready",
            "tone": "ok",
            "metric": "Verifies swipe gestures, overview, studio audio, daemons, updates, thermals, battery & 4K scale",
            "actions": [
                {
                    "label": "Run Doctor",
                    "command": f"{HOME / '.local' / 'bin' / 'omarchy-doctor'} --notify",
                    "active": False,
                    "closeOnRun": False,
                    "toast": "Running System Health Doctor…",
                },
                {
                    "label": "Auto-Heal",
                    "command": f"{HOME / '.local' / 'bin' / 'omarchy-doctor'} --heal --notify",
                    "active": False,
                    "closeOnRun": False,
                    "toast": "Auto-healing gestures & services…",
                },
            ],
        },
    ]

    for tool in tools:
        act_labels = " ".join(a["label"] for a in tool["actions"])
        tool["searchBlob"] = f"{tool['title']} {tool['status']} {tool['metric']} {act_labels}".lower()
    return tools


def build_guides():
    guides = [
        {
            "id": "guide-omarchy-menus",
            "eyebrow": "01 · NAVIGATION",
            "title": "The Omarchy Button & Menus",
            "summary": "Every app, setting, and window is one shortcut or click away.",
            "bullets": [
                {
                    "text": "Top-left Omarchy logo: Left = Full Menu, Middle = Apps, Right = Terminal.",
                    "keys": [],
                },
                {
                    "text": "Search and launch any installed app from any desk.",
                    "keys": ["Super", "Space"],
                },
                {
                    "text": "Open the Full Omarchy Menu for themes, audio, and setup.",
                    "keys": ["Super", "Alt", "Space"],
                },
                {
                    "text": "Search Everything across open windows, tabs, agents, and files.",
                    "keys": ["Super", "Ctrl", "Space"],
                },
            ],
        },
        {
            "id": "guide-workspaces",
            "eyebrow": "02 · WORKSPACES",
            "title": "Mastering Workspaces & Empty Desks",
            "summary": "Organize tasks spatially across clean desks without losing windows.",
            "bullets": [
                {
                    "text": "Swipe 3 fingers up for live Workspace Overview (tracks 1:1).",
                    "keys": ["3↑"],
                },
                {
                    "text": "Swipe 2 fingers left/right inside Overview — or press Ctrl+1–9 / Ctrl+N.",
                    "keys": ["Ctrl", "1–9"],
                },
                {
                    "text": "Switch any window visually (Alt+Tab) or same-app windows (Alt+`).",
                    "keys": ["Alt", "Tab"],
                },
                {
                    "text": "Hide the active window to the top-bar shelf (or 4-finger pinch in).",
                    "keys": ["Super", "H"],
                },
            ],
        },
        {
            "id": "guide-hardware",
            "eyebrow": "03 · HARDWARE & CARE",
            "title": "Audio, Display & Battery Care",
            "summary": "Calibrated for the Dell XPS 17 9720 speakers, 4K display, and battery.",
            "bullets": [
                {
                    "text": "Switch live between 3D Spatial (FDTR-XTC) and 7.1 SOFA in Custom Tools.",
                    "keys": [],
                },
                {
                    "text": "Sharp 4K panel runs native D65 ICC color with zero-shader Nightlight.",
                    "keys": [],
                },
                {
                    "text": "Desk Mode caps charging at 55–80%; pick Travel 100% before flights.",
                    "keys": [],
                },
                {
                    "text": "Silent fan curves stay quiet on light tasks and ramp smoothly under load.",
                    "keys": [],
                },
            ],
        },
        {
            "id": "guide-safety",
            "eyebrow": "04 · SAFETY & RECOVERY",
            "title": "Safe Rollbacks & System Updates",
            "summary": "Built-in snapshots and guardrails keep updates stress-free.",
            "bullets": [
                {
                    "text": "Snapper takes automatic Btrfs snapshots before system updates.",
                    "keys": [],
                },
                {
                    "text": "Reopen this Shortcuts & Help Center anytime from anywhere.",
                    "keys": ["Super", "K"],
                },
                {
                    "text": "Rollback scripts and safety backups are stored under ~/.cache/om-next/.",
                    "keys": [],
                },
                {
                    "text": "Destructive actions (Lock, Power, Close) stay read-only here by design.",
                    "keys": [],
                },
            ],
        },
    ]

    for g in guides:
        bullet_blob = " ".join(b["text"] + " " + " ".join(b["keys"]) for b in g["bullets"])
        g["searchBlob"] = f"{g['eyebrow']} {g['title']} {g['summary']} {bullet_blob}".lower()
    return guides


def build_payload():
    env, hypr_dir = detect_hypr_session()

    # Kick off the single tiny subprocess (pactl) before local I/O so it overlaps completely!
    pactl_proc = None
    try:
        pactl_proc = subprocess.Popen(
            ["pactl", "get-default-sink"],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except OSError:
        pactl_proc = None

    by_mod_desc, by_mod_key, lua_fallback = parse_lua_binding_files()

    hypr_sock = os.path.join(hypr_dir, ".socket.sock") if hypr_dir else ""
    raw_binds = query_unix_socket(hypr_sock, "j/binds") if hypr_sock else None
    raw_ws = query_unix_socket(hypr_sock, "j/workspaces") if hypr_sock else None
    raw_clients = query_unix_socket(hypr_sock, "j/clients") if hypr_sock else None

    # Graceful fallback if socket wasn't found directly
    if raw_binds is None:
        raw_binds = run_cmd_capture(["hyprctl", "-j", "binds"], env, 1.0)
    if raw_ws is None:
        raw_ws = run_cmd_capture(["hyprctl", "-j", "workspaces"], env, 0.8)
    if raw_clients is None:
        raw_clients = run_cmd_capture(["hyprctl", "-j", "clients"], env, 0.8)

    codex_ver = read_codex_version(env)
    nl_enabled, nl_temp = read_nightlight_status(hypr_dir, env)

    default_sink = None
    if pactl_proc is not None:
        try:
            out, _ = pactl_proc.communicate(timeout=0.8)
            if pactl_proc.returncode == 0:
                default_sink = out.strip()
        except subprocess.SubprocessError:
            pactl_proc.kill()

    shortcuts = build_shortcuts(raw_binds, by_mod_desc, by_mod_key, lua_fallback)
    gestures = build_gestures()
    tools = build_tools(default_sink, raw_ws, raw_clients, codex_ver, nl_enabled, nl_temp)
    guides = build_guides()

    cat_counts = {"all": len(shortcuts)}
    for sc in shortcuts:
        cat_counts[sc["category"]] = cat_counts.get(sc["category"], 0) + 1

    categories = [
        {
            "id": c["id"],
            "label": c["label"],
            "fullLabel": c["fullLabel"],
            "count": cat_counts.get(c["id"], 0),
        }
        for c in CATEGORIES
    ]

    return {
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "counts": {
            "shortcuts": len(shortcuts),
            "gestures": len(gestures),
            "tools": len(tools),
            "guides": len(guides),
        },
        "categories": categories,
        "shortcuts": shortcuts,
        "gestures": gestures,
        "tools": tools,
        "guides": guides,
    }


def run_detached(command: str) -> int:
    cmd = (command or "").strip()
    if not cmd:
        return 2
    if not is_safe_action("", cmd):
        sys.stderr.write("Refused unsafe command\n")
        return 3
    env, _ = detect_hypr_session()
    subprocess.Popen(
        ["bash", "-lc", cmd],
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return 0


def main(argv) -> int:
    if len(argv) >= 2 and argv[1] == "--run":
        if len(argv) < 3:
            sys.stderr.write("Usage: HelpData.py --run <command>\n")
            return 2
        return run_detached(" ".join(argv[2:]))

    payload = build_payload()
    sys.stdout.write(json.dumps(payload, ensure_ascii=False))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
