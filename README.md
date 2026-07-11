# WebDock

Remote-control a Mac window from any browser.

**Languages / 언어:** [English](README.md) · [한국어](docs/README.ko.md) · [日本語](docs/README.ja.md) · [中文](docs/README.zh.md) · [Deutsch](docs/README.de.md) · [Français](docs/README.fr.md)

The **web UI** also supports EN / KO / JA / ZH / DE / FR (language menu in the header).

---

## Features

| Feature | Description |
|---------|-------------|
| Window / display streaming | ScreenCaptureKit |
| Remote input | Mouse, keyboard, scroll, Hangul compose |
| Covered windows | Raises the target app when another window is in front |
| Quality | Presets + JPEG / PNG / H.264 |
| Auth | Optional access token |
| LAN | Connect from other devices on the same Wi‑Fi |

**Security:** If LAN is enabled, use a strong token. Do not expose the port to the public internet unprotected.

---

## Requirements

**Host (Mac)**

- macOS 14+
- Xcode or Command Line Tools (`xcode-select --install`)
- Permissions: **Screen Recording**, **Accessibility**

**Client**

- Modern Chrome / Edge / Safari / Firefox

---

## Install (recommended)

### From Releases

1. Open [Releases](https://github.com/alice-cli/WebDock/releases)
2. Download `WebDock-macOS-*.zip`
3. Unzip and run `WebDock.app`
4. Enable **Screen Recording** and **Accessibility** in System Settings

### From source

```bash
git clone https://github.com/alice-cli/WebDock.git
cd WebDock
chmod +x build_app.sh install_home.sh
./install_home.sh
```

Installs to **`~/WebDock.app`** and launches the app.

### First run

1. Open WebDock settings → start server (default port `8080`)
2. Set an access **token** (recommended) and enable **LAN** if needed
3. Grant Screen Recording + Accessibility
4. Browser: `http://127.0.0.1:8080` or `http://<Mac-LAN-IP>:8080`
5. Enter token → select a window → control

---

## Build

```bash
swift build -c release
./build_app.sh          # → ./WebDock.app
./install_home.sh       # install to ~/WebDock.app
```

`build_app.sh`: release binary, app icons from `MacRemote.png`, package `WebDock.app`.

---

## Config

`~/Library/Application Support/WebDock/config.ini`

```ini
[server]
enabled = true
port = 8080
allow_lan = true

[auth]
token = your-secret-token
```

---

## Tips

- **UI language:** header language selector (saved in `localStorage`)
- **Hangul:** use **한 / A** or Ctrl+Space on the remote canvas; turn off local Hangul IME on Windows if possible
- **Quality:** Fast / Balanced / Live; JPG / PNG / H.264
- **Display sleep:** monitor can sleep until a valid client connects

---

## Project layout

```text
WebDock/
├── Package.swift
├── Sources/          # App, Capture, Config, Input, Server, WebUI
├── docs/             # Multi-language README
├── MacRemote.png
├── build_app.sh
└── install_home.sh
```

---

## Troubleshooting

| Issue | Check |
|-------|--------|
| Black screen / empty list | Screen Recording permission, wake display |
| Clicks / keys ignored | Accessibility permission |
| Browser cannot connect | Server on, port, LAN, firewall, token |
| `swift: command not found` | Install Xcode or CLT |

---

## License

[MIT](LICENSE)

Use responsibly. You are responsible for tokens, firewall, and network exposure.
