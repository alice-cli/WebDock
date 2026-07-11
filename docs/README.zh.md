# WebDock

通过浏览器远程控制 Mac 窗口。

**语言:** [English](../README.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [中文](README.zh.md) · [Deutsch](README.de.md) · [Français](README.fr.md)

Web UI 支持 EN / KO / JA / ZH / DE / FR（页眉语言菜单）。

---

## 功能

| 功能 | 说明 |
|------|------|
| 窗口 / 全屏串流 | ScreenCaptureKit |
| 远程输入 | 鼠标、键盘、滚轮、韩文输入 |
| 被遮挡的窗口 | 其他应用在前时也会把目标窗口置前再输入 |
| 画质 | 预设 + JPEG / PNG / H.264 |
| 认证 | 可选访问令牌 |
| LAN | 同一 Wi‑Fi 下其他设备访问 |

**安全：** 开启 LAN 时请使用强令牌，不要把端口直接暴露到公网。

---

## 要求

**主机 (Mac)**

- macOS 14+
- Xcode 或 Command Line Tools
- 权限：**屏幕录制**、**辅助功能**

**客户端**

- 最新 Chrome / Edge / Safari / Firefox

---

## 安装

### Releases

1. 打开 [Releases](https://github.com/alice-cli/WebDock/releases)
2. 下载 `WebDock-macOS-*.zip`
3. 解压并运行 `WebDock.app`
4. 在系统设置中允许 **屏幕录制** 与 **辅助功能**

### 从源码

```bash
git clone https://github.com/alice-cli/WebDock.git
cd WebDock
chmod +x build_app.sh install_home.sh
./install_home.sh
```

安装路径：**`~/WebDock.app`**

### 首次运行

1. 设置中启动服务器（默认端口 `8080`）
2. 设置访问 **令牌**（推荐），需要时开启 **LAN**
3. 授权屏幕录制 / 辅助功能
4. 浏览器：`http://127.0.0.1:8080` 或 `http://<Mac-LAN-IP>:8080`
5. 输入令牌 → 选择窗口 → 控制

---

## 构建

```bash
swift build -c release
./build_app.sh
./install_home.sh
```

---

## 配置

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

## 提示

- **界面语言：** 页眉语言选择
- **韩文：** **한 / A** 或 Ctrl+Space
- **画质：** 流畅 / 均衡 / 直播 · JPG / PNG / H.264

---

## 故障排除

| 问题 | 检查 |
|------|------|
| 黑屏 / 列表为空 | 屏幕录制、唤醒显示器 |
| 点击/按键无效 | 辅助功能 |
| 无法连接 | 服务器、端口、LAN、防火墙、令牌 |

---

## 许可证

[MIT](../LICENSE)
