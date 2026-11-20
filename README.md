# lucky.egpu: eGPU bar widget, SUPER+SPACE submenu, safe eject

Built 2026-11-18 for philosophia (Framework 13 AMD + TREBLEET TB3 eGPU, RX 6600 XT).

## Pieces
- `BarWidget.qml`: bar icon, shown only while an eGPU is attached or ejected-but-plugged.
  Left click: eject (or reattach). Right click: opens the eGPU submenu. Red/active means
  Hyprland still drives the eGPU, so eject is refused.
- `bin/egpu` (symlinked to `~/.local/bin/egpu`): `status [--json|--notify]`, `run <cmd>`,
  `run-picker`, `holders`, `eject [--dry-run] [--yes|--close-apps]`, `reattach`.
- `extras/omarchy-menu.jsonc`: the "eGPU" submenu (Eject / Reattach / Status / Run app on eGPU),
  merged between `lucky.egpu-menu-start/end` markers into
  `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
- `extras/egpu-pci-ctl` -> `/usr/local/libexec/egpu-pci-ctl` (root helper: status/remove/rescan,
  no device arguments) + `extras/sudoers-egpu-eject` -> `/etc/sudoers.d/egpu-eject`.
- `extras/72-egpu-offload-only.rules`: sets `ID_SEAT=seat-egpu` and drops `master-of-seat` on the
  eGPU's DRM card, so Aquamarine/logind never give it to Hyprland. Staged in
  `/usr/local/share/egpu/` and copied into `/etc/udev/rules.d/` at the next boot by
  `egpu-offload-only-activate.service` (applying it live would yank the GPU from the running session).

## How eject works
Refuses if Hyprland holds the eGPU's card node. Otherwise lists processes holding the card/render
node, asks (Eject anyway / Close these apps / Cancel), removes the eGPU's external PCIe subtree
(the enclosure's upstream port, e.g. 0000:01:00.0), and notifies "Safe to unplug". Replugging later is
automatic (boltd re-authorizes, PCI hotplug re-enumerates). `egpu reattach` rescans PCI if you change
your mind without unplugging.

## Install / remove
`extras/install.sh` (add), `extras/install.sh --status`, `extras/install.sh --remove` (then reboot to give
the eGPU back to Hyprland).
