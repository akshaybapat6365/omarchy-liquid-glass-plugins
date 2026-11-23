# Maintainer: Akshay Bapat <https://github.com/akshaybapat6365>
pkgname=omarchy-liquid-glass-plugins
pkgver=1.0.0
pkgrel=1
pkgdesc='Modular Liquid Glass Quickshell plugin suite for Omarchy Linux (11 plugins)'
arch=('any')
url='https://github.com/akshaybapat6365/omarchy-liquid-glass-plugins'
license=('MIT')
depends=('quickshell' 'hyprland' 'qt6-declarative' 'python')
optdepends=(
  'wl-clipboard: clipboard image copy in akshaybapat.screenshot-manager'
  'glib2: recoverable desktop trash in akshaybapat.screenshot-manager'
  'pacman-contrib: Arch update detection in akshaybapat.system-updates'
  'flatpak: Flatpak update detection in akshaybapat.system-updates'
  'ai-usagebar: multi-provider AI quota engine for akshaybapat.ai-usage'
  'omarchy-rust-daemons: optional Rust daemons (everythingd, vitalsd, screenshotd) for sub-10ms latency'
)
source=()

package() {
  local srcroot="${startdir}"
  local share="$pkgdir/usr/share/$pkgname"

  install -dm755 "$share/plugins"
  cp -a "$srcroot/plugins/." "$share/plugins/"
  install -Dm755 "$srcroot/install.sh" "$share/install.sh"
  install -Dm755 "$srcroot/uninstall.sh" "$share/uninstall.sh"
  install -Dm644 "$srcroot/README.md" "$share/README.md"
  install -Dm644 "$srcroot/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"

  # Install omarchy-help CLI globally
  install -Dm755 "$srcroot/plugins/akshaybapat.help/bin/omarchy-help" "$pkgdir/usr/bin/omarchy-help"

  # Convenience user installer wrapper
  install -dm755 "$pkgdir/usr/bin"
  cat > "$pkgdir/usr/bin/omarchy-liquid-glass-plugins" <<'EOF'
#!/usr/bin/env bash
exec /usr/share/omarchy-liquid-glass-plugins/install.sh "$@"
EOF
  chmod 755 "$pkgdir/usr/bin/omarchy-liquid-glass-plugins"
}
