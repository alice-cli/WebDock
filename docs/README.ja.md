# WebDock

Mac のウィンドウをブラウザから遠隔操作するアプリです。

**言語:** [English](../README.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [中文](README.zh.md) · [Deutsch](README.de.md) · [Français](README.fr.md)

Web UI も EN / KO / JA / ZH / DE / FR 対応（ヘッダーの言語メニュー）。

---

## 機能

| 機能 | 説明 |
|------|------|
| ウィンドウ / 画面ストリーミング | ScreenCaptureKit |
| リモート入力 | マウス・キーボード・スクロール・ハングル入力 |
| 前面にない窓 | 他アプリが被っていても対象を前面にして入力 |
| 画質 | プリセット + JPEG / PNG / H.264 |
| 認証 | 任意のアクセストークン |
| LAN | 同じ Wi‑Fi の他端末から接続 |

**セキュリティ:** LAN を開く場合は強いトークンを使ってください。インターネットにポートをそのまま公開しないでください。

---

## 必要環境

**ホスト (Mac)**

- macOS 14+
- Xcode または Command Line Tools
- 権限: **画面収録**、**アクセシビリティ**

**クライアント**

- 最新の Chrome / Edge / Safari / Firefox

---

## インストール

### Releases（ビルド済み・推奨）

Xcode 不要です。

1. [**Releases**](https://github.com/alice-cli/WebDock/releases)
2. **`WebDock-macOS-*.zip`** をダウンロード
3. 解凍 → **`WebDock.app`** を開く
4. **画面収録** と **アクセシビリティ** を許可
5. アプリでサーバー開始（ポート **8080**）
6. ブラウザ `http://127.0.0.1:8080`

リリースページに **EN / KO / JA / ZH / DE / FR** の手順があります。

### ソースから

```bash
git clone https://github.com/alice-cli/WebDock.git
cd WebDock
chmod +x build_app.sh install_home.sh
./install_home.sh
```

インストール先: **`~/WebDock.app`**

### 初回

1. 設定でサーバー開始（ポート既定 `8080`）
2. **トークン** 設定（推奨）、必要なら **LAN**
3. 画面収録 / アクセシビリティ
4. ブラウザ: `http://127.0.0.1:8080` または `http://<MacのLAN_IP>:8080`
5. トークン入力 → ウィンドウ選択 → 操作

---

## ビルド

```bash
swift build -c release
./build_app.sh
./install_home.sh
```

---

## 設定

`~/Library/Application Support/WebDock/config.ini`

```ini
[server]
enabled = true
port = 8080
allow_lan = true

[auth]
token = your-secret
```

---

## ヒント

- **UI 言語:** ヘッダーの言語選択
- **ハングル:** **한 / A** または Ctrl+Space
- **画質:** 高速 / バランス / 配信 · JPG / PNG / H.264

---

## トラブルシュート

| 症状 | 確認 |
|------|------|
| 黒画面 / 一覧が空 | 画面収録、ディスプレイ起床 |
| クリック・キー無効 | アクセシビリティ |
| 接続できない | サーバー、ポート、LAN、ファイアウォール、トークン |

---

## ライセンス

[MIT](../LICENSE)
