#!/usr/bin/env node
// cc-statusbar Settings TUI
// No dependencies - pure Node.js

const fs = require('fs');
const path = require('path');

const home = process.env.HOME || process.env.USERPROFILE;
const confPath = path.join(home, '.claude', 'statusline.conf');

// ─── ANSI ───
const ESC = '\x1b[';
const R = `${ESC}0m`, B = `${ESC}1m`, D = `${ESC}2m`;
const CYAN = `${ESC}36m`, GREEN = `${ESC}32m`, YELLOW = `${ESC}33m`, RED = `${ESC}31m`;
const GRAY = `${ESC}90m`, BLUE = `${ESC}34m`, WHITE = `${ESC}37m`;
const BG_BLUE = `${ESC}44m`, BG_RED = `${ESC}41m`;
const HIDE = `${ESC}?25l`, SHOW = `${ESC}?25h`, CLS = `${ESC}2J${ESC}H`;

// ─── Languages ───
const LANGUAGES = [
  { code: 'en', label: 'English',
    ctx: 'ctx', h5: '5h', d7: '7d', cost: 'cost', svc: 'svc', settings: 'settings',
    tui: { title: 'Settings', display: 'Display Sections', usage: 'Usage & Limits', ui: 'UI & Help', bar: 'Bar Appearance',
           model: 'Model name', path: 'Working directory', git: 'Git branch', context: 'Context usage',
           h5limit: '5-hour rate limit', d7limit: '7-day rate limit', sessionCost: 'Session cost (API)',
           lang: 'Language', hint: 'Settings hint', barStyle: 'Bar style', barWidth: 'Bar width (4-20)',
           reset: 'Reset all to defaults', nav: 'Navigate', toggle: 'Toggle', adjust: 'Adjust', exit: 'Exit',
           saved: 'Changes are saved instantly.', resetDone: 'Reset to defaults!', enterSelect: 'Enter to select' }},
  { code: 'ko', label: '한국어',
    ctx: '컨텍스트', h5: '5시간', d7: '7일', cost: '비용', svc: '서비스', settings: '설정',
    tui: { title: '설정', display: '표시 항목', usage: '사용량 & 한도', ui: 'UI & 도움말', bar: '바 모양',
           model: '모델 이름', path: '작업 디렉토리', git: 'Git 브랜치', context: '컨텍스트 사용량',
           h5limit: '5시간 사용 한도', d7limit: '7일 사용 한도', sessionCost: '세션 비용 (API)',
           lang: '언어', hint: '설정 힌트 표시', barStyle: '바 스타일', barWidth: '바 너비 (4-20)',
           reset: '모두 기본값으로 초기화', nav: '이동', toggle: '전환', adjust: '조절', exit: '나가기',
           saved: '변경사항이 즉시 저장됩니다.', resetDone: '기본값으로 초기화됨!', enterSelect: 'Enter로 선택' }},
  { code: 'ja', label: '日本語',
    ctx: 'ctx', h5: '5h', d7: '7d', cost: 'cost', svc: 'svc', settings: '設定',
    tui: { title: '設定', display: '表示項目', usage: '使用量と制限', ui: 'UIとヘルプ', bar: 'バーの外観',
           model: 'モデル名', path: '作業ディレクトリ', git: 'Gitブランチ', context: 'コンテキスト使用量',
           h5limit: '5時間制限', d7limit: '7日間制限', sessionCost: 'セッション費用 (API)',
           lang: '言語', hint: '設定ヒント', barStyle: 'バースタイル', barWidth: 'バー幅 (4-20)',
           reset: 'すべてデフォルトに戻す', nav: '移動', toggle: '切替', adjust: '調整', exit: '終了',
           saved: '変更は即座に保存されます。', resetDone: 'デフォルトにリセット！', enterSelect: 'Enterで選択' }},
  { code: 'zh', label: '中文',
    ctx: '上下文', h5: '5小时', d7: '7天', cost: '费用', svc: '服务', settings: '设置',
    tui: { title: '设置', display: '显示项目', usage: '用量与限额', ui: 'UI与帮助', bar: '进度条样式',
           model: '模型名称', path: '工作目录', git: 'Git分支', context: '上下文用量',
           h5limit: '5小时限额', d7limit: '7天限额', sessionCost: '会话费用 (API)',
           lang: '语言', hint: '设置提示', barStyle: '进度条样式', barWidth: '进度条宽度 (4-20)',
           reset: '全部恢复默认', nav: '导航', toggle: '切换', adjust: '调整', exit: '退出',
           saved: '更改已即时保存。', resetDone: '已恢复默认！', enterSelect: 'Enter选择' }},
  { code: 'es', label: 'Español',
    ctx: 'ctx', h5: '5h', d7: '7d', cost: 'coste', svc: 'svc', settings: 'config',
    tui: { title: 'Configuración', display: 'Secciones', usage: 'Uso y límites', ui: 'UI y ayuda', bar: 'Apariencia de barra',
           model: 'Nombre del modelo', path: 'Directorio', git: 'Rama Git', context: 'Uso de contexto',
           h5limit: 'Límite 5 horas', d7limit: 'Límite 7 días', sessionCost: 'Coste sesión (API)',
           lang: 'Idioma', hint: 'Mostrar ayuda', barStyle: 'Estilo de barra', barWidth: 'Ancho (4-20)',
           reset: 'Restablecer todo', nav: 'Navegar', toggle: 'Cambiar', adjust: 'Ajustar', exit: 'Salir',
           saved: 'Cambios guardados al instante.', resetDone: '¡Restablecido!', enterSelect: 'Enter para elegir' }},
  { code: 'fr', label: 'Français',
    ctx: 'ctx', h5: '5h', d7: '7j', cost: 'coût', svc: 'svc', settings: 'config',
    tui: { title: 'Paramètres', display: 'Sections', usage: 'Utilisation', ui: 'UI et aide', bar: 'Apparence barre',
           model: 'Nom du modèle', path: 'Répertoire', git: 'Branche Git', context: 'Utilisation contexte',
           h5limit: 'Limite 5h', d7limit: 'Limite 7j', sessionCost: 'Coût session (API)',
           lang: 'Langue', hint: 'Afficher aide', barStyle: 'Style de barre', barWidth: 'Largeur (4-20)',
           reset: 'Tout réinitialiser', nav: 'Naviguer', toggle: 'Basculer', adjust: 'Ajuster', exit: 'Quitter',
           saved: 'Enregistré instantanément.', resetDone: 'Réinitialisé !', enterSelect: 'Entrée pour choisir' }},
  { code: 'de', label: 'Deutsch',
    ctx: 'ctx', h5: '5h', d7: '7T', cost: 'Kosten', svc: 'svc', settings: 'Einst.',
    tui: { title: 'Einstellungen', display: 'Anzeigeabschnitte', usage: 'Nutzung & Limits', ui: 'UI & Hilfe', bar: 'Balken',
           model: 'Modellname', path: 'Verzeichnis', git: 'Git-Branch', context: 'Kontextnutzung',
           h5limit: '5-Stunden-Limit', d7limit: '7-Tage-Limit', sessionCost: 'Sitzungskosten (API)',
           lang: 'Sprache', hint: 'Einstellungshilfe', barStyle: 'Balkenstil', barWidth: 'Breite (4-20)',
           reset: 'Alles zurücksetzen', nav: 'Navigation', toggle: 'Umschalten', adjust: 'Anpassen', exit: 'Beenden',
           saved: 'Sofort gespeichert.', resetDone: 'Zurückgesetzt!', enterSelect: 'Enter zum Auswählen' }},
  { code: 'pt', label: 'Português',
    ctx: 'ctx', h5: '5h', d7: '7d', cost: 'custo', svc: 'svc', settings: 'config',
    tui: { title: 'Configurações', display: 'Seções', usage: 'Uso e limites', ui: 'UI e ajuda', bar: 'Aparência da barra',
           model: 'Nome do modelo', path: 'Diretório', git: 'Branch Git', context: 'Uso de contexto',
           h5limit: 'Limite 5h', d7limit: 'Limite 7d', sessionCost: 'Custo sessão (API)',
           lang: 'Idioma', hint: 'Dica de config', barStyle: 'Estilo da barra', barWidth: 'Largura (4-20)',
           reset: 'Redefinir tudo', nav: 'Navegar', toggle: 'Alternar', adjust: 'Ajustar', exit: 'Sair',
           saved: 'Salvo instantaneamente.', resetDone: 'Redefinido!', enterSelect: 'Enter para selecionar' }},
  { code: 'ru', label: 'Русский',
    ctx: 'ctx', h5: '5ч', d7: '7д', cost: 'цена', svc: 'svc', settings: 'настр.',
    tui: { title: 'Настройки', display: 'Разделы', usage: 'Использование', ui: 'UI и помощь', bar: 'Вид полосы',
           model: 'Имя модели', path: 'Каталог', git: 'Ветка Git', context: 'Использование контекста',
           h5limit: 'Лимит 5ч', d7limit: 'Лимит 7д', sessionCost: 'Стоимость (API)',
           lang: 'Язык', hint: 'Подсказка настроек', barStyle: 'Стиль полосы', barWidth: 'Ширина (4-20)',
           reset: 'Сбросить всё', nav: 'Навигация', toggle: 'Переключить', adjust: 'Настроить', exit: 'Выход',
           saved: 'Сохранено мгновенно.', resetDone: 'Сброшено!', enterSelect: 'Enter для выбора' }},
  { code: 'vi', label: 'Tiếng Việt',
    ctx: 'ctx', h5: '5g', d7: '7ng', cost: 'chi phí', svc: 'svc', settings: 'cài đặt',
    tui: { title: 'Cài đặt', display: 'Hiển thị', usage: 'Sử dụng & giới hạn', ui: 'UI & trợ giúp', bar: 'Thanh tiến trình',
           model: 'Tên model', path: 'Thư mục', git: 'Nhánh Git', context: 'Sử dụng ngữ cảnh',
           h5limit: 'Giới hạn 5g', d7limit: 'Giới hạn 7ng', sessionCost: 'Chi phí (API)',
           lang: 'Ngôn ngữ', hint: 'Gợi ý cài đặt', barStyle: 'Kiểu thanh', barWidth: 'Độ rộng (4-20)',
           reset: 'Đặt lại tất cả', nav: 'Di chuyển', toggle: 'Chuyển', adjust: 'Điều chỉnh', exit: 'Thoát',
           saved: 'Đã lưu ngay lập tức.', resetDone: 'Đã đặt lại!', enterSelect: 'Enter để chọn' }},
];

