import Foundation

/// Browser UI strings: ko / en / ja / zh / de / fr
let webDockI18nJS = """
// ── i18n ──────────────────────────────────────────────
const I18N = {
  ko: {
    menu:'목록', menuTitle:'창·앱 목록', sideTitle:'창 · 앱', close:'닫기',
    quick:'퀵 런처', edit:'편집', done:'완료', clients:'접속 중',
    tabWin:'창', tabApp:'앱', emptyTitle:'창을 선택하세요',
    emptyBody:'상단 <b>목록</b>에서 창을 고르거나<br><b>앱</b> 탭에서 실행하세요',
    txtPh:'텍스트 입력 · Enter 전송', send:'전송', imeTitle:'한/영 전환',
    preFast:'빠름', preBal:'균형', preLive:'방송', quality:'화질',
    refresh:'목록 새로고침', fit:'맞춤', zoomIn:'확대', zoomOut:'축소',
    clipAutoOn:'📋 자동', clipAutoOff:'📋 수동', clipPull:'가져오기',
    connecting:'연결 중…', connected:'연결됨', disconnected:'연결 끊김 — 재시도 중…',
    connError:'연결 오류', authFail:'인증 실패 — 토큰을 확인하세요',
    busy:'다른 곳에서 입력 중입니다', themeLight:'라이트 모드로 전환', themeDark:'다크 모드로 전환',
    cancel:'취소', confirm:'확인', searchWin:'창 · 앱 이름 검색…', searchApp:'앱 검색…',
    loadingApps:'앱 목록을 불러오는 중…', noSearch:'검색 결과가 없습니다',
    pinQuick:'퀵 런처에 고정', unpin:'고정 해제', newWin:'새 창 열기',
    closeWin:'이 창만 닫기 (앱 전체 종료 아님)', refreshList:'목록 새로고침 중…',
    streaming:'스트리밍', closing:'창 닫는 중…', pinned:'고정됨', pinFail:'고정 실패',
    launching:'실행 중…', newInstance:'새 창 여는 중…',
    paste:'붙여넣기', pasteRemote:'원격 붙여넣기 (Mac 클립보드)',
    clipOn:'클립보드 자동 가져오기 ON', clipOff:'클립보드 자동 가져오기 OFF',
    clipPulling:'원격 클립보드 가져오는 중…', clipEmpty:'원격 클립보드 비어 있음',
    clipOk:'원격 복사 → 이 기기 클립보드', clipBlocked:'클립보드 쓰기 막힘',
    imeKo:'현재: 한글 — 클릭하면 영문(A)', imeEn:'현재: 영문(A) — 클릭하면 한글',
    fitDevice:'화면: 기기 해상도 맞춤', fitAll:'화면: 전체 맞춤',
    resFit:'해상도 맞춤', qhint:'앱 탭에서 + 로 자주 쓰는 앱을 고정하세요',
    qhintEdit:' · 삭제는 편집', lang:'언어', disk:'디스크'
  },
  en: {
    menu:'Menu', menuTitle:'Windows & apps', sideTitle:'Windows · Apps', close:'Close',
    quick:'Quick launch', edit:'Edit', done:'Done', clients:'Connected',
    tabWin:'Windows', tabApp:'Apps', emptyTitle:'Select a window',
    emptyBody:'Pick a window from <b>Menu</b> or launch an app under <b>Apps</b>',
    txtPh:'Type text · Enter to send', send:'Send', imeTitle:'Hangul / Latin',
    preFast:'Fast', preBal:'Balanced', preLive:'Live', quality:'Quality',
    refresh:'Refresh list', fit:'Fit', zoomIn:'Zoom in', zoomOut:'Zoom out',
    clipAutoOn:'📋 Auto', clipAutoOff:'📋 Manual', clipPull:'Pull',
    connecting:'Connecting…', connected:'Connected', disconnected:'Disconnected — retrying…',
    connError:'Connection error', authFail:'Auth failed — check token',
    busy:'Another client is typing', themeLight:'Switch to light mode', themeDark:'Switch to dark mode',
    cancel:'Cancel', confirm:'OK', searchWin:'Search windows…', searchApp:'Search apps…',
    loadingApps:'Loading apps…', noSearch:'No results',
    pinQuick:'Pin to quick launch', unpin:'Unpin', newWin:'New window',
    closeWin:'Close this window only', refreshList:'Refreshing…',
    streaming:'Streaming', closing:'Closing window…', pinned:'Pinned', pinFail:'Pin failed',
    launching:'Launching…', newInstance:'Opening new window…',
    paste:'Paste', pasteRemote:'Remote paste (Mac clipboard)',
    clipOn:'Clipboard auto-pull ON', clipOff:'Clipboard auto-pull OFF',
    clipPulling:'Pulling remote clipboard…', clipEmpty:'Remote clipboard empty',
    clipOk:'Remote copy → this device', clipBlocked:'Clipboard write blocked',
    imeKo:'Hangul mode — click for Latin', imeEn:'Latin mode — click for Hangul',
    fitDevice:'View: fit device', fitAll:'View: fit all',
    resFit:'Resolution', qhint:'Pin apps from the Apps tab with +',
    qhintEdit:' · edit to remove', lang:'Language', disk:'Disk'
  },
  ja: {
    menu:'一覧', menuTitle:'ウィンドウとアプリ', sideTitle:'ウィンドウ · アプリ', close:'閉じる',
    quick:'クイック起動', edit:'編集', done:'完了', clients:'接続中',
    tabWin:'ウィンドウ', tabApp:'アプリ', emptyTitle:'ウィンドウを選択',
    emptyBody:'<b>一覧</b>からウィンドウを選ぶか、<b>アプリ</b>から起動してください',
    txtPh:'テキスト入力 · Enterで送信', send:'送信', imeTitle:'韓国語 / 英字',
    preFast:'高速', preBal:'バランス', preLive:'配信', quality:'画質',
    refresh:'一覧を更新', fit:'合わせる', zoomIn:'拡大', zoomOut:'縮小',
    clipAutoOn:'📋 自動', clipAutoOff:'📋 手動', clipPull:'取得',
    connecting:'接続中…', connected:'接続済み', disconnected:'切断 — 再接続中…',
    connError:'接続エラー', authFail:'認証失敗 — トークンを確認',
    busy:'他のクライアントが入力中', themeLight:'ライトモード', themeDark:'ダークモード',
    cancel:'キャンセル', confirm:'OK', searchWin:'ウィンドウ検索…', searchApp:'アプリ検索…',
    loadingApps:'読み込み中…', noSearch:'結果なし',
    pinQuick:'クイックに固定', unpin:'固定解除', newWin:'新しいウィンドウ',
    closeWin:'このウィンドウだけ閉じる', refreshList:'更新中…',
    streaming:'配信中', closing:'閉じています…', pinned:'固定済み', pinFail:'固定失敗',
    launching:'起動中…', newInstance:'新しいウィンドウを開いています…',
    paste:'貼り付け', pasteRemote:'リモート貼り付け',
    clipOn:'クリップボード自動 ON', clipOff:'クリップボード自動 OFF',
    clipPulling:'取得中…', clipEmpty:'クリップボードが空です',
    clipOk:'リモート → この端末', clipBlocked:'書き込み不可',
    imeKo:'ハングル — クリックで英字', imeEn:'英字 — クリックでハングル',
    fitDevice:'表示: 端末に合わせる', fitAll:'表示: 全体',
    resFit:'解像度', qhint:'アプリタブで + を押して固定',
    qhintEdit:' · 編集で削除', lang:'言語', disk:'ディスク'
  },
  zh: {
    menu:'列表', menuTitle:'窗口与应用', sideTitle:'窗口 · 应用', close:'关闭',
    quick:'快捷启动', edit:'编辑', done:'完成', clients:'已连接',
    tabWin:'窗口', tabApp:'应用', emptyTitle:'请选择窗口',
    emptyBody:'从顶部<b>列表</b>选择窗口，或在<b>应用</b>中启动',
    txtPh:'输入文字 · Enter 发送', send:'发送', imeTitle:'韩文 / 英文',
    preFast:'流畅', preBal:'均衡', preLive:'直播', quality:'画质',
    refresh:'刷新列表', fit:'适应', zoomIn:'放大', zoomOut:'缩小',
    clipAutoOn:'📋 自动', clipAutoOff:'📋 手动', clipPull:'拉取',
    connecting:'连接中…', connected:'已连接', disconnected:'已断开 — 重试中…',
    connError:'连接错误', authFail:'认证失败 — 请检查令牌',
    busy:'其他客户端正在输入', themeLight:'切换到浅色', themeDark:'切换到深色',
    cancel:'取消', confirm:'确定', searchWin:'搜索窗口…', searchApp:'搜索应用…',
    loadingApps:'正在加载应用…', noSearch:'无结果',
    pinQuick:'固定到快捷栏', unpin:'取消固定', newWin:'新窗口',
    closeWin:'仅关闭此窗口', refreshList:'刷新中…',
    streaming:'串流中', closing:'正在关闭…', pinned:'已固定', pinFail:'固定失败',
    launching:'启动中…', newInstance:'正在打开新窗口…',
    paste:'粘贴', pasteRemote:'远程粘贴（Mac 剪贴板）',
    clipOn:'剪贴板自动拉取 开', clipOff:'剪贴板自动拉取 关',
    clipPulling:'正在拉取…', clipEmpty:'远程剪贴板为空',
    clipOk:'远程复制 → 本机', clipBlocked:'无法写入剪贴板',
    imeKo:'韩文 — 点击切换英文', imeEn:'英文 — 点击切换韩文',
    fitDevice:'视图：适配设备', fitAll:'视图：全部适配',
    resFit:'分辨率', qhint:'在应用页用 + 固定常用应用',
    qhintEdit:' · 编辑可删除', lang:'语言', disk:'磁盘'
  },
  de: {
    menu:'Liste', menuTitle:'Fenster & Apps', sideTitle:'Fenster · Apps', close:'Schließen',
    quick:'Schnellstart', edit:'Bearbeiten', done:'Fertig', clients:'Verbunden',
    tabWin:'Fenster', tabApp:'Apps', emptyTitle:'Fenster wählen',
    emptyBody:'Fenster über <b>Liste</b> wählen oder App unter <b>Apps</b> starten',
    txtPh:'Text · Enter senden', send:'Senden', imeTitle:'Hangul / Latein',
    preFast:'Schnell', preBal:'Ausgewogen', preLive:'Live', quality:'Qualität',
    refresh:'Liste aktualisieren', fit:'Anpassen', zoomIn:'Vergrößern', zoomOut:'Verkleinern',
    clipAutoOn:'📋 Auto', clipAutoOff:'📋 Manuell', clipPull:'Abrufen',
    connecting:'Verbinden…', connected:'Verbunden', disconnected:'Getrennt — erneut…',
    connError:'Verbindungsfehler', authFail:'Auth fehlgeschlagen — Token prüfen',
    busy:'Anderer Client tippt', themeLight:'Hellmodus', themeDark:'Dunkelmodus',
    cancel:'Abbrechen', confirm:'OK', searchWin:'Fenster suchen…', searchApp:'Apps suchen…',
    loadingApps:'Apps laden…', noSearch:'Keine Treffer',
    pinQuick:'Anheften', unpin:'Lösen', newWin:'Neues Fenster',
    closeWin:'Nur dieses Fenster schließen', refreshList:'Aktualisiere…',
    streaming:'Streaming', closing:'Schließe…', pinned:'Angeheftet', pinFail:'Anheften fehlgeschlagen',
    launching:'Startet…', newInstance:'Neues Fenster…',
    paste:'Einfügen', pasteRemote:'Remote-Einfügen',
    clipOn:'Zwischenablage Auto AN', clipOff:'Zwischenablage Auto AUS',
    clipPulling:'Lade Zwischenablage…', clipEmpty:'Remote-Zwischenablage leer',
    clipOk:'Remote → dieses Gerät', clipBlocked:'Schreiben blockiert',
    imeKo:'Hangul — Klick für Latein', imeEn:'Latein — Klick für Hangul',
    fitDevice:'Ansicht: Gerät', fitAll:'Ansicht: alles',
    resFit:'Auflösung', qhint:'Apps mit + anheften',
    qhintEdit:' · Bearbeiten zum Entfernen', lang:'Sprache', disk:'Disk'
  },
  fr: {
    menu:'Liste', menuTitle:'Fenêtres et apps', sideTitle:'Fenêtres · Apps', close:'Fermer',
    quick:'Lancement rapide', edit:'Modifier', done:'OK', clients:'Connectés',
    tabWin:'Fenêtres', tabApp:'Apps', emptyTitle:'Choisir une fenêtre',
    emptyBody:'Choisissez via <b>Liste</b> ou lancez une app sous <b>Apps</b>',
    txtPh:'Texte · Entrée pour envoyer', send:'Envoyer', imeTitle:'Hangul / Latin',
    preFast:'Rapide', preBal:'Équilibré', preLive:'Live', quality:'Qualité',
    refresh:'Actualiser', fit:'Ajuster', zoomIn:'Zoom +', zoomOut:'Zoom −',
    clipAutoOn:'📋 Auto', clipAutoOff:'📋 Manuel', clipPull:'Récupérer',
    connecting:'Connexion…', connected:'Connecté', disconnected:'Déconnecté — nouvel essai…',
    connError:'Erreur de connexion', authFail:'Auth échouée — vérifier le jeton',
    busy:'Un autre client saisit', themeLight:'Mode clair', themeDark:'Mode sombre',
    cancel:'Annuler', confirm:'OK', searchWin:'Rechercher…', searchApp:'Rechercher apps…',
    loadingApps:'Chargement…', noSearch:'Aucun résultat',
    pinQuick:'Épingler', unpin:'Retirer', newWin:'Nouvelle fenêtre',
    closeWin:'Fermer cette fenêtre seule', refreshList:'Actualisation…',
    streaming:'Diffusion', closing:'Fermeture…', pinned:'Épinglé', pinFail:'Échec',
    launching:'Lancement…', newInstance:'Ouverture…',
    paste:'Coller', pasteRemote:'Coller distant',
    clipOn:'Presse-papiers auto ON', clipOff:'Presse-papiers auto OFF',
    clipPulling:'Récupération…', clipEmpty:'Presse-papiers distant vide',
    clipOk:'Distant → cet appareil', clipBlocked:'Écriture bloquée',
    imeKo:'Hangul — clic pour latin', imeEn:'Latin — clic pour hangul',
    fitDevice:'Vue : appareil', fitAll:'Vue : tout',
    resFit:'Résolution', qhint:'Épingler les apps avec +',
    qhintEdit:' · modifier pour retirer', lang:'Langue', disk:'Disque'
  }
};

function detectLang(){
  const saved = localStorage.getItem('webdock.lang');
  if (saved && I18N[saved]) return saved;
  const n = (navigator.language || 'en').toLowerCase();
  if (n.startsWith('ko')) return 'ko';
  if (n.startsWith('ja')) return 'ja';
  if (n.startsWith('zh')) return 'zh';
  if (n.startsWith('de')) return 'de';
  if (n.startsWith('fr')) return 'fr';
  return 'en';
}
let lang = detectLang();

function t(key){
  const pack = I18N[lang] || I18N.en;
  return pack[key] || I18N.en[key] || key;
}

function setLang(code){
  if (!I18N[code]) code = 'en';
  lang = code;
  localStorage.setItem('webdock.lang', code);
  document.documentElement.lang = code === 'zh' ? 'zh-CN' : code;
  applyI18n();
  const sel = document.getElementById('langSelect');
  if (sel) sel.value = code;
}

function applyI18n(){
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const k = el.getAttribute('data-i18n');
    if (!k) return;
    if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') return;
    const html = el.getAttribute('data-i18n-html') === '1';
    if (html) el.innerHTML = t(k);
    else el.textContent = t(k);
  });
  document.querySelectorAll('[data-i18n-title]').forEach(el => {
    el.title = t(el.getAttribute('data-i18n-title'));
  });
  document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
    el.placeholder = t(el.getAttribute('data-i18n-placeholder'));
  });
  // dynamic labels that use classes
  const cancel = document.getElementById('modalCancel');
  if (cancel) cancel.textContent = t('cancel');
  const ok = document.getElementById('modalOk');
  if (ok && !modalResolve) ok.textContent = t('confirm');
  const qeb = document.getElementById('quickEditBtn');
  if (qeb) qeb.textContent = quickEdit ? t('done') : t('edit');
  const menuBtn = document.getElementById('menuBtn');
  if (menuBtn && !document.body.classList.contains('side-open')) {
    // mobile closed label
  }
  syncClipAutoBtn();
  applyIMEState(imeKorean);
  const themeBtn = document.getElementById('themeBtn');
  if (themeBtn) {
    const light = document.documentElement.classList.contains('light');
    themeBtn.title = light ? t('themeDark') : t('themeLight');
  }
}

"""
