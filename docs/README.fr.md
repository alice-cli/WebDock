# WebDock

Contrôlez une fenêtre Mac depuis le navigateur.

**Langues :** [English](../README.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [中文](README.zh.md) · [Deutsch](README.de.md) · [Français](README.fr.md)

L’**interface web** gère EN / KO / JA / ZH / DE / FR (menu langue en en-tête).

---

## Fonctionnalités

| Fonction | Description |
|----------|-------------|
| Flux fenêtre / écran | ScreenCaptureKit |
| Entrée distante | Souris, clavier, molette, hangul |
| Fenêtres masquées | L’app cible est ramenée au premier plan |
| Qualité | Préréglages + JPEG / PNG / H.264 |
| Auth | Jeton d’accès optionnel |
| LAN | Autres appareils sur le même Wi‑Fi |

**Sécurité :** avec le LAN, utilisez un jeton fort. N’ouvrez pas le port sur Internet sans protection.

---

## Prérequis

**Hôte (Mac)**

- macOS 14+
- Xcode ou Command Line Tools
- Permissions : **Enregistrement de l’écran**, **Accessibilité**

**Client**

- Chrome / Edge / Safari / Firefox récents

---

## Installation

### Releases (binaire · recommandé)

Sans Xcode.

1. [**Releases**](https://github.com/alice-cli/WebDock/releases)
2. Télécharger **`WebDock-macOS-*.zip`**
3. Décompresser → lancer **`WebDock.app`**
4. Autoriser **Enregistrement de l’écran** et **Accessibilité**
5. Démarrer le serveur (port **8080**)
6. Navigateur : `http://127.0.0.1:8080`

Les notes de version incluent EN / KO / JA / ZH / DE / FR.

### Depuis les sources

```bash
git clone https://github.com/alice-cli/WebDock.git
cd WebDock
chmod +x build_app.sh install_home.sh
./install_home.sh
```

Chemin : **`~/WebDock.app`**

### Première utilisation

1. Démarrer le serveur (port `8080` par défaut)
2. Définir un **jeton** (recommandé), activer le **LAN** si besoin
3. Accorder les permissions
4. Navigateur : `http://127.0.0.1:8080` ou IP LAN
5. Jeton → choisir une fenêtre → contrôler

---

## Build

```bash
swift build -c release
./build_app.sh
./install_home.sh
```

---

## Configuration

`~/Library/Application Support/WebDock/config.ini`

```ini
[server]
enabled = true
port = 8080
allow_lan = true

[auth]
token = secret
```

---

## Astuces

- **Langue UI :** sélecteur en en-tête
- **Hangul :** **한 / A** ou Ctrl+Espace
- **Qualité :** Rapide / Équilibré / Live · JPG / PNG / H.264

---

## Dépannage

| Problème | Vérifier |
|----------|----------|
| Écran noir | Enregistrement d’écran, réveil moniteur |
| Clics / touches ignorés | Accessibilité |
| Pas de connexion | Serveur, port, LAN, pare-feu, jeton |

---

## Licence

[MIT](../LICENSE)
