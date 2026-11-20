#!/bin/bash
# lucky.egpu installer. A plugin cannot run anything when it is loaded, so the
# pieces outside the plugin directory are added (and removed) here:
#   - eGPU submenu in ~/.config/omarchy/extensions/omarchy-menu.jsonc (SUPER+SPACE)
#   - ~/.local/bin/egpu -> bin/egpu
#   - root helper /usr/local/libexec/egpu-pci-ctl + /etc/sudoers.d/egpu-eject
#   - offload-only udev rule, staged in /usr/local/share/egpu and activated at
#     next boot by egpu-offload-only-activate.service (never live: changing the
#     seat of a GPU Hyprland holds would yank it from the running session)
#
#   install.sh            install everything (uses sudo)
#   install.sh --menu     only (re)write the menu block
#   install.sh --remove   take everything out again
#   install.sh --status   show what is installed
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
plugin=$(dirname "$here")
menu=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc

menu_edit() { # $1 = add|remove
  mkdir -p "$(dirname "$menu")"
  [[ -f $menu ]] || printf '{\n}\n' >"$menu"
  [[ -L $menu ]] && { echo "refusing to edit symlinked $menu" >&2; exit 1; }
  cp -p "$menu" "$menu.bak-egpu-$(date +%Y%m%d%H%M%S)"
  python3 - "$menu" "$1" "$here/omarchy-menu.jsonc" <<'PY'
import re, sys
path, mode, block_path = sys.argv[1:4]
text = open(path).read()
start, end = "// lucky.egpu-menu-start", "// lucky.egpu-menu-end"
# drop any previous block
text = re.sub(r"\n?[ \t]*" + re.escape(start) + r".*?" + re.escape(end) + r"[^\n]*", "", text, flags=re.S)
lines = text.rstrip("\n").split("\n")
close = max(i for i, l in enumerate(lines) if l.strip().startswith("}"))
# last real entry line before the closing brace (skip blanks/comments)
prev = close - 1
while prev >= 0 and (not lines[prev].strip() or lines[prev].strip().startswith("//")):
    prev -= 1
if mode == "add":
    block = open(block_path).read().rstrip("\n").split("\n")
    if prev >= 0 and not re.search(r"[{,]\s*$", lines[prev]):
        lines[prev] += ","
    lines = lines[:close] + block + lines[close:]
else:
    if prev >= 0:
        lines[prev] = re.sub(r",\s*$", "", lines[prev])
open(path, "w").write("\n".join(lines) + "\n")
PY
  omarchy-menu refresh >/dev/null 2>&1 || true
}

system_install() {
  sudo install -Dm755 "$here/egpu-pci-ctl" /usr/local/libexec/egpu-pci-ctl
  sudo install -m440 "$here/sudoers-egpu-eject" /etc/sudoers.d/egpu-eject.new
  sudo visudo -c -f /etc/sudoers.d/egpu-eject.new >/dev/null
  sudo mv /etc/sudoers.d/egpu-eject.new /etc/sudoers.d/egpu-eject
  sudo install -Dm644 "$here/72-egpu-offload-only.rules" /usr/local/share/egpu/72-egpu-offload-only.rules
  sudo install -Dm644 "$here/egpu-offload-only-activate.service" /etc/systemd/system/egpu-offload-only-activate.service
  sudo systemctl daemon-reload
  sudo systemctl enable egpu-offload-only-activate.service >/dev/null
}

system_remove() {
  sudo systemctl disable egpu-offload-only-activate.service >/dev/null 2>&1 || true
  sudo rm -f /etc/systemd/system/egpu-offload-only-activate.service /usr/local/share/egpu/72-egpu-offload-only.rules \
    /etc/udev/rules.d/72-egpu-offload-only.rules /etc/sudoers.d/egpu-eject /usr/local/libexec/egpu-pci-ctl
  sudo rmdir /usr/local/share/egpu 2>/dev/null || true
  sudo systemctl daemon-reload
  sudo udevadm control --reload || true
}

case ${1:-} in
  --status)
    grep -q 'lucky.egpu-menu-start' "$menu" 2>/dev/null && echo "menu: installed" || echo "menu: missing"
    [[ -L $HOME/.local/bin/egpu ]] && echo "cli: ~/.local/bin/egpu" || echo "cli: missing"
    [[ -x /usr/local/libexec/egpu-pci-ctl ]] && echo "helper: installed" || echo "helper: missing"
    sudo -n /usr/local/libexec/egpu-pci-ctl status >/dev/null 2>&1 && echo "sudoers: installed" || echo "sudoers: missing"
    if [[ -f /etc/udev/rules.d/72-egpu-offload-only.rules ]]; then echo "offload-only rule: active"
    elif [[ -f /usr/local/share/egpu/72-egpu-offload-only.rules ]]; then echo "offload-only rule: staged (activates at next boot)"
    else echo "offload-only rule: missing"; fi
    ;;
  --menu) menu_edit add ;;
  --remove)
    menu_edit remove
    rm -f "$HOME/.local/bin/egpu"
    system_remove
    echo "removed. A reboot returns the eGPU to Hyprland."
    ;;
  "")
    menu_edit add
    mkdir -p "$HOME/.local/bin"; ln -sfn "$plugin/bin/egpu" "$HOME/.local/bin/egpu"
    system_install
    echo "installed. Reboot once to make the eGPU offload-only."
    ;;
  *) echo "usage: install.sh [--menu|--remove|--status]" >&2; exit 2 ;;
esac
