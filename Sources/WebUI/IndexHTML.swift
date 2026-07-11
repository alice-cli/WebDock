import Foundation

/// Assembles the single-page WebDock UI (CSS + markup + JS).
enum WebUI {
    static var indexHTML: String {
        """
        <!doctype html>
        <html lang="ko">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
        <meta name="mobile-web-app-capable" content="yes">
        <meta name="theme-color" content="#0a0b0d">
        <title>WebDock</title>
        <link rel="icon" type="image/png" sizes="32x32" href="/favicon.png">
        <link rel="icon" type="image/png" sizes="192x192" href="/favicon-192.png">
        <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
        <link rel="shortcut icon" href="/favicon.png">
        <style>
        \(webDockCSS)
        </style>
        </head>
        <body>
          <div id="modal" role="dialog" aria-modal="true" aria-labelledby="modalTitle">
            <div class="modal-card">
              <h3 class="modal-title" id="modalTitle">확인</h3>
              <p class="modal-body" id="modalBody"></p>
              <div class="modal-actions">
                <button type="button" class="btn ghost" id="modalCancel">취소</button>
                <button type="button" class="btn danger" id="modalOk">확인</button>
              </div>
            </div>
          </div>

          <!-- 상단 헤더: CPU/RAM/디스크 항상 표시 (햄버거 없음) -->
          <header id="topbar">
            <button type="button" id="menuBtn" class="textbtn" onclick="toggleSidebar()" title="창·앱 목록">목록</button>
            <span id="dot" title="연결 상태"></span>
            <div id="metrics" class="metrics" aria-label="시스템 리소스">
              <span class="metric" id="mCpu" title="CPU">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><rect x="5" y="5" width="14" height="14" rx="1"/><path d="M9 2v3M15 2v3M9 19v3M15 19v3M2 9h3M2 15h3M19 9h3M19 15h3"/></svg>
                <span class="metric-val" id="mCpuVal">–</span>
              </span>
              <span class="metric" id="mRam" title="RAM">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><rect x="3" y="7" width="18" height="10" rx="1"/><path d="M7 7v10M12 7v10M17 7v10"/></svg>
                <span class="metric-val" id="mRamVal">–</span>
              </span>
              <span class="metric" id="mDisk" title="디스크">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><ellipse cx="12" cy="6" rx="8" ry="3"/><path d="M4 6v6c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12v6c0 1.7 3.6 3 8 3s8-1.3 8-3v-6"/></svg>
                <span class="metric-val" id="mDiskVal">–</span>
              </span>
            </div>
            <span id="fps">– fps</span>
            <button id="themeBtn" class="iconbtn" onclick="toggleTheme()" title="라이트/다크 전환" aria-label="테마 전환">
              <svg class="icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <circle cx="12" cy="12" r="4"/>
                <path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/>
              </svg>
              <svg class="icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d="M21 14.5A8.5 8.5 0 1 1 9.5 3a7 7 0 0 0 11.5 11.5z"/>
              </svg>
            </button>
          </header>

          <div id="sideBackdrop" onclick="closeSidebar()" aria-hidden="true"></div>
          <div id="shell">
            <div id="side">
              <div class="side-head">
                <span class="side-title">창 · 앱</span>
                <button type="button" class="textbtn" onclick="closeSidebar()" title="닫기">닫기</button>
              </div>
              <div id="quick">
                <div class="section">
                  <span>퀵 런처 <span class="count" id="quickCount">0</span></span>
                  <button type="button" class="section-btn" id="quickEditBtn" onclick="toggleQuickEdit()" title="고정 해제 편집">편집</button>
                </div>
                <div id="quickList"></div>
              </div>
              <div id="clients">
                <div class="section">접속 중 <span class="count" id="clientCount">0</span></div>
                <div id="clientList" class="client-list"></div>
              </div>
              <div class="tabs">
                <button class="tab active" id="tabWin" onclick="setMode('windows')" title="열린 창">
                  창 <span class="badge" id="winBadge">0</span>
                </button>
                <button class="tab" id="tabApp" onclick="setMode('apps')" title="앱 목록">
                  앱 <span class="badge" id="appBadge">0</span>
                </button>
              </div>
              <div id="list"></div>
            </div>
            <div id="main">
              <div id="stage">
                <div id="empty">
                  <div class="empty-icon">▢</div>
                  <strong>창을 선택하세요</strong>
                  상단 <b>목록</b>에서 창을 고르거나<br>
                  <b>앱</b> 탭에서 실행하세요
                </div>
                <canvas id="cv" tabindex="0" style="display:none"></canvas>
                <div id="grip" title="드래그하여 창 크기 조절"></div>
              </div>
              <div id="bar">
                <input id="txt" placeholder="텍스트 입력 · Enter 전송" autocomplete="off" spellcheck="false" enterkeyhint="send" inputmode="text">
                <div class="bar-actions">
                  <button class="btn" onclick="sendText()">전송</button>
                  <button id="imeBtn" class="en" onclick="toggleIME()" title="한/영 전환">
                    <span class="ime-side" id="imeKo">한</span>
                    <span class="ime-side" id="imeEn">A</span>
                  </button>
                  <div class="fmt" title="화질 프리셋">
                    <button type="button" class="fmt-btn" id="preFast" onclick="setPreset('fast')">빠름</button>
                    <button type="button" class="fmt-btn on" id="preBal" onclick="setPreset('balanced')">균형</button>
                    <button type="button" class="fmt-btn" id="preLive" onclick="setPreset('broadcast')">방송</button>
                  </div>
                  <div class="fmt" title="스트림 포맷">
                    <button type="button" class="fmt-btn on" id="fmtJpeg" onclick="setFormat('jpeg')">JPG</button>
                    <button type="button" class="fmt-btn" id="fmtPng" onclick="setFormat('png')">PNG</button>
                    <button type="button" class="fmt-btn" id="fmtH264" onclick="setFormat('h264')" title="H.264 하드웨어 방송 (WebCodecs)">H264</button>
                  </div>
                  <label class="q" id="qLabel" title="JPEG 화질 (PNG는 무손실, 슬라이더 무시)">화질 <input id="q" type="range" min="0.2" max="1" step="0.05" value="0.92" oninput="setQuality(this.value)"><span id="qVal">92%</span></label>
                </div>
              </div>
              <div id="status">
                <button class="mini" onclick="toggleBar()" title="입력 바 토글">⌨︎</button>
                <button class="mini" onclick="refreshList()" title="목록 새로고침">↻</button>
                <button class="mini" onclick="resetViewAuto()" title="화면에 맞게 (모바일: 원격 창 해상도 맞춤)">맞춤</button>
                <button class="mini" onclick="zoomInStep()" title="확대">＋</button>
                <button class="mini" onclick="zoomOutStep()" title="축소">－</button>
                <span id="zoomHint" class="zoom-hint">100%</span>
                <button type="button" class="mini clip-auto on" id="clipAutoBtn" onclick="toggleClipAuto()" aria-pressed="true" title="원격 복사 시 이 기기 클립보드로 자동 가져오기">📋 자동</button>
                <button type="button" class="mini" id="clipPullBtn" onclick="pullRemoteClipboard()" title="지금 원격 클립보드 가져오기">가져오기</button>
                <span id="statusText">연결 중…</span>
                <span class="keys"></span>
              </div>
            </div>
          </div>
        <script>
        \(webDockJS)
        </script>
        </body>
        </html>
        """
    }
}
