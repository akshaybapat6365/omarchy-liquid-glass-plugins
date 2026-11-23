#!/usr/bin/env bash
# install.sh — Modular installer for the Omarchy Liquid Glass Plugin Suite.
#
# Usage:
#   ./install.sh --list
#   ./install.sh --all [--enable] [--dry-run]
#   ./install.sh --plugin help --plugin osd [--enable] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_SRC="${SCRIPT_DIR}/plugins"
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
PLUGINS_DEST="${CONFIG_HOME}/omarchy/plugins"
BIN_DEST="${HOME}/.local/bin"

PLUGIN_ORDER=(
  "help"
  "osd"
  "everything"
  "vitals"
  "screenshot-manager"
  "ai-usage"
  "notification-center"
  "system-updates"
  "window-shelf"
  "workspace-windows"
  "app-launcher"
)

declare -A PLUGIN_KIND=(
  [help]="overlay"
  [osd]="panel"
  [everything]="bar-widget+service"
  [vitals]="bar-widget"
  [screenshot-manager]="bar-widget"
  [ai-usage]="bar-widget"
  [notification-center]="bar-widget+service"
  [system-updates]="bar-widget"
  [window-shelf]="bar-widget"
  [workspace-windows]="bar-widget"
  [app-launcher]="bar-widget"
)

declare -A PLUGIN_DESC=(
  [help]="Liquid Glass Shortcuts, Trackpad Gestures, Custom Tools & Quick Help Center (+ omarchy-help CLI)"
  [osd]="Optical Liquid Glass capsule OSD with Qt 6.12 Fresnel top-edge sheen shader"
  [everything]="Search & jump to windows, browser tabs, tmux panes, AI agents & Neovim buffers"
  [vitals]="Dual-GPU & hardware telemetry panel (zero dGPU wakes; Rust vitalsd / Python fallback)"
  [screenshot-manager]="Instant screenshot gallery, lightbox & clipboard manager (Rust screenshotd / Python fallback)"
  [ai-usage]="Multi-provider AI quota circular tachometer dials & spend breakdown panel"
  [notification-center]="Keyboard-first, app-grouped Notification Center with actions & DND"
  [system-updates]="Unified Arch, AUR, Flatpak, Omarchy & add-on update indicator"
  [window-shelf]="macOS Cmd+H minimized window shelf chips with hover preview & Peek"
  [workspace-windows]="Per-workspace active window icon strip (focused bright + underline)"
  [app-launcher]="Omarchy Logo bar trigger (Left = Full Menu, Middle = Apps, Right = Terminal)"
)

declare -A PLUGIN_SECTION=(
  [everything]="left"
  [vitals]="right"
  [screenshot-manager]="right"
  [ai-usage]="right"
  [notification-center]="right"
  [system-updates]="right"
  [window-shelf]="left"
  [workspace-windows]="left"
  [app-launcher]="left"
)

usage() {
  cat <<'USAGE'
Omarchy Liquid Glass Plugin Suite — Installer

Usage:
  ./install.sh --all [options]
  ./install.sh --plugin <name> [--plugin <name> ...] [options]
  ./install.sh --list

Options:
  --all              Install all 11 plugins
  --plugin <name>    Install a specific plugin (repeatable; accepts short name like
                     'help' or full id like 'akshaybapat.help')
  --list             List all available plugins and exit
  --enable           Print safe activation steps (and enable bar widgets via
                     omarchy-shell / omarchy plugin when available without
                     clobbering existing bar layouts)
  --dry-run          Preview installation steps without modifying any files
  --no-rescan        Skip 'omarchy-shell shell rescanPlugins' after installation
  -h, --help         Show this help message

Examples:
  ./install.sh --list
  ./install.sh --all
  ./install.sh --plugin help --plugin osd
  ./install.sh --plugin vitals --enable
USAGE
}

list_plugins() {
  printf "%-20s %-34s %-19s %s\n" "SHORT NAME" "PLUGIN ID" "KIND" "DESCRIPTION"
  printf "%-20s %-34s %-19s %s\n" "----------" "---------" "----" "-----------"
  for short in "${PLUGIN_ORDER[@]}"; do
    printf "%-20s %-34s %-19s %s\n" \
      "$short" "akshaybapat.${short}" "${PLUGIN_KIND[$short]}" "${PLUGIN_DESC[$short]}"
  done
}

normalize_plugin() {
  local raw="$1"
  raw="${raw#akshaybapat.}"
  if [[ -z "${PLUGIN_DESC[$raw]+x}" ]]; then
    echo "Error: unknown plugin '${1}'. Run './install.sh --list' to see valid names." >&2
    exit 2
  fi
  printf '%s\n' "$raw"
}

