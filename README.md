# WebDock

**맥에 떠 있는 창을 브라우저로 원격 조작하는 앱**입니다.  
Windows·다른 Mac·폰 브라우저에서 접속해 마우스·키보드로 제어할 수 있습니다.

- 호스트: **macOS 14+**
- 클라이언트: 최신 Chrome / Edge / Safari / Firefox
- 소스: Swift Package Manager (외부 패키지 의존성 없음)

---

## 무엇을 하나요?

| 기능 | 설명 |
|------|------|
| 창 / 전체 화면 스트리밍 | ScreenCaptureKit으로 선택한 창 또는 디스플레이를 전송 |
| 원격 입력 | 클릭, 드래그, 스크롤, 키보드, 한/영(클라이언트 2벌식 조합) |
| 웹 UI | 창 목록, 앱 실행, 화질 프리셋(JPG/PNG/H.264), 클립보드 연동 |
| 토큰 인증 | 설정한 접속 토큰이 있어야 웹 UI 진입 |
| LAN 공유 | 같은 Wi‑Fi의 다른 기기에서 `http://맥IP:포트` 접속 |

**보안 주의:** LAN을 열면 같은 네트워크의 다른 사람도 주소만 알면 접근을 시도할 수 있습니다.  
토큰을 반드시 쓰고, 공인 인터넷에 포트를 그대로 노출하지 마세요.

---

## 요구 사항

### 맥 (서버)

