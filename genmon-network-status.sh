#!/usr/bin/env bash
# Unified xfce4-genmon network status: WAN IP, LAN IP, interface up/down/monitor.
# Replaces the split genmon-show-{up,down}.sh + genmon-vpn-show-ip.sh workflow.

set -u

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/genmon"
WAN_CACHE="${CACHE_DIR}/wan-ip"
WAN_TS="${CACHE_DIR}/wan-ip.ts"

mkdir -p "$CACHE_DIR"

COMMON="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/genmon-network-common.sh"
# shellcheck source=genmon-network-common.sh
source "$COMMON"

IP() { genmon_IP "$@"; }

iface_ipv4() {
  IP -4 -o addr show dev "$1" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1
}

iface_mode() { genmon_iface_mode "$1"; }
iface_status_label() { genmon_iface_status_label "$1"; }
iface_glyph() { genmon_iface_glyph "$1"; }
iface_glyph_markup() { genmon_iface_glyph_markup "$1"; }
iface_display_name() { genmon_iface_display_name "$1"; }

get_wan_ip() {
  local now ip ts ttl="$GENMON_WAN_TTL"
  now="$(date +%s)"
  if [[ -f "$WAN_CACHE" && -f "$WAN_TS" ]]; then
    ts="$(cat "$WAN_TS" 2>/dev/null || echo 0)"
    if (( now - ts < ttl )); then
      cat "$WAN_CACHE"
      return
    fi
  fi

  ip="$(
    curl -fsS --max-time 4 https://api.ipify.org 2>/dev/null \
      || curl -fsS --max-time 4 http://whatismyip.akamai.com/ 2>/dev/null \
      || echo 'offline'
  )"
  printf '%s' "$ip" > "$WAN_CACHE"
  printf '%s' "$now" > "$WAN_TS"
  printf '%s' "$ip"
}

lan_priority_order() {
  local iface
  LAN_PRIORITY=()
  for iface in "$@"; do
    case "$iface" in
      tun*|tap*) LAN_PRIORITY+=("$iface") ;;
    esac
  done
  for iface in "$@"; do
    case "$iface" in
      wlan*|wlp*) LAN_PRIORITY+=("$iface") ;;
    esac
  done
  for iface in "$@"; do
    case "$iface" in
      eth*|enp*|eno*|ens*|usb*) LAN_PRIORITY+=("$iface") ;;
    esac
  done
  for iface in "$@"; do
    case "$iface" in
      hci*|bnep*|pan*) LAN_PRIORITY+=("$iface") ;;
    esac
  done
  for iface in "$@"; do
    LAN_PRIORITY+=("$iface")
  done
}

