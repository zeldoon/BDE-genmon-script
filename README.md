# BDE-genmon-script

**BDE-genmon-script** ("Big Dick Energy" version) is the full-featured, production-oriented set of scripts for the xfce4-genmon plugin.

It is the enhanced iteration used in real operator setups on Raspberry Pi 5 (Kali) for unified network visibility + control, with special emphasis on Bluetooth PAN for reliable, low-power remote control from a phone.

## Features

- One applet for everything: WAN IP (with cache), LAN IPs with pretty names, interface state (UP green / DOWN red / MON orange), VPN detection, BT broadcast strength indicator, Pi5 power/undervolt status (real EXT5V rail + core voltage + dmesg count).
- Full clickable action menu (whiptail/dialog or terminal): bring interfaces up/down/monitor, change BT strength on the fly (HIGH/MED/LOW with clear explanations of power vs PAN availability), view detailed power status with hardware recommendations.
- Smart auto-discovery + user config (~/.config/genmon/network-devices.conf) for skipping virtual interfaces and forcing extra ones.
- Designed around practical Bluetooth use: the BT strength control and power monitoring exist specifically so you can keep a Bluetooth Personal Area Network "available" for remote SSH/RustDesk/etc. from your phone without the Pi blasting max power.

## Installation

### 1. Install dependencies

```bash
sudo apt update
sudo apt install xfce4-genmon-plugin whiptail dialog network-manager bluetooth bluez bluez-tools wireless-tools curl
```

On Raspberry Pi 5 / Kali, make sure `vcgencmd` is available (usually `sudo apt install raspberrypi-utils` or equivalent).

### 2. Place the scripts

Copy the three scripts to a directory in your PATH, e.g.:

```bash
mkdir -p ~/.local/bin
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc   # if not already
source ~/.bashrc
cp genmon-network-*.sh ~/.local/bin/
chmod +x ~/.local/bin/genmon-network-*.sh
```

### 3. Configure the genmon plugin

- Right-click panel → Panel → Add New Items → Generic Monitor
- Edit the plugin:
  - Command: `/home/YOURUSER/.local/bin/genmon-network-status.sh`
  - Period (seconds): 5 or 10
  - Label: (blank or "Net")
  - Click command: `/home/YOURUSER/.local/bin/genmon-network-action.sh`
- Apply and restart panel (`xfce4-panel -r`).

### 4. Optional config

Create `~/.config/genmon/network-devices.conf`:

```
WAN_TTL=120

- docker0
- br-*
- veth*

+ usb0
+ pan0
```

## Features in Detail

See the scripts. The common.sh has all the shared logic (discovery, BT helpers with the three levels, power monitoring with PMIC + dmesg, markup functions).

The status.sh builds the <txt> <tool> <txtclick> for the panel.

The action.sh provides the full menu (categories for net / bt / pwr) and the logic to change interface state, BT level, and show power info.

## Practical Modifications Users Can Apply

- Change the default BT level in the code or make the panel always show current level.
- Add more interface patterns or skip rules for your specific setup (docker, lxc, tailscale, etc.).
- Tweak the power thresholds or add more dmesg parsing.
- Make the power menu call additional vcgencmd commands or your own undervolt fixer script.
- Strip features you don't want (e.g. remove the power menu if not on Pi5, remove VPN detection if not using NM).
- Change colors in the markup functions or add temperature to the status.
- Integrate the BT strength control into your own status bar or conky.
- Add support for more VPN backends.

The modular design (common + status + action) makes it easy to fork and customize.

## Intended Use: Bluetooth Network for Remote Control (the main reason for the BT + power features)

This is explicitly built for people who want to use Bluetooth as a practical, always-available, low-power network link for remote control of the device from their phone — especially on a Raspberry Pi that may not have reliable WiFi or where you want to avoid WiFi for security/low power reasons.

Typical workflow:
- Pi and phone are paired over Bluetooth.
- Phone connects to the Pi using Bluetooth PAN (Personal Area Network).
- You get a direct IP link (bnep interface on Pi side).
- From the phone (Termux or JuiceSSH or RustDesk client) you SSH or remote-desktop to the Pi's bnep IP.
- No WiFi access point needed; low bandwidth, works over the Bluetooth radio.

The genmon script's BT broadcast strength control lets you keep this link usable without running the Pi at full discoverable power (which drains battery and generates heat).

### How to Make a Bluetooth Network You Can SSH Into From Your Phone

#### On the Pi (make it the NAP/server side)

1. Pair the phone (one-time):
   ```bash
   bluetoothctl
   power on
   discoverable on
   pairable on
   scan on
   # find your phone MAC
   pair XX:XX:XX:XX:XX:XX
   trust XX:XX:XX:XX:XX:XX
   exit
   ```

2. Enable the interface and IP (example using a common 192.168.7.0/24 subnet):
   After the phone initiates the PAN connection (most Android phones have a "Bluetooth tethering" or PAN option in developer options or Bluetooth settings), a bnepX interface will appear on the Pi.

   ```bash
   # Example assuming bnep0 appears
   sudo ip link set bnep0 up
   sudo ip addr add 192.168.7.1/24 dev bnep0
   sudo ip link set bnep0 up
   ```

3. (Optional but recommended for full "network") Enable IP forwarding and NAT if the phone should share the Pi's upstream connection:
   ```bash
   sudo sysctl -w net.ipv4.ip_forward=1
   sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
   ```

4. Make sure SSH is running and listening on the bnep IP:
   ```bash
   sudo systemctl enable --now ssh
   # Optionally restrict in /etc/ssh/sshd_config:
   # ListenAddress 192.168.7.1
   # PasswordAuthentication no
   # (use keys)
   ```

5. On the phone:
   - Connect to the Pi via Bluetooth PAN (the phone will get an IP like 192.168.7.2 or you can set static).
   - From Termux (or any SSH client):
     ```bash
     ssh youruser@192.168.7.1
     ```
   - For RustDesk or VNC: use the same IP as the host.

#### Using the genmon script with this setup

Use the action menu (or `genmon-network-action.sh --bt`) to set the BT level to MED or LOW. This keeps the PAN "available" for the phone to connect or stay connected at much lower power than HIGH. The power monitoring will also warn you if input voltage is sagging (critical when running remote sessions on marginal power).

This is exactly the use case the BT strength and power features were built for — practical, reliable Bluetooth remote control on real operator devices.

## License

See the individual scripts (generally permissive like the original genmon work).

Contributions and forks for different remote control use cases are welcome. If you improve the BT PAN SSH instructions or add phone-side scripts, PRs or issues are appreciated.

## Credits

This is the BDE (Big Dick Energy) evolution of the genmon network scripts that originated in the zeldoon/genmon_scripts repository and were heavily used and extended in the RAZOR RPi5 operator toolkit.

Use it, modify it, make your BT remote setups awesome (and power-efficient).
