# Power Managment

Centralize Omarchy power and idle options from the Quattro bar — screensaver, display off, auto-lock, idle suspend and lid-switch handling.

![Power Managment panel](preview.png)

## Features

- **Timings** — Screensaver, Display off (DPMS) and Auto-lock sliders plus dropdown (Never / 1m … 120m). Edits user-owned hypridle config with atomic write and backup, plus shell idle config sync.
- **Idle & Suspend** — IdleAction and IdleActionSec via systemd logind drop-in (explicit polkit authorization on Apply).
- **Lid** — Ignore Lid Close toggle (inhibitor + power-saver on close / restore on open) plus HandleLidSwitch settings (On battery / On AC / Docked). Auto-hidden on desktop without lid. Based on chupe/omarchy-lid-suspend.
- **Battery-aware** — Auto-detection of laptop vs desktop and power profile display.
- **Actions** — Five quick actions: Screensaver, Lock, Logout, Reboot and Shutdown (with confirmation for the last three).

## Installation

```bash
omarchy plugin add https://github.com/tug-benson/omarchy-power-managment --enable
```

Development symlink:

```bash
ln -s /path/to/omarchy-power-managment ~/.config/omarchy/plugins/io.github.tug-benson.power-managment
omarchy-shell shell rescanPlugins
```

Remove:

```bash
omarchy plugin remove io.github.tug-benson.power-managment
```

## Dependencies

Manual install via pacman (no auto-install):

```bash
sudo pacman -S --needed hypridle hyprlock power-profiles-daemon upower python3 polkit
```

- hypridle, hyprlock and hyprctl for idle/lock/DPMS
- systemd (systemd-analyze, systemd-logind) for suspend/lid
- upower and power-profiles-daemon for laptop/desktop detection
- python3 for helpers
- polkit for privileged writes to logind drop-in

## Usage

1. Click the power icon in the bar to open the panel.
2. **Timings** — Adjust Screensaver / Display off / Lock and click Apply timings.
3. **Idle & Suspend** — Choose Action and Delay and click Apply idle (polkit).
4. **Lid** — On laptop, toggle Ignore Lid Close or set On battery / On AC / Docked and Apply lid (polkit). On desktop the section is hidden.
5. Use Open hypridle.conf and Reload to inspect or refresh.

Defaults match Omarchy stock: screensaver 30m, lock 45m, display off disabled, IdleAction ignore.

## Security

- hypridle config edits are user-owned and atomic with backup, without sudo.
- logind writes only via explicit Apply with polkit, no hidden sudo in polling.
- Lid inhibitor uses a transient user systemd unit and file-based flag, with secure runtime directory handling.
- Input validation for timings and enums, no eval and no shell interpolation.

## Development

```bash
omarchy plugin validate ~/.config/omarchy/plugins/io.github.tug-benson.power-managment
qmllint -I "$OMARCHY_PATH/shell" ~/.config/omarchy/plugins/io.github.tug-benson.power-managment/*.qml
omarchy-shell shell summon io.github.tug-benson.power-managment '{}'
```

## Credits

- Lid inhibitor and power-profile logic adapted from chupe/omarchy-lid-suspend (MIT).
- Inspired by omarchy-kvm, omarchy-openvpn and omarchy-remmina patterns.

## License

MIT — see LICENSE.
