# WebDock

맥 창을 브라우저에서 원격 조작하는 앱입니다.

**언어:** [English](../README.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [中文](README.zh.md) · [Deutsch](README.de.md) · [Français](README.fr.md)

웹 UI도 EN / KO / JA / ZH / DE / FR 지원 (상단 언어 메뉴).

---

## 기능

| 기능 | 설명 |
|------|------|
| 창 / 전체 화면 스트리밍 | ScreenCaptureKit |
| 원격 입력 | 마우스, 키보드, 스크롤, 한글 조합 |
| 가려진 창 | 다른 앱이 위에 있어도 대상 창을 앞으로 올린 뒤 입력 |
| 화질 | 프리셋 + JPEG / PNG / H.264 |
| 인증 | 선택적 접속 토큰 |
| LAN | 같은 Wi‑Fi의 다른 기기에서 접속 |

**보안:** LAN을 열면 토큰을 강하게 설정하세요. 공인 인터넷에 포트를 그대로 노출하지 마세요.

---

## 요구 사항

**맥 (서버)**

- macOS 14+
- Xcode 또는 Command Line Tools (`xcode-select --install`)
- 권한: **화면 기록**, **손쉬운 사용**

**클라이언트**

- 최신 Chrome / Edge / Safari / Firefox

---

## 설치 (권장)

### Releases (빌드된 앱 · 권장)

Xcode 없이 바로 쓸 수 있습니다.

1. [**Releases**](https://github.com/alice-cli/WebDock/releases) 열기  
2. 다운로드 (둘 중 하나)  
   - **`WebDock-macOS-*.pkg`** — 설치 프로그램 → **응용 프로그램**에 설치  
   - **`WebDock-macOS-*.zip`** — 압축 해제 후 `WebDock.app` 실행  
3. **시스템 설정 → 개인정보 보호 및 보안**  
   - **화면 기록** · **손쉬운 사용** 허용  
4. 앱에서 **서버** 토글 ON (기본 OFF · 켜 두면 다음 실행 때 자동 시작)  
5. 브라우저 `http://127.0.0.1:8080` → 창 선택  

각 릴리스에 **한·영·일·중·독·프** 설치 안내가 있습니다.

### 소스에서

```bash
git clone https://github.com/alice-cli/WebDock.git
cd WebDock
chmod +x build_app.sh install_home.sh
./install_home.sh
```

설치 경로: **`~/WebDock.app`**

### 첫 실행

1. WebDock 설정 → 서버 시작 (기본 포트 `8080`)  
2. **접속 토큰** 설정 (권장), 필요 시 **LAN 허용**  
3. 화면 기록 / 손쉬운 사용 권한  
4. 브라우저: `http://127.0.0.1:8080` 또는 `http://<맥_LAN_IP>:8080`  
5. 토큰 입력 → 창 선택 → 조작  

---

## 빌드

```bash
swift build -c release
./build_app.sh
./install_home.sh
```

---

## 설정

`~/Library/Application Support/WebDock/config.ini`

```ini
[server]
enabled = true
port = 8080
allow_lan = true

[auth]
token = 비밀-토큰
```

---

## 사용 팁

- **UI 언어:** 웹 상단 언어 선택 (브라우저에 저장)
- **한글:** **한 / A** 또는 Ctrl+Space · Windows 로컬 한글은 끄는 것 권장
- **화질:** 빠름 / 균형 / 방송 · JPG / PNG / H.264
- **모니터 절전:** 유효한 클라이언트 접속 시 화면 깨움

---

## 문제 해결

| 증상 | 확인 |
|------|------|
| 검은 화면 / 목록 비움 | 화면 기록 권한, 디스플레이 깨우기 |
| 클릭·키 무시 | 손쉬운 사용 권한 |
| 브라우저 연결 안 됨 | 서버, 포트, LAN, 방화벽, 토큰 |
| `swift` 없음 | Xcode 또는 CLT 설치 |

---

## 라이선스

[MIT](../LICENSE)
