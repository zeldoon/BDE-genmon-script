  # BDE-genmon-script

**BDE-genmon-script** (Big Dick Energy version) is a set of unified scripts for the xfce4-genmon plugin. It provides a single, powerful panel applet that shows:

- WAN IP (cached)
- Multiple LAN IPs with interface names and states
- Interface status (UP / DOWN / MON for monitor mode)
- VPN status
- Bluetooth broadcast strength control (HIGH / MED / LOW) with live power vs availability trade-offs, especially useful for keeping a Bluetooth Personal Area Network (PAN) available for remote control without max power draw
- Pi5-specific power and undervoltage monitoring (EXT5V input rail from PMIC, core voltage, recent dmesg undervolt events, practical hardware fix recommendations)

The action menu (click the panel) lets you bring interfaces up/down, put wireless in monitor mode, change BT broadcast strength, and view detailed power status.

This is the "BDE" (Big Dick Energy) version of the original unified genmon-network scripts. It is intended for users who want practical, robust tools for daily use on Raspberry Pi (especially Pi 5) and other Linux boxes, particularly those who use Bluetooth tethering/PAN from a phone for low-bandwidth remote control (SSH, RustDesk, etc.) instead of or in addition to WiFi.

## Features

- **Unified status in one applet**: No more separate genmon for up/down, VPN, etc.
- **Smart interface discovery**: Auto-detects real interfaces (eth*, wlan*, bnep*, pan*, etc.), skips virtual ones by default. Configurable skip/include via `~/.config/genmon/network-devices.conf`.
- **WAN IP with smart caching**: Avoids hammering public APIs; configurable TTL.
- **Bluetooth broadcast control**: Three levels with clear explanations:
  - HIGH: discoverable + full scans (max power, for initial pairing)
  - MEDIUM: pairable + pscan (available for known devices/PAN, lower power) — recommended default for always-on remote
  - LOW: stealth/min power (PAN may still work if phone initiates)
- **Pi5 power monitoring**: Shows real input rail voltage (EXT5V_V), core voltage, undervolt event count since boot, and actionable hardware advice (short high-quality e-marked cable, good PD PSU, direct plug, arm_boost=0 in config.txt).
- **Action menu**: Full whiptail/dialog menu for interface control, BT strength, power info. Can be launched from terminal too (`genmon-network-action.sh --menu`).
- **Robust notifications and refresh**: Works with xfce4-panel genmon plugin.
- **Pango markup** for colored status in panel.

## Installation

### Prerequisites (Kali / Debian / Ubuntu / RPi OS)

```bash
sudo apt update
sudo apt install xfce4-genmon-plugin whiptail dialog network-manager bluez bluez-tools wireless-tools curl v4l-utils # v4l for some tools; adjust as needed
```

On Raspberry Pi, make sure `vcgencmd` works (usually in `raspberrypi-utils` or equivalent).

### Files

Place these three scripts somewhere in PATH (recommended `~/.local/bin/` or `/usr/local/bin/`):

- `genmon-network-common.sh`
- `genmon-network-action.sh`
- `genmon-network-status.sh`

Make them executable:

```bash
chmod +x genmon-network-*.sh
```

### Panel Configuration (xfce4-genmon-plugin)

1. Add a new "Generic Monitor" plugin to your panel.
2. In the plugin preferences:
   - Command: full path to `genmon-network-status.sh` (e.g. `/home/youruser/.local/bin/genmon-network-status.sh`)
   - Label: (optional, e.g. "Net")
   - Period: 5 or 10 seconds (the scripts cache appropriately)
   - Click command: full path to `genmon-network-action.sh` (for the menu)
3. Save and restart the panel (`xfce4-panel -r` or log out/in).

### Optional Config File

Create `~/.config/genmon/network-devices.conf` (or `$XDG_CONFIG_HOME/genmon/network-devices.conf`):

```
# WAN IP cache TTL in seconds
WAN_TTL=60

# Interfaces to skip (prefix with -)
- docker0
- br-*

# Force-include extra interfaces (prefix with +)
+ usb0

# Legacy: plain names are treated as force-include
pan0
```

Lines starting with # are comments. Changes are picked up on next refresh.

## Features in Detail

See the scripts themselves for implementation. Key behaviors:

- Interfaces are discovered every run using `ip link` + pattern matching + config.
- Status labels: UP (green), DOWN (red), MON (orange).
- VPN detection via tun/tap or nmcli.
- BT control uses `bluetoothctl` + `hciconfig` for scan modes.
- Power monitoring parses `vcgencmd pmic_read_adc` for EXT5V_V (best indicator of input voltage sag) and falls back to core voltage + dmesg count for undervolts.

## Practical Modifications

Users are encouraged to fork and tweak. Examples:

- Change colors/glyphs in `genmon-network-common.sh` (the markup functions).
- Add/remove interface patterns in `genmon_matches_iface_pattern` and `genmon_should_skip_iface`.
- Adjust BT level logic or power thresholds (e.g. change 4.80V / 4.90V cutoffs).
- Make the power menu show more or integrate with `vcgencmd` throttling decode.
- Add support for additional VPN types or custom status icons.
- For non-Pi: comment out or conditional the PMIC/vcgencmd power bits.
- Change default BT level or make the panel show more/less detail.
- Integrate with other monitoring (e.g. call from your own status script).

