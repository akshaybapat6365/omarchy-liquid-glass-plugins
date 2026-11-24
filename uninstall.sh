#!/usr/bin/env bash
# uninstall.sh — Clean uninstaller for the Omarchy Liquid Glass Plugin Suite.
#
# Usage:
#   ./uninstall.sh --all [--dry-run]
#   ./uninstall.sh --plugin help --plugin osd [--dry-run]
#   ./uninstall.sh --list

set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
PLUGINS_DEST="${CONFIG_HOME}/omarchy/plugins"
BIN_DEST="${HOME}/.local/bin"

PLUGIN_ORDER=(
  "help"
  "switcher"
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

declare -A VALID=()
for p in "${PLUGIN_ORDER[@]}"; do
  VALID[$p]=1
done

usage() {
  cat <<'USAGE'
Omarchy Liquid Glass Plugin Suite — Uninstaller

Usage:
  ./uninstall.sh --all [options]
  ./uninstall.sh --plugin <name> [--plugin <name> ...] [options]
  ./uninstall.sh --list

Options:
  --all              Uninstall all 11 plugins from ~/.config/omarchy/plugins/
  --plugin <name>    Uninstall a specific plugin (repeatable; accepts short name
                     like 'help' or full id like 'akshaybapat.help')
  --list             Show installed status of all 11 plugins
  --dry-run          Preview removal without deleting files
  --no-rescan        Skip 'omarchy-shell shell rescanPlugins' after removal
  -h, --help         Show this help message
USAGE
}

normalize_plugin() {
  local raw="$1"
  raw="${raw#akshaybapat.}"
  if [[ -z "${VALID[$raw]+x}" ]]; then
    echo "Error: unknown plugin '${1}'. Valid names: ${PLUGIN_ORDER[*]}" >&2
    exit 2
  fi
  printf '%s\n' "$raw"
}

list_installed() {
  printf "%-20s %-34s %s\n" "SHORT NAME" "PLUGIN ID" "STATUS"
  printf "%-20s %-34s %s\n" "----------" "---------" "------"
  for short in "${PLUGIN_ORDER[@]}"; do
    id="akshaybapat.${short}"
    if [[ -d "${PLUGINS_DEST}/${id}" ]]; then
      printf "%-20s %-34s %s\n" "$short" "$id" "installed"
    else
      printf "%-20s %-34s %s\n" "$short" "$id" "not installed"
    fi
  done
}

UNINSTALL_ALL=0
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
      UNINSTALL_ALL=1
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
      list_installed
      exit 0
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
      echo "Error: unknown argument '$1'. Run './uninstall.sh --help'." >&2
      exit 2
      ;;
  esac
done

if [[ "$UNINSTALL_ALL" -eq 1 ]]; then
  SELECTED=("${PLUGIN_ORDER[@]}")
fi

if [[ ${#SELECTED[@]} -eq 0 ]]; then
  echo "Error: specify --all or at least one --plugin <name>." >&2
  exit 2
fi

echo "==> Removing selected plugins from ${PLUGINS_DEST}"
for short in "${SELECTED[@]}"; do
  id="akshaybapat.${short}"
  dst="${PLUGINS_DEST}/${id}"
  if [[ -d "$dst" ]]; then
    echo "  • removing ${id}"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "    [dry-run] rm -rf ${dst}"
    else
      rm -rf "${dst}"
    fi
  else
    echo "  • ${id} (not installed, skipping)"
  fi

  if [[ "$short" == "help" && -f "${BIN_DEST}/omarchy-help" ]]; then
    echo "    ↳ removing ${BIN_DEST}/omarchy-help"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "    [dry-run] rm -f ${BIN_DEST}/omarchy-help"
    else
      rm -f "${BIN_DEST}/omarchy-help"
    fi
  fi
  if [[ "$short" == "switcher" && -f "${BIN_DEST}/omarchy-switcher" ]]; then
    echo "    ↳ removing ${BIN_DEST}/omarchy-switcher"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "    [dry-run] rm -f ${BIN_DEST}/omarchy-switcher"
    else
      rm -f "${BIN_DEST}/omarchy-switcher"
    fi
  fi

  if [[ "$short" == "window-shelf" ]]; then
    echo "    ↳ Note: if any windows are currently minimized on the shelf, recover them with:"
    echo "      hyprctl dispatch togglespecialworkspace omarchy-minimized"
  fi
done

if [[ "$NO_RESCAN" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
fi

echo "==> Done."