// ─── Bar styles ───
const STYLES = {
  blocks:    { fill: '▓', empty: '░', label: '▓░ Blocks' },
  dots:      { fill: '●', empty: '○', label: '●○ Dots' },
  squares:   { fill: '■', empty: '□', label: '■□ Squares' },
  lines:     { fill: '━', empty: '─', label: '━─ Lines' },
  triangles: { fill: '▰', empty: '▱', label: '▰▱ Triangles' },
  ascii:     { fill: '#', empty: '.', label: '#. ASCII' },
};

// ─── Config items (rebuilt on language change) ───
function t() {
  const lang = LANGUAGES.find(l => l.code === (values ? values.LANGUAGE : 'en')) || LANGUAGES[0];
  return lang.tui;
}

function buildItems() {
  const l = t();
  return [
    { key: '_hdr_display', type: 'header', label: l.display },
    { key: 'SHOW_MODEL', label: l.model, type: 'bool', default: 'true' },
    { key: 'SHOW_PATH', label: l.path, type: 'bool', default: 'true' },
    { key: 'SHOW_GIT_BRANCH', label: l.git, type: 'bool', default: 'true' },
    { key: '_hdr_usage', type: 'header', label: l.usage },
    { key: 'SHOW_CONTEXT', label: l.context, type: 'bool', default: 'true' },
    { key: 'SHOW_5H_LIMIT', label: l.h5limit, type: 'bool', default: 'true' },
    { key: 'SHOW_7D_LIMIT', label: l.d7limit, type: 'bool', default: 'true' },
    { key: 'SHOW_COST', label: l.sessionCost, type: 'bool', default: 'false' },
    { key: '_hdr_ui', type: 'header', label: l.ui },
    { key: 'LANGUAGE', label: `🌐 ${l.lang}`, type: 'language', default: 'en' },
    { key: 'SHOW_COMMANDS', label: l.hint, type: 'bool', default: 'true' },
    { key: 'SHOW_VERSION', label: 'Version (v1.0.32)', type: 'bool', default: 'true' },
    { key: 'SHOW_EFFORT', label: 'Effort level (effort:max etc.)', type: 'bool', default: 'true' },
    { key: 'SHOW_FAST', label: 'Fast mode (fast:on)', type: 'bool', default: 'true' },
    { key: '_hdr_bar', type: 'header', label: l.bar },
    { key: 'BAR_STYLE', label: l.barStyle, type: 'select', options: Object.keys(STYLES), default: 'blocks' },
    { key: 'BAR_WIDTH', label: l.barWidth, type: 'number', min: 4, max: 20, default: '10' },
    { key: '_hdr_reset', type: 'header', label: '' },
    { key: '_RESET', label: l.reset, type: 'action' },
  ];
}