# Every UP iface with an IPv4 (shared by panel + tooltip).
collect_lan_ips() {
  local iface ip status
  local -a ips=()
  local -A seen_ip=()

  lan_priority_order "$@"
  for iface in "${LAN_PRIORITY[@]}"; do
    status="$(iface_status_label "$iface")"
    [[ "$status" == "DOWN" || "$status" == "MON" ]] && continue
    ip="$(iface_ipv4 "$iface")"
    [[ -n "$ip" ]] || continue
    [[ -n "${seen_ip[$ip]:-}" ]] && continue
    seen_ip["$ip"]=1
    ips+=("$ip")
  done
  ((${#ips[@]})) || return 1
  printf '%s\n' "${ips[@]}"
}

collect_lan_entries() {
  local iface ip status label
  local -a entries=()
  local -A seen_ip=()

  lan_priority_order "$@"
  for iface in "${LAN_PRIORITY[@]}"; do
    status="$(iface_status_label "$iface")"
    [[ "$status" == "DOWN" || "$status" == "MON" ]] && continue
    ip="$(iface_ipv4 "$iface")"
    [[ -n "$ip" ]] || continue
    [[ -n "${seen_ip[$ip]:-}" ]] && continue
    seen_ip["$ip"]=1
    entries+=("LAN: ${ip} (${label})")
  done
  ((${#entries[@]})) || return 1
  printf '%s\n' "${entries[@]}"
}

vpn_active() { genmon_vpn_active; }
vpn_panel_markup() { genmon_vpn_panel_markup; }

genmon_discover_ifaces
IFACES=("${GENMON_IFACES[@]}")

wan="$(get_wan_ip)"
declare -a panel_ip_parts=("$wan")
if lan_ip_list="$(collect_lan_ips "${IFACES[@]}")"; then
  while IFS= read -r ip; do
    [[ -n "$ip" ]] && panel_ip_parts+=("$ip")
  done <<< "$lan_ip_list"
fi

TOOLTIP_RULE='──────────────'
declare -a iface_parts=()
tooltip_lines=("WAN: ${wan}")

if lan_lines="$(collect_lan_entries "${IFACES[@]}")"; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && tooltip_lines+=("$line")
  done <<< "$lan_lines"
else
  tooltip_lines+=("LAN: none")
fi

tooltip_lines+=("$TOOLTIP_RULE" "Interfaces:")

for iface in "${IFACES[@]}"; do
  status="$(iface_status_label "$iface")"
  ip="$(iface_ipv4 "$iface")"
  mode="$(iface_mode "$iface")"
  label="$(iface_display_name "$iface")"
  [[ -z "$ip" ]] && ip="—"

  if [[ "$label" != "$iface" ]]; then
    tooltip_lines+=("  ${iface}  ${status}  ${ip}  ${mode} · ${label}")
  else
    tooltip_lines+=("  ${iface}  ${status}  ${ip}  ${mode}")
  fi

  genmon_hide_from_panel_summary "$iface" && continue
  iface_parts+=("$(genmon_iface_name_markup "$iface" "$status")")
done

iface_summary=""
if ((${#iface_parts[@]})); then
  iface_summary="${iface_parts[0]}"
  for ((i = 1; i < ${#iface_parts[@]}; i++)); do
    iface_summary+="  ${iface_parts[i]}"
  done
fi

panel_txt="${panel_ip_parts[0]}"
for ((i = 1; i < ${#panel_ip_parts[@]}; i++)); do
  panel_txt+=" · ${panel_ip_parts[i]}"
  done
[[ -n "$iface_summary" ]] && panel_txt="${panel_txt} · ${iface_summary}"
panel_txt="${panel_txt} · $(vpn_panel_markup)"

tooltip_lines+=("$TOOLTIP_RULE")
if vpn_active; then
  vpn_name="$(genmon_vpn_label 2>/dev/null || true)"
  if [[ -n "$vpn_name" ]]; then
    tooltip_lines+=("VPN: on (${vpn_name})")
  else
    tooltip_lines+=("VPN: on")
  fi
else
  tooltip_lines+=("VPN: off")
fi

tooltip_lines+=("$TOOLTIP_RULE" "Click: Network UP/DOWN/MON or Bluetooth broadcast strength (high/med/low for power). PWR status shown for undervolt monitoring.")

# BT broadcast strength (added for power control while keeping PAN available)
bt_state=$(genmon_bt_get_state 2>/dev/null || echo "disc=no;pair=no;scans=none")
bt_level=$(genmon_bt_level_label "$bt_state")
tooltip_lines+=("$TOOLTIP_RULE" "BT broadcast: ${bt_level} (high/med/low via menu)")
panel_txt="${panel_txt} · BT:${bt_level}"

# Power/voltage (Pi5 undervolt awareness; companion to arm_boost disable + cable/PSU fix)
pwr_state=$(genmon_power_get 2>/dev/null || echo "ext5v=?;core=?;status=ok")
pwr_level=$(genmon_power_label "$pwr_state")
case "$pwr_level" in
  LOW) pwr_markup="<span foreground='#e74c3c'>PWR:LOW</span>" ;;
  MARG) pwr_markup="<span foreground='#f1c40f'>PWR:MARG</span>" ;;
  *) pwr_markup="PWR:OK" ;;
esac
panel_txt="${panel_txt} · ${pwr_markup}"
tooltip_lines+=("$TOOLTIP_RULE" "Power: ${pwr_level} (EXT5V input rail + core; LOW/MARG triggers frequent undervolt in dmesg)")
ext5v=$(echo "$pwr_state" | sed -n 's/.*ext5v=\([^;]*\).*/\1/p')
corev=$(echo "$pwr_state" | sed -n 's/.*core=\([^;]*\).*/\1/p')
[[ -n "$ext5v" && "$ext5v" != "?" ]] && tooltip_lines+=("5V rail: ${ext5v}V (sag below ~4.8V causes undervolt/throttle)")
[[ -n "$corev" && "$corev" != "?" ]] && tooltip_lines+=("Core volt: ${corev}V")

tooltip="$(printf '%s\n' "${tooltip_lines[@]}")"

printf '<txt>%s</txt>' "$panel_txt"
printf '<tool>%s</tool>' "$tooltip"
printf '<txtclick>%s</txtclick>' "${HOME}/.local/bin/genmon-network-action.sh"