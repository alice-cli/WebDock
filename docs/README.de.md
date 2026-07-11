# WebDock

Mac-Fenster im Browser fernsteuern.

**Sprachen:** [English](../README.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [中文](README.zh.md) · [Deutsch](README.de.md) · [Français](README.fr.md)

Die **Web-UI** unterstützt EN / KO / JA / ZH / DE / FR (Sprachmenü in der Kopfzeile).

---

## Funktionen

| Funktion | Beschreibung |
|----------|--------------|
| Fenster- / Display-Streaming | ScreenCaptureKit |
| Remote-Eingabe | Maus, Tastatur, Scroll, Hangul |
| Verdeckte Fenster | Ziel-App wird nach vorne geholt |
| Qualität | Presets + JPEG / PNG / H.264 |
| Auth | Optionaler Token |
| LAN | Andere Geräte im selben Wi‑Fi |

**Sicherheit:** Bei LAN starken Token nutzen. Port nicht ungeschützt ins Internet legen.

---

## Voraussetzungen

**Host (Mac)**

- macOS 14+
- Xcode oder Command Line Tools
- Rechte: **Bildschirmaufnahme**, **Bedienungshilfen**

**Client**

- Aktueller Chrome / Edge / Safari / Firefox

---

## Installation

### Releases (vorgefertigte App · empfohlen)

Kein Xcode nötig.

1. [**Releases**](https://github.com/alice-cli/WebDock/releases)
2. **`WebDock-macOS-*.zip`** laden
3. Entpacken → **`WebDock.app`** starten
4. **Bildschirmaufnahme** + **Bedienungshilfen** erlauben
5. Server starten (Port **8080**)
6. Browser: `http://127.0.0.1:8080`

Release-Notizen mit Schritten in **EN / KO / JA / ZH / DE / FR**.

### Aus dem Quellcode

```bash
git clone https://github.com/alice-cli/WebDock.git
cd WebDock
chmod +x build_app.sh install_home.sh
./install_home.sh
```

Ziel: **`~/WebDock.app`**

### Erster Start

1. Server starten (Port standardmäßig `8080`)
2. **Token** setzen, optional **LAN**
3. Rechte erteilen
4. Browser: `http://127.0.0.1:8080` oder LAN-IP
5. Token → Fenster wählen → steuern

---

## Build

```bash
swift build -c release
./build_app.sh
./install_home.sh
```

---

## Konfiguration

`~/Library/Application Support/WebDock/config.ini`

```ini
[server]
enabled = true
port = 8080
allow_lan = true

[auth]
token = geheim
```

---

## Tipps

- **UI-Sprache:** Auswahl in der Kopfzeile
- **Hangul:** **한 / A** oder Ctrl+Space
- **Qualität:** Fast / Balanced / Live · JPG / PNG / H.264

---

## Fehlerbehebung

| Problem | Prüfen |
|---------|--------|
| Schwarzer Bildschirm | Bildschirmaufnahme, Display wecken |
| Klicks/Tasten tot | Bedienungshilfen |
| Keine Verbindung | Server, Port, LAN, Firewall, Token |

---

## Lizenz

[MIT](../LICENSE)