const DEFAULTS = { SHOW_MODEL: 'true', SHOW_PATH: 'true', SHOW_GIT_BRANCH: 'true', SHOW_CONTEXT: 'true',
  SHOW_5H_LIMIT: 'true', SHOW_7D_LIMIT: 'true', SHOW_COST: 'false', SHOW_COMMANDS: 'true',
  SHOW_VERSION: 'true', SHOW_EFFORT: 'true', SHOW_FAST: 'true',
  LANGUAGE: 'en', BAR_STYLE: 'blocks', BAR_WIDTH: '10' };

// Display width: CJK/emoji = 2, others = 1
function strWidth(str) {
  let w = 0;
  for (const ch of str) {
    const cp = ch.codePointAt(0);
    if ((cp >= 0x1100 && cp <= 0x115F) || (cp >= 0x2E80 && cp <= 0xA4CF) ||
        (cp >= 0xAC00 && cp <= 0xD7AF) || (cp >= 0xF900 && cp <= 0xFAFF) ||
        (cp >= 0xFE10 && cp <= 0xFE6F) || (cp >= 0xFF00 && cp <= 0xFF60) ||
        (cp >= 0xFFE0 && cp <= 0xFFE6) || (cp >= 0x20000 && cp <= 0x2FFFD) ||
        (cp >= 0x30000 && cp <= 0x3FFFD) || (cp >= 0x1F000 && cp <= 0x1FAFF) ||
        (cp >= 0x3000 && cp <= 0x303F) || (cp >= 0x4E00 && cp <= 0x9FFF)) {
      w += 2;
    } else {
      w += 1;
    }
  }
  return w;
}