INSTALL_ALL=0
DO_ENABLE=0
DRY_RUN=0
NO_RESCAN=0
SELECTED=()

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      INSTALL_ALL=1
      shift
      ;;
    --plugin)
      if [[ $# -lt 2 ]]; then
        echo "Error: --plugin requires a plugin name." >&2
        exit 2
      fi
      SELECTED+=("$(normalize_plugin "$2")")
      shift 2
      ;;
    --plugin=*)
      SELECTED+=("$(normalize_plugin "${1#*=}")")
      shift
      ;;
    --list)
      list_plugins
      exit 0
      ;;
    --enable)
      DO_ENABLE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-rescan)
      NO_RESCAN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'. Run './install.sh --help'." >&2
      exit 2
      ;;
  esac
done

if [[ "$INSTALL_ALL" -eq 1 ]]; then
  SELECTED=("${PLUGIN_ORDER[@]}")
fi

if [[ ${#SELECTED[@]} -eq 0 ]]; then
  echo "Error: specify --all or at least one --plugin <name>." >&2
  exit 2
fi

# Deduplicate while preserving order, and auto-include workspace-windows if window-shelf is selected.
declare -A SEEN=()
FINAL_PLUGINS=()
for short in "${SELECTED[@]}"; do
  if [[ "$short" == "window-shelf" && -z "${SEEN[workspace-windows]+x}" ]]; then
    # Check if workspace-windows is already in SELECTED
    has_ww=0
    for s2 in "${SELECTED[@]}"; do
      [[ "$s2" == "workspace-windows" ]] && has_ww=1
    done
    if [[ "$has_ww" -eq 0 ]]; then
      echo "[info] akshaybapat.window-shelf imports WindowIcons.js from akshaybapat.workspace-windows; including workspace-windows."
      SEEN[workspace-windows]=1
      FINAL_PLUGINS+=("workspace-windows")
    fi
  fi
  if [[ -z "${SEEN[$short]+x}" ]]; then
    SEEN[$short]=1
    FINAL_PLUGINS+=("$short")
  fi
done

run_or_echo() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

echo "==> Installing ${#FINAL_PLUGINS[@]} plugin(s) into ${PLUGINS_DEST}"
run_or_echo mkdir -p "${PLUGINS_DEST}"

for short in "${FINAL_PLUGINS[@]}"; do
  id="akshaybapat.${short}"
  src="${PLUGINS_SRC}/${id}"
  dst="${PLUGINS_DEST}/${id}"

  if [[ ! -d "$src" ]]; then
    echo "Error: plugin source directory missing: ${src}" >&2
    exit 1
  fi

  echo "  • ${id} (${PLUGIN_KIND[$short]})"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "    [dry-run] sync ${src} -> ${dst}"
  else
    rm -rf "${dst}"
    mkdir -p "${dst}"
    cp -a "${src}/." "${dst}/"
  fi

  # Install omarchy-help CLI when akshaybapat.help is installed
  if [[ "$short" == "help" && -f "${src}/bin/omarchy-help" ]]; then
    run_or_echo mkdir -p "${BIN_DEST}"
    run_or_echo install -m 755 "${src}/bin/omarchy-help" "${BIN_DEST}/omarchy-help"
    echo "    ↳ installed CLI: ${BIN_DEST}/omarchy-help"
  fi
done

if [[ "$NO_RESCAN" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
  if command -v omarchy-shell >/dev/null 2>&1; then
    echo "==> Refreshing Omarchy shell plugin catalog..."
    if omarchy-shell shell rescanPlugins >/dev/null 2>&1; then
      echo "    ↳ omarchy-shell shell rescanPlugins succeeded."
    else
      echo "    ↳ Note: omarchy-shell is not currently active; new plugins will load on next shell start."
    fi
  else
    echo "==> Note: 'omarchy-shell' not found in PATH; skipping live rescan."
  fi
fi

if [[ "$DO_ENABLE" -eq 1 ]]; then
  echo ""
  echo "==> Safe Activation & Layout Guide"
  for short in "${FINAL_PLUGINS[@]}"; do
    id="akshaybapat.${short}"
    kind="${PLUGIN_KIND[$short]}"
    if [[ "$kind" == "bar-widget" || "$kind" == "bar-widget+service" ]]; then
      section="${PLUGIN_SECTION[$short]:-right}"
      echo "  • ${id} (${section} bar section):"
      echo "      omarchy plugin enable ${id} ${section}"
    elif [[ "$short" == "help" ]]; then
      echo "  • ${id} (overlay — bind a key or run directly):"
      echo "      omarchy-help toggle    # or bind SUPER+K in ~/.config/hypr/bindings.lua"
    elif [[ "$short" == "osd" ]]; then
      echo "  • ${id} (panel overlay — replaces built-in OSD cleanly):"
      echo "      Add \"${id}\" to enabled plugins in ~/.config/omarchy/shell.json (and disable \"omarchy.osd\" if desired)"
    fi
  done
  echo ""
  echo "Tip: Your existing ~/.config/omarchy/shell.json bar layout was NOT modified automatically."
fi

echo "==> Done."
