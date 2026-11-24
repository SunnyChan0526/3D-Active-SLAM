#!/usr/bin/env bash
# Host-side (NOT in the container) settings the D435i needs on a Jetson
# (JetPack 6.2 / Ubuntu 22.04). Found on the AGX Orin, 2026-11-24.
# See setup/JETSON_HOST_SETUP.md.
#
#   bash setup/jetson_host_setup.sh            check only, changes nothing
#   bash setup/jetson_host_setup.sh --apply    apply 1 + 2 below (asks for sudo)
#
# 1. PipeWire media-session: drop the v4l2 monitor (it grabs the camera, so
#    IMU / color streams fail to start).          -> user config, no sudo
# 2. USB autosuspend off, persistent across reboot:
#    - udev rule: RealSense (8086) devices keep power/control=on
#    - systemd oneshot: usbcore autosuspend=-1 (what was set by hand on AGX)
# 3. uvcvideo: only reported. Unloading it had no proven effect.
set -euo pipefail

apply=false
case "${1:-}" in
  --apply) apply=true ;;
  ""|--check) ;;
  *) echo "usage: $0 [--check|--apply]"; exit 2 ;;
esac

ms_user_conf="$HOME/.config/pipewire/media-session.d/media-session.conf"
ms_sys_conf=/usr/share/pipewire/media-session.d/media-session.conf
udev_rule=/etc/udev/rules.d/99-activeslam-usb-power.rules
unit=/etc/systemd/system/activeslam-usb-autosuspend.service

ok()   { echo "  [ok]   $*"; }
warn() { echo "  [todo] $*"; }
info() { echo "  [info] $*"; }

# v4l2 listed (uncommented) as a session module?
v4l2_enabled() { grep -Eq '^[[:space:]]*v4l2([[:space:]]|#|$)' "$1"; }

session_manager() {
  if systemctl --user is-active --quiet pipewire-media-session 2>/dev/null; then echo media-session
  elif systemctl --user is-active --quiet wireplumber 2>/dev/null; then echo wireplumber
  elif pgrep -f bin/pipewire-media-session >/dev/null; then echo media-session
  elif pgrep -x wireplumber >/dev/null; then echo wireplumber
  else echo none; fi
}

check() {
  echo "== system"
  info "$( { tr -d '\0' </proc/device-tree/model; } 2>/dev/null || uname -m)"
  [[ -f /etc/nv_tegra_release ]] && info "$(head -1 /etc/nv_tegra_release)"
  command -v nvpmodel >/dev/null && info "power mode: $(nvpmodel -q 2>/dev/null | head -1)"

  echo "== 1. PipeWire v4l2 monitor"
  local sm; sm="$(session_manager)"
  info "session manager: $sm"
  case "$sm" in
    media-session)
      if [[ -f "$ms_user_conf" ]]; then
        if v4l2_enabled "$ms_user_conf"; then warn "v4l2 still enabled in $ms_user_conf"
        else ok "v4l2 disabled in $ms_user_conf"; fi
      else warn "no user config $ms_user_conf (system default has v4l2 on)"; fi ;;
    wireplumber) warn "wireplumber is running; this script only handles pipewire-media-session" ;;
    none) ok "no PipeWire session manager running" ;;
  esac

  echo "== 2. USB autosuspend"
  local g; g="$(cat /sys/module/usbcore/parameters/autosuspend 2>/dev/null || echo '?')"
  [[ "$g" == -1 ]] && ok "usbcore autosuspend = -1" || warn "usbcore autosuspend = $g (want -1)"
  [[ -f "$udev_rule" ]] && ok "udev rule $udev_rule" || warn "missing $udev_rule"
  systemctl is-enabled --quiet activeslam-usb-autosuspend 2>/dev/null \
    && ok "activeslam-usb-autosuspend.service enabled" || warn "activeslam-usb-autosuspend.service not enabled"

  echo "== RealSense devices"
  local found=false d
  for d in /sys/bus/usb/devices/*; do
    [[ -f "$d/idVendor" && "$(cat "$d/idVendor")" == 8086 ]] || continue
    [[ "$(cat "$d/bDeviceClass" 2>/dev/null)" == 09 ]] && continue   # skip hubs
    found=true
    local speed ctl prod
    speed="$(cat "$d/speed" 2>/dev/null)"; ctl="$(cat "$d/power/control" 2>/dev/null)"
    prod="$(cat "$d/product" 2>/dev/null || cat "$d/idProduct")"
    info "$(basename "$d"): $prod, ${speed} Mb/s, power/control=$ctl"
    [[ "${speed:-0}" -ge 5000 ]] || warn "  not USB 3.x — use a USB3 port / cable"
    [[ "$ctl" == on ]] || warn "  power/control is '$ctl' (want on)"
  done
  $found || info "no 8086 device connected"

  echo "== 3. uvcvideo (info only)"
  if grep -q "^uvcvideo " /proc/modules 2>/dev/null; then info "uvcvideo loaded"
  elif modinfo uvcvideo >/dev/null 2>&1; then info "uvcvideo available, not loaded"
  else info "uvcvideo not present"; fi
}

apply_pipewire() {
  local sm; sm="$(session_manager)"
  if [[ "$sm" == wireplumber ]]; then
    echo "wireplumber detected: not handled, disable its v4l2 monitor by hand (see JETSON_HOST_SETUP.md)."
    return
  fi
  if [[ ! -f "$ms_user_conf" ]]; then
    [[ -f "$ms_sys_conf" ]] || { echo "no $ms_sys_conf; is pipewire-media-session installed? skipping"; return; }
    mkdir -p "$(dirname "$ms_user_conf")"
    cp "$ms_sys_conf" "$ms_user_conf"
    echo "copied $ms_sys_conf -> $ms_user_conf"
  fi
  if v4l2_enabled "$ms_user_conf"; then
    cp "$ms_user_conf" "$ms_user_conf.bak.$(date +%Y%m%d%H%M%S)"
    sed -i -E 's/^([[:space:]]*)(v4l2([[:space:]#].*)?)$/\1#\2  # ActiveSLAM: grabs the RealSense/' "$ms_user_conf"
    echo "disabled v4l2 in $ms_user_conf"
  fi
  if [[ "$sm" == media-session ]]; then
    systemctl --user restart pipewire pipewire-media-session 2>/dev/null \
      && echo "restarted pipewire + media-session" \
      || echo "could not restart pipewire; log out/in or reboot"
  fi
}

apply_usb() {
  sudo tee "$udev_rule" >/dev/null <<'EOF'
# ActiveSLAM: keep Intel RealSense devices out of USB autosuspend.
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="8086", TEST=="power/control", ATTR{power/control}="on"
EOF
  sudo tee "$unit" >/dev/null <<'EOF'
[Unit]
Description=ActiveSLAM: disable USB autosuspend (usbcore autosuspend=-1)
DefaultDependencies=no
Before=sysinit.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo -1 > /sys/module/usbcore/parameters/autosuspend'
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now activeslam-usb-autosuspend.service
  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=8086 --action=add
  echo "USB autosuspend: udev rule + systemd unit installed"
}

if $apply; then
  echo "### applying"
  apply_pipewire
  apply_usb
  echo
fi
check
$apply || echo; $apply || echo "(check only. Run with --apply to change settings.)"