function pad(str, target) {
  const diff = target - strWidth(str);
  return str + ' '.repeat(Math.max(0, diff));
}

function getEditable() {
  return buildItems().filter(i => !['separator', 'header'].includes(i.type));
}

// ─── Config I/O ───
function load() {
  const v = { ...DEFAULTS };
  if (fs.existsSync(confPath)) {
    for (const line of fs.readFileSync(confPath, 'utf8').split('\n')) {
      const m = line.match(/^(\w+)=(.*)$/);
      if (m) v[m[1]] = m[2].replace(/^["']|["']$/g, '');
    }
  }
  return v;
}

function save(v) {
  const lines = ['# cc-statusbar configuration', '# Managed by /ccsconfig TUI', ''];
  lines.push('# Sections');
  const all = buildItems();
  all.filter(i => i.type === 'bool').forEach(i => lines.push(`${i.key}=${v[i.key] || i.default}`));
  lines.push(`LANGUAGE=${v.LANGUAGE || 'en'}`);
  lines.push('', '# Bar');
  all.filter(i => ['select', 'number'].includes(i.type)).forEach(i => lines.push(`${i.key}=${v[i.key] || i.default}`));
  lines.push('');
  fs.writeFileSync(confPath, lines.join('\n'));
}

// ─── State ───
let cursor = 0;
let values = load();
let message = '';
let messageTimer = null;
let subMenu = false;  // language sub-menu open
let subCursor = 0;

function showMsg(msg, color = GREEN) {
  message = `${color}${msg}${R}`;
  if (messageTimer) clearTimeout(messageTimer);
  messageTimer = setTimeout(() => { message = ''; render(); }, 2000);
}

function autoSave() {
  save(values);
}

// ─── Render ───
function render() {
  const W = 55;
  let out = CLS;

  const l = t();
  const items = buildItems();
  out += `  ${CYAN}${B}cc-statusbar ${l.title}${R}\n`;
  out += `${GRAY}  ${'─'.repeat(W)}${R}\n`;

  // Live preview
  const barStyle = values.BAR_STYLE || 'blocks';
  const barWidth = parseInt(values.BAR_WIDTH || '10');
  const PREVIEW_STYLES = {
    blocks: { fill: '▓', empty: '░' }, dots: { fill: '●', empty: '○' },
    squares: { fill: '■', empty: '□' }, lines: { fill: '━', empty: '─' },
    triangles: { fill: '▰', empty: '▱' }, ascii: { fill: '#', empty: '.' },
  };
  const ps = PREVIEW_STYLES[barStyle] || PREVIEW_STYLES.blocks;
  function prevBar(pct) {
    const n = Math.round(pct * barWidth / 100);
    return ps.fill.repeat(n) + ps.empty.repeat(barWidth - n);
  }
  const lang = LANGUAGES.find(la => la.code === (values.LANGUAGE || 'en')) || LANGUAGES[0];
  let prev = `  ${GRAY}Preview:${R} `;
  if (values.SHOW_MODEL !== 'false') prev += `${CYAN}${B}Model${R} `;
  if (values.SHOW_PATH !== 'false') prev += `${GRAY}|${R} ${BLUE}path${R} `;
  if (values.SHOW_CONTEXT !== 'false') prev += `${GRAY}|${R} ${lang.ctx} ${GREEN}${prevBar(21)} 21%${R} `;
  if (values.SHOW_5H_LIMIT !== 'false') prev += `${GRAY}|${R} ${lang.h5} ${GREEN}${prevBar(45)} 45%${R} `;
  if (values.SHOW_7D_LIMIT !== 'false') prev += `${GRAY}|${R} ${lang.d7} ${GREEN}${prevBar(4)} 4%${R} `;
  if (values.SHOW_COMMANDS !== 'false') prev += `${GRAY}|${R} ${D}${GRAY}${lang.settings}: npx cc-statusbar${R}`;
  out += prev + '\n';
  out += `${GRAY}  ${'─'.repeat(W)}${R}\n`;

  let editIdx = 0;
  for (const item of items) {
    if (item.type === 'header') {
      out += `\n  ${CYAN}${B}${item.label}${R}\n`;
      continue;
    }
    if (item.type === 'separator') continue;

    const sel = editIdx === cursor;
    const pre = sel ? `${BG_BLUE}${WHITE}${B} ▸ ` : '   ';

    const val = values[item.key] || item.default;
    let display = '';

    if (item.type === 'bool') {
      const on = val === 'true';
      const check = on ? `${sel ? R + ' ' : ''}${GREEN}[✓]${R}` : `${sel ? R + ' ' : ''}${RED}[ ]${R}`;
      display = `${pad(item.label, 30)}${check}`;
    } else if (item.type === 'select') {
      const styleInfo = STYLES[val] || {};
      const label = styleInfo.label || val;
      const hint = sel ? ` ${D}← →${R}` : '';
      display = `${pad(item.label, 30)}${sel ? R + ' ' : ''}${YELLOW}${label}${R}${hint}`;
    } else if (item.type === 'number') {
      const num = parseInt(val);
      const canDec = num > (item.min || 1);
      const canInc = num < (item.max || 20);
      const hint = sel ? ` ${D}← ${canDec ? '−' : ' '} ${canInc ? '+' : ' '} →${R}` : '';
      display = `${pad(item.label, 30)}${sel ? R + ' ' : ''}${YELLOW}${val}${R}${hint}`;
    } else if (item.type === 'language') {
      const lang = LANGUAGES.find(l => l.code === val) || LANGUAGES[0];
      const hint = sel ? ` ${D}${t().enterSelect}${R}` : '';
      display = `${pad(item.label, 30)}${sel ? R + ' ' : ''}${YELLOW}${lang.label}${R}${hint}`;
      out += `${pre}${display}${sel ? ' ' + R : ''}\n`;
      // Show sub-menu if open
      if (subMenu && sel) {
        for (let li = 0; li < LANGUAGES.length; li++) {
          const l = LANGUAGES[li];
          const lsel = li === subCursor;
          const lpre = lsel ? `     ${BG_BLUE}${WHITE}${B} ▸ ` : '       ';
          out += `${lpre}${l.label} ${GRAY}(${l.code})${R}${lsel ? ' ' + R : ''}\n`;
        }
      }
      editIdx++;
      continue;
    } else if (item.type === 'action') {
      const actionPre = sel ? `${BG_BLUE}${WHITE}${B} ▸ ` : `  ${GRAY}`;
      out += `${actionPre}${item.label}${sel ? ' ' + R : R}\n`;
      editIdx++;
      continue;
    }

    out += `${pre}${display}${sel ? ' ' + R : ''}\n`;
    editIdx++;
  }

  out += `\n${GRAY}  ${'─'.repeat(W)}${R}\n`;
  out += `  ${D}↑↓${R} ${l.nav}  ${D}Space/Enter${R} ${l.toggle}  ${D}←→${R} ${l.adjust}  ${D}Esc${R} ${l.exit}\n`;
  out += `  ${GRAY}${l.saved}${R}\n`;

  if (message) out += `  ${message}\n`;

  process.stdout.write(out);
}

// ─── Input ───
function handleKey(key) {
  const item = getEditable()[cursor];

  // Sub-menu mode (language selection)
  if (subMenu) {
    if (key === '\x1b[A') {
      subCursor = subCursor <= 0 ? LANGUAGES.length - 1 : subCursor - 1;
    } else if (key === '\x1b[B') {
      subCursor = subCursor >= LANGUAGES.length - 1 ? 0 : subCursor + 1;
    } else if (key === '\r' || key === ' ') {
      values[item.key] = LANGUAGES[subCursor].code;
      subMenu = false;
      autoSave();
    } else if (key === '\x1b') {
      subMenu = false;
    }
    render();
    return;
  }

  // Navigation
  if (key === '\x1b[A') { // Up (wrap)
    cursor = cursor <= 0 ? getEditable().length - 1 : cursor - 1;
  } else if (key === '\x1b[B') { // Down (wrap)
    cursor = cursor >= getEditable().length - 1 ? 0 : cursor + 1;
  }
  // Toggle (Space or Enter)
  else if (key === ' ' || key === '\r') {
    if (item.type === 'bool') {
      values[item.key] = values[item.key] === 'true' ? 'false' : 'true';
      autoSave();
    } else if (item.type === 'select') {
      const idx = item.options.indexOf(values[item.key]);
      values[item.key] = item.options[(idx + 1) % item.options.length];
      autoSave();
    } else if (item.type === 'language') {
      const idx = LANGUAGES.findIndex(l => l.code === values[item.key]);
      subCursor = idx >= 0 ? idx : 0;
      subMenu = true;
    } else if (item.type === 'action' && item.key === '_RESET') {
      values = { ...DEFAULTS };
      autoSave();
      showMsg(t().resetDone, YELLOW);
    }
  }
  // Right arrow
  else if (key === '\x1b[C') {
    if (item.type === 'number') {
      const num = parseInt(values[item.key] || item.default);
      if (num < (item.max || 20)) {
        values[item.key] = String(num + 1);
        autoSave();
      }
    } else if (item.type === 'select') {
      const idx = item.options.indexOf(values[item.key]);
      values[item.key] = item.options[(idx + 1) % item.options.length];
      autoSave();
    }
  }
  // Left arrow
  else if (key === '\x1b[D') {
    if (item.type === 'number') {
      const num = parseInt(values[item.key] || item.default);
      if (num > (item.min || 1)) {
        values[item.key] = String(num - 1);
        autoSave();
      }
    } else if (item.type === 'select') {
      const idx = item.options.indexOf(values[item.key]);
      values[item.key] = item.options[(idx - 1 + item.options.length) % item.options.length];
      autoSave();
    }
  }
  // Exit (Esc)
  else if (key === '\x1b') {
    cleanup();
    process.exit(0);
  }
  // Ignore everything else (한글 etc.)

  render();
}

function cleanup() {
  process.stdout.write(SHOW);
  process.stdin.setRawMode(false);
  process.stdout.write(CLS);
}

// ─── Main ───
if (!process.stdin.isTTY) {
  console.log('Error: Requires interactive terminal.');
  console.log('Run: node C:\\Users\\' + (process.env.USERNAME || 'YOU') + '\\.claude\\config-ui.js');
  process.exit(1);
}

process.stdout.write(HIDE);
process.stdin.setRawMode(true);
process.stdin.resume();
process.stdin.setEncoding('utf8');
process.on('exit', cleanup);
process.on('SIGINT', () => { cleanup(); process.exit(0); });

render();

process.stdin.on('data', (data) => {
  for (let i = 0; i < data.length; i++) {
    if (data[i] === '\x1b' && i + 2 < data.length && data[i + 1] === '[') {
      handleKey(data.slice(i, i + 3));
      i += 2;
    } else {
      handleKey(data[i]);
    }
  }
});