The scripts are deliberately modular (common.sh for logic, status for the txt, action for the menu).

## Intended Use: Bluetooth Network for Remote Control

This suite is particularly useful if you want to use Bluetooth as a practical, low-power, low-bandwidth network for remote control of a headless or semi-headless device (Raspberry Pi, laptop, etc.) from your phone, without relying on WiFi or cellular data for the control link itself.

Typical setup:
- Pi provides or joins a Bluetooth Personal Area Network (PAN).
- Phone connects to the Pi's BT interface (bnep0 or similar).
- You get a direct IP link between phone and Pi (very low bandwidth, good for SSH, RustDesk, VNC, etc.).
- The genmon script lets you control BT broadcast strength from the panel so you can keep the link "available" (MED/LOW) without max power (HIGH), saving battery while still allowing the phone to initiate or maintain the PAN.
- Power monitoring helps you keep the Pi healthy (undervolt awareness is critical on Pi 5 with marginal PSUs/cables).

### How to Set Up a Bluetooth Network You Can SSH Into From Your Phone

This is the practical part. The goal is a direct IP-over-BT link so your phone can `ssh user@pi-ip` or run RustDesk client to the Pi without WiFi.

#### On the Raspberry Pi (server / NAP side)

1. Install prerequisites:
   ```bash
   sudo apt update
   sudo apt install bluez bluez-tools iproute2 dnsmasq  # dnsmasq optional for DHCP
   ```

2. Pair your phone (one time):
   ```bash
   bluetoothctl
   power on
   discoverable on
   pairable on
   scan on   # wait for your phone to appear, note its MAC
   pair <phone-mac>
   trust <phone-mac>
   exit
   ```

3. Enable NAP (Network Access Point) on the Pi so the phone can get an IP or direct link:
   A simple reliable way (modern bluez):
   ```bash
   # Make sure the controller is up
   sudo hciconfig hci0 up piscan

   # Use bt-pan helper if available, or manual
   # Install if needed: sudo apt install bt-pan or use the following

   # Common practical method using systemd-networkd or manual ip
   sudo ip link add name bnep0 type bluetooth   # or let the connection create it
   # Better: use the phone to initiate the PAN connection (most Android phones have "Bluetooth tethering" or PAN client mode)

   # After phone connects as PAN client, a bnepX interface appears on Pi
   # Assign IP on Pi side (example static for SSH)
   sudo ip addr add 192.168.7.1/24 dev bnep0
   sudo ip link set bnep0 up

   # Optional: enable IP forwarding and NAT if you want the phone to share the Pi's internet
   sudo sysctl -w net.ipv4.ip_forward=1
   sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE   # adjust outgoing iface
   ```

   Many users simply let the phone connect and use the direct link layer for SSH/RustDesk without full routing.

4. Start SSH if not running:
   ```bash
   sudo systemctl enable --now ssh
   ```

5. On the phone (client side):
   - Pair with the Pi if not already.
   - Use an app or built-in Bluetooth PAN / tethering to connect to the Pi as client (search for "Bluetooth PAN" or "Bluetooth network" in phone settings or use apps like "Bluetooth Auto Connect" or Termux scripts).
   - Once connected, the phone gets an IP (often 192.168.7.2 or similar) or the Pi's bnep IP is reachable directly.
   - From Termux or any SSH client on the phone: `ssh user@192.168.7.1` (or the Pi's bnep IP).
   - For RustDesk or VNC, use the direct IP.

#### Power Saving with the genmon script
Use the action menu (or `genmon-network-action.sh --bt`) to set MED or LOW. This keeps the PAN available for the phone to connect or stay connected without the Pi running at full discoverable power. Perfect for always-on remote control setups on battery or marginal power.

#### Tips for Reliability
- Use static IPs on the bnep interface for both sides to avoid DHCP issues.
- On Pi, a small script or systemd unit to bring up the bnep IP on interface creation.
- Test the link with `ping` and `ssh` before relying on it for remote.
- Combine with the power monitoring in the script to watch for undervolts that could drop the BT radio.
- For security: restrict SSH to the bnep interface only (`ListenAddress 192.168.7.1` in sshd_config) or use key-only auth.

This setup is exactly why the BT strength and power features were added — practical remote control over Bluetooth when you don't want or can't use WiFi/cellular for the control channel.

## License

Same as original genmon scripts (usually MIT or similar — check original sources).

## Credits & Relation to Other Projects

This is the enhanced "BDE" (Big Dick Energy) iteration of the genmon-network scripts originally shared in the zeldoon/genmon_scripts repo and heavily used/integrated in the RAZOR RPi5 operator toolkit.

Contributions, forks, and practical modifications are welcome. If you build something cool for your remote BT setups, share it!

For the full RAZOR RPi5 operator menu that integrates these scripts + CPU/BT/power/keyboard tools, see the related RAZOR project.

Happy hacking — may your panels be informative and your BT links reliable (at reasonable power levels).