- macOS **14 Sonoma** 이상
- [Xcode](https://developer.apple.com/xcode/) 또는 **Command Line Tools**  
  (`xcode-select --install`)
- Swift 6 도구 체인 (Xcode에 포함)
- 권한 (최초 실행 시 설정):
  - **화면 기록 (Screen Recording)**
  - **손쉬운 사용 (Accessibility)** — 원격 클릭·키 입력용

### 브라우저 (클라이언트)

- 데스크톱 또는 모바일 최신 브라우저
- 같은 PC / 같은 LAN / (고급) 터널·VPN 뒤의 주소

---

## 인증서가 필요한가?

| 목적 | Apple 개발자 인증서 필요? | 설명 |
|------|---------------------------|------|
| **소스 받아서 직접 빌드·사용** | **아니오** | 아래 설치 스크립트만으로 가능 |
| 재빌드할 때마다 권한 다시 묻히지 않기 | **아니오** (로컬 자체 서명 권장) | `./setup_dev_cert.sh` — Apple 유료 계정 불필요 |
| Gatekeeper 경고 없이 **다운로드 배포** (공증) | **예** (Apple Developer Program, 유료) | 현재 저장소는 공증(notarize) 릴리스를 기본 제공하지 않음 |
| Mac App Store 배포 | **예** | 별도 심사·사이닝 |

### 일반 사용자 (맥에 설치해서 쓰기)

1. 이 저장소를 clone 하거나 ZIP 다운로드  
2. `./install_home.sh` 실행  
3. 시스템 설정에서 **화면 기록 / 손쉬운 사용** 허용  
4. Gatekeeper가 막으면: Finder에서 앱 **우클릭 → 열기** 한 번  

**Apple Developer Program 가입은 필수가 아닙니다.**

### 개발자 (자주 다시 빌드)

ad-hoc 서명으로 빌드하면 macOS가 “다른 앱”으로 보고 **화면 기록 권한을 매번** 다시 물어볼 수 있습니다.  
로컬 전용 인증서를 한 번 만들어 두면 서명이 안정되어 권한이 유지됩니다.

```bash
./setup_dev_cert.sh   # 로컬 키체인 + "WebDock Dev" 인증서 (Apple 계정 불필요)
./install_home.sh
```

### 타인에게 .app 파일만 뿌리고 싶을 때

- **공증 없음:** 받는 사람이 “확인되지 않은 개발자” 경고를 보고 **우클릭 → 열기** 해야 함  
- **공증 있음:** Apple Developer 계정 + `notarytool` 필요 (이 README 범위 밖)

---

## 빠른 설치 (권장)

터미널에서:

```bash
git clone https://github.com/alice-cli/WebDock.git
cd WebDock
chmod +x build_app.sh install_home.sh setup_dev_cert.sh

# (선택) 권한 유지용 로컬 서명 — 재빌드가 잦으면 권장
./setup_dev_cert.sh

# 빌드 → ~/WebDock.app 설치 → 실행
./install_home.sh
```

설치 위치: **`~/WebDock.app`**  
다시 설치해도 같은 경로를 쓰므로 시스템 설정 권한 항목이 비교적 안정적입니다.

### 첫 실행 체크리스트

1. Dock 또는 `~/WebDock.app` 실행  
2. 설정 창에서:
   - 서버 켜기  
   - 포트 (기본 `8080`)  
   - **접속 토큰** 설정 (권장)  
   - 다른 기기 접속 시 **LAN 허용**  
3. **시스템 설정 → 개인정보 보호 및 보안**
   - 화면 기록 → WebDock 체크  
   - 손쉬운 사용 → WebDock 체크  
4. 브라우저에서:
   - 같은 맥: `http://127.0.0.1:8080`  
   - 다른 기기: `http://<맥의_LAN_IP>:8080`  
5. 토큰 입력 후 창 선택 → 원격 조작  

방화벽이 켜져 있으면 WebDock / 해당 포트 허용이 필요할 수 있습니다.

---

## 빌드만 하기

```bash
# 릴리스 바이너리
swift build -c release

# .app 번들 생성 (아이콘 포함, codesign)
./build_app.sh
# → ./WebDock.app
```

`build_app.sh`가 하는 일:

1. `swift build -c release`  
2. `MacRemote.png` → Dock 아이콘(`.icns`) + 웹 파비콘  
3. `WebDock.app` 구성 + `Info.plist`  
4. 가능하면 **WebDock Dev** 로컬 인증서로 서명, 없으면 ad-hoc 서명  

---

## 설정 파일

경로:

```text
~/Library/Application Support/WebDock/config.ini
```

예시:

```ini
[server]
enabled = true
port = 8080
allow_lan = true

[auth]
token = 여기에_긴_비밀문자열
```

- `allow_lan = false` 이면 `127.0.0.1` 만 접속  
- 토큰이 비어 있으면 인증 없이 UI 열림 (로컬 테스트용, 비권장)

---

## 사용 팁

### 원격 한글

- 웹 UI의 **한 / A** 버튼 또는 **Ctrl+Space** (원격 캔버스 포커스 시)  
- Windows에서는 **로컬 한글 IME를 끄고** WebDock 한 모드로 치는 것을 권장  
- 한글 모드는 브라우저에서 2벌식 조합 후 유니코드로 전송 (맥 IME 조합 깨짐 회피)

### 화질

- 프리셋: 빠름 / 균형 / 방송  
- 포맷: JPG / PNG / H.264 (브라우저 WebCodecs 지원 시)

### 모니터가 꺼져 있을 때

- 서버만 켜 둔 상태에서는 절전 가능  
- **토큰이 맞는 접속**이 오면 디스플레이를 깨움  

### 권한을 다시 허용해야 할 때

- 앱 경로를 바꿨거나, ad-hoc으로 자주 다시 빌드한 경우  
- 시스템 설정에서 **이전 WebDock 항목 삭제** 후 `~/WebDock.app`만 다시 허용  
- 개발 시: `./setup_dev_cert.sh` 후 `./install_home.sh` 로 서명 고정  

---

## 프로젝트 구조

```text
WebDock/
├── Package.swift          # SPM
├── Sources/
│   ├── main.swift
│   ├── App/               # 설정 UI, 메뉴바, 서버 수명
│   ├── Capture/           # ScreenCaptureKit, JPEG/PNG/H.264
│   ├── Config/            # config.ini
│   ├── Input/             # 마우스·키보드·포커스·IME
│   ├── Server/            # HTTP + WebSocket
│   └── WebUI/             # 임베드된 HTML/CSS/JS
├── MacRemote.png          # 앱/웹 아이콘 원본
├── build_app.sh           # .app 빌드 + 서명
├── install_home.sh        # ~/WebDock.app 설치
└── setup_dev_cert.sh      # 로컬 개발용 서명 인증서
```

---

## 문제 해결

| 증상 | 확인 |
|------|------|
| 검은 화면 / 창 목록 비어 있음 | 화면 기록 권한, 맥 디스플레이 깨우기 |
| 클릭·키가 안 먹음 | 손쉬운 사용 권한, 대상 창이 앞에 있는지 |
| 브라우저 연결 거부 | 서버 ON, 포트, LAN 허용, 방화벽, 토큰 |
| “확인되지 않은 개발자” | Finder에서 우클릭 → 열기 |
| 빌드마다 권한 초기화 | `./setup_dev_cert.sh` 후 같은 경로(`~/WebDock.app`)에 설치 |
| `swift: command not found` | Xcode 또는 CLT 설치 |

---

## 라이선스

[MIT](LICENSE) — 자유롭게 사용·수정·배포할 수 있습니다.  
이 소프트웨어는 있는 그대로 제공되며, 원격 제어로 인한 보안 사고에 대해 작성자는 책임지지 않습니다. 토큰·방화벽·네트워크 범위를 스스로 관리하세요.

---

## 기여

이슈와 PR을 환영합니다.  
큰 기능 변경 전에는 이슈로 먼저 논의해 주세요.
