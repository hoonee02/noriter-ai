import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'tauri_bridge.dart' as tauri;
import 'worker_bridge.dart';

// Business logic (message formatting, Ollama request preprocessing) runs
// off the main/UI thread in a Web Worker -- see lib/worker_main.dart and
// lib/worker/logic.dart. The worker is started once at boot and talked to
// over postMessage for the lifetime of the page.
late final WorkerBridge _worker;

void main() {
  _worker = WorkerBridge.start();

  final root = web.document.getElementById('app')!;
  root.innerHTML = '''
    <div class="chat">
      <div class="header">
        <span>Noriter AI</span>
        <div class="headerBtns">
          <button id="queueBtn" type="button">📋 큐</button>
          <button id="modelBtn" type="button">🧠 모델</button>
          <button id="telegramBtn" type="button">✈ 텔레그램</button>
          <button id="promptBtn" type="button">📝 프롬프트</button>
          <button id="memoryBtn" type="button">🧑 메모리</button>
          <button id="wikiBtn" type="button">📚 위키</button>
          <button id="settingsBtn" type="button">⚙ 설정</button>
        </div>
      </div>

      <div id="queuePanel" class="panel hidden">
        <p class="panelDesc">
          웹 채팅과 텔레그램에서 들어온 생성 요청은 하나의 대기열을 통해 순서대로만
          처리됩니다 (동시에 두 개가 Ollama를 부르지 않도록). 여기서 실시간으로 보여줍니다.
        </p>
        <div id="queueList" class="queueList"></div>
      </div>

      <div id="modelPanel" class="panel hidden">
        <div id="modelHealth" class="modelHealth"></div>
        <div class="panelRow">
          <button id="modelVerify" type="button">🔍 Ollama 연결 확인 &amp; 목록 새로고침</button>
          <span id="modelConnStatus"></span>
        </div>
        <label>사용할 모델
          <select id="cfgModel"></select>
        </label>
        <div class="panelActions">
          <button id="modelSave" type="button">모델 저장</button>
          <span id="modelStatus"></span>
        </div>
      </div>

      <div id="telegramPanel" class="panel hidden">
        <p class="panelDesc">
          텔레그램 브릿지를 켜면, 이 봇으로 온 메시지를 로컬 Ollama 모델에 전달해 답장까지
          자동으로 보내줍니다. 앱 창을 닫아 트레이로 내려가 있어도 계속 동작하고,
          창을 다시 열면 그동안 오간 대화가 채팅창에도 표시됩니다.
        </p>
        <label>텔레그램 봇 토큰
          <input id="cfgToken" type="text" placeholder="123456:ABC-..." />
        </label>
        <label class="checkbox">
          <input id="cfgEnabled" type="checkbox" />
          텔레그램 브릿지 사용
        </label>
        <div class="panelActions">
          <button id="telegramSave" type="button">저장 &amp; 적용</button>
          <span id="telegramStatus"></span>
        </div>
      </div>

      <div id="promptPanel" class="panel hidden">
        <p class="panelDesc">
          사진/파일을 캡션 없이 보내면(텔레그램 클라이언트에 따라 캡션을 못 붙이는 경우가 있습니다)
          아래 문구가 프롬프트로 대신 쓰입니다. 비워두면 기본 문구("첨부된 내용을 확인하고
          설명해주세요.")가 사용됩니다. 대화 기억은 없으므로 이 프롬프트는 매번 새로 적용됩니다.
        </p>
        <label>첨부파일 기본 프롬프트
          <textarea id="cfgAttachmentPrompt" rows="4" placeholder="첨부된 내용을 확인하고 설명해주세요."></textarea>
        </label>
        <div class="panelActions">
          <button id="promptSave" type="button">저장</button>
          <span id="promptStatus"></span>
        </div>
      </div>

      <div id="memoryPanel" class="panel hidden">
        <p class="panelDesc">
          여기 있는 내용은 웹/텔레그램 모든 대화에 항상 참고 정보로 포함됩니다 (재시작해도
          유지됨). 대화 중 5턴마다 자동으로 기억할 만한 내용이 있는지도 확인해 추가합니다.
          📌 고정하면 항상 우선 포함됩니다.
        </p>
        <div id="memoryList" class="entryList"></div>
        <label>새 항목 내용
          <textarea id="memoryContent" rows="2" placeholder="예: 사용자는 GTX 1660 6GB VRAM 환경을 사용한다"></textarea>
        </label>
        <div class="panelRow">
          <label>분류
            <select id="memoryCategory">
              <option value="fact">fact</option>
              <option value="hardware">hardware</option>
              <option value="preference">preference</option>
              <option value="instruction">instruction</option>
              <option value="other">other</option>
            </select>
          </label>
          <label class="checkbox"><input id="memoryPinned" type="checkbox" /> 📌 고정</label>
        </div>
        <div class="panelActions">
          <button id="memorySave" type="button">추가</button>
          <button id="memoryCancelEdit" type="button" class="hidden">취소</button>
          <span id="memoryStatus"></span>
        </div>
      </div>

      <div id="wikiPanel" class="panel hidden">
        <p class="panelDesc">
          대화 중 나온 내용을 문서로 정리해서 보관합니다 (자동 생성 안 됨 -- 직접 저장해야
          쌓입니다). 나중에 찾아볼 수 있는 "찾아보는 자료"입니다.
        </p>
        <div id="wikiList" class="entryList"></div>
        <label>제목
          <input id="wikiTitle" type="text" placeholder="예: 예제모음.xlsx 데이터 구조" />
        </label>
        <label>요약
          <input id="wikiSummary" type="text" placeholder="한 줄 요약" />
        </label>
        <label>본문
          <textarea id="wikiBody" rows="4" placeholder="마크다운으로 자유롭게"></textarea>
        </label>
        <label>태그 (쉼표로 구분)
          <input id="wikiTags" type="text" placeholder="excel, telegram" />
        </label>
        <div class="panelActions">
          <button id="wikiSave" type="button">저장</button>
          <button id="wikiCancelEdit" type="button" class="hidden">취소</button>
          <span id="wikiStatus"></span>
        </div>
      </div>

      <div id="settingsPanel" class="panel hidden">
        <label>컨텍스트 크기
          <div class="sliderRow">
            <input id="cfgContextSize" type="range" min="512" max="32768" step="512" />
            <span id="cfgContextSizeValue" class="sliderValue"></span>
          </div>
        </label>
        <div class="panelActions">
          <button id="settingsSave" type="button">저장</button>
          <span id="settingsStatus"></span>
        </div>
      </div>

      <div id="log" class="log"></div>
      <form id="form" class="composer">
        <input id="input" type="text" placeholder="메시지를 입력하세요" autocomplete="off" />
        <button type="submit">보내기</button>
      </form>
    </div>
  '''
      .toJS;

  _wire();
  _loadModelPanel();
  _loadTelegramPanel();
  _loadPromptPanel();
  _loadSettingsPanel();
}

String _escapeHtml(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Every message (web chat and mirrored Telegram traffic alike) gets a
/// generation timestamp; assistant replies additionally get token count +
/// generation time once available (Ollama reports `eval_count`, and wall
/// time is measured on the Rust side -- see ollama.rs's `ChatResult`).
/// The timestamp/stats formatting and HTML-escaping happen in the Web
/// Worker (lib/worker/logic.dart's `formatMessage`), not here -- this
/// function just renders whatever the worker hands back.
/// Returns the created element so callers can fill in the final text/stats
/// once an async reply completes (see the "..." placeholder pattern below).
Future<web.HTMLElement> _appendMessage(String who, String text, {int? tokensUsed, int? elapsedMs}) async {
  final formatted = await _worker.call('formatMessage', {
    'text': text,
    if (tokensUsed != null) 'tokensUsed': tokensUsed,
    if (elapsedMs != null) 'elapsedMs': elapsedMs,
  });

  final log = web.document.getElementById('log')!;
  final line = web.document.createElement('div') as web.HTMLDivElement;
  line.className = 'msg $who';
  line.innerHTML = '''
    <div class="msgText">${formatted['escapedText']}</div>
    <div class="msgMeta">${formatted['meta']}</div>
  '''
      .toJS;
  log.appendChild(line);
  log.scrollTop = log.scrollHeight;
  return line;
}

Future<void> _updateMessage(web.HTMLElement line, String text, {int? tokensUsed, int? elapsedMs}) async {
  final formatted = await _worker.call('formatMessage', {
    'text': text,
    if (tokensUsed != null) 'tokensUsed': tokensUsed,
    if (elapsedMs != null) 'elapsedMs': elapsedMs,
  });

  final textEl = line.querySelector('.msgText');
  if (textEl != null) textEl.textContent = text;
  final metaEl = line.querySelector('.msgMeta');
  if (metaEl != null) metaEl.textContent = formatted['meta'] as String;

  final log = web.document.getElementById('log')!;
  log.scrollTop = log.scrollHeight;
}

web.HTMLElement _byId(String id) => web.document.getElementById(id) as web.HTMLElement;

void _forEachElement(web.NodeList nodes, void Function(web.HTMLElement) fn) {
  for (var i = 0; i < nodes.length; i++) {
    fn(nodes.item(i) as web.HTMLElement);
  }
}

void _togglePanel(String panelId, List<String> others) {
  final panel = _byId(panelId);
  final wasHidden = panel.classList.contains('hidden');
  for (final other in others) {
    _byId(other).classList.add('hidden');
  }
  if (wasHidden) {
    panel.classList.remove('hidden');
  } else {
    panel.classList.add('hidden');
  }
}

void _wire() {
  final form = web.document.getElementById('form') as web.HTMLFormElement;
  final input = web.document.getElementById('input') as web.HTMLInputElement;

  void onSubmit(web.Event e) {
    e.preventDefault();
    final text = input.value.trim();
    if (text.isEmpty) return;
    input.value = '';
    unawaited(_appendMessage('user', text));
    unawaited(_sendToOllama(text));
  }

  form.addEventListener('submit', onSubmit.toJS);

  // Background Telegram traffic mirrors into the same log while the window
  // is open (see src-tauri/src/telegram.rs -- emits "telegram-event").
  tauri.listen('telegram-event', (payload) {
    final type = payload['type'] as String? ?? '';
    final text = payload['text'] as String? ?? '';
    if (type == 'incoming') {
      unawaited(_appendMessage('telegram', text));
    } else {
      final tokensUsed = (payload['tokensUsed'] as num?)?.toInt();
      final elapsedMs = (payload['elapsedMs'] as num?)?.toInt();
      unawaited(_appendMessage('assistant', text, tokensUsed: tokensUsed, elapsedMs: elapsedMs));
    }
  });

  const panels = [
    'queuePanel',
    'modelPanel',
    'telegramPanel',
    'promptPanel',
    'memoryPanel',
    'wikiPanel',
    'settingsPanel',
  ];

  void wireToggle(
    String btnId,
    String panelId, {
    void Function()? onOpen,
    void Function()? onClose,
  }) {
    final btn = web.document.getElementById(btnId) as web.HTMLButtonElement;
    void onClick(web.Event e) {
      final wasHidden = _byId(panelId).classList.contains('hidden');
      _togglePanel(panelId, panels.where((p) => p != panelId).toList());
      if (wasHidden) {
        onOpen?.call();
      } else {
        onClose?.call();
      }
    }

    btn.addEventListener('click', onClick.toJS);
  }

  wireToggle(
    'modelBtn',
    'modelPanel',
    onOpen: _startModelHealthPolling,
    onClose: _stopModelHealthPolling,
  );
  wireToggle('telegramBtn', 'telegramPanel', onOpen: _stopModelHealthPolling);
  wireToggle('promptBtn', 'promptPanel', onOpen: _stopModelHealthPolling);
  wireToggle('memoryBtn', 'memoryPanel', onOpen: () {
    _stopModelHealthPolling();
    unawaited(_loadMemoryPanel());
  });
  wireToggle('wikiBtn', 'wikiPanel', onOpen: () {
    _stopModelHealthPolling();
    unawaited(_loadWikiPanel());
  });
  wireToggle('settingsBtn', 'settingsPanel', onOpen: _stopModelHealthPolling);
  wireToggle('queueBtn', 'queuePanel', onOpen: _stopModelHealthPolling);

  // Queue state is broadcast continuously by the Rust side (both web-chat
  // and Telegram requests funnel through one FIFO there); keep listening
  // regardless of whether the panel is currently visible so the 📋 큐
  // button's count badge stays accurate.
  tauri.listen('queue-update', (payload) {
    final items = (payload['items'] as List?) ?? const [];
    _renderQueue(items);
  });

  final verifyBtn = web.document.getElementById('modelVerify') as web.HTMLButtonElement;
  void onVerify(web.Event e) => _verifyOllama();
  verifyBtn.addEventListener('click', onVerify.toJS);

  final modelSaveBtn = web.document.getElementById('modelSave') as web.HTMLButtonElement;
  void onModelSave(web.Event e) => _saveModel();
  modelSaveBtn.addEventListener('click', onModelSave.toJS);

  final telegramSaveBtn = web.document.getElementById('telegramSave') as web.HTMLButtonElement;
  void onTelegramSave(web.Event e) => _saveTelegram();
  telegramSaveBtn.addEventListener('click', onTelegramSave.toJS);

  final promptSaveBtn = web.document.getElementById('promptSave') as web.HTMLButtonElement;
  void onPromptSave(web.Event e) => _savePrompt();
  promptSaveBtn.addEventListener('click', onPromptSave.toJS);

  final settingsSaveBtn = web.document.getElementById('settingsSave') as web.HTMLButtonElement;
  void onSettingsSave(web.Event e) => _saveGeneralSettings();
  settingsSaveBtn.addEventListener('click', onSettingsSave.toJS);

  final contextSlider = web.document.getElementById('cfgContextSize') as web.HTMLInputElement;
  void onContextSliderInput(web.Event e) {
    web.document.getElementById('cfgContextSizeValue')!.textContent = contextSlider.value;
  }

  contextSlider.addEventListener('input', onContextSliderInput.toJS);

  final memorySaveBtn = web.document.getElementById('memorySave') as web.HTMLButtonElement;
  void onMemorySave(web.Event e) => unawaited(_saveMemoryEntry());
  memorySaveBtn.addEventListener('click', onMemorySave.toJS);

  final memoryCancelBtn = web.document.getElementById('memoryCancelEdit') as web.HTMLButtonElement;
  void onMemoryCancel(web.Event e) => _resetMemoryForm();
  memoryCancelBtn.addEventListener('click', onMemoryCancel.toJS);

  final wikiSaveBtn = web.document.getElementById('wikiSave') as web.HTMLButtonElement;
  void onWikiSave(web.Event e) => unawaited(_saveWikiEntry());
  wikiSaveBtn.addEventListener('click', onWikiSave.toJS);

  final wikiCancelBtn = web.document.getElementById('wikiCancelEdit') as web.HTMLButtonElement;
  void onWikiCancel(web.Event e) => _resetWikiForm();
  wikiCancelBtn.addEventListener('click', onWikiCancel.toJS);
}

void _renderQueue(List items) {
  final list = web.document.getElementById('queueList')!;
  if (items.isEmpty) {
    list.textContent = '대기 중인 요청 없음';
  } else {
    list.innerHTML = items.map((raw) {
      final item = raw as Map;
      final sourceLabel = item['source'] == 'telegram' ? '✈ 텔레그램' : '💬 웹';
      final isRunning = item['status'] == 'running';
      final statusLabel = isRunning ? '⏳ 생성 중' : '🕓 대기 중';
      final preview = _escapeHtml((item['preview'] as String?) ?? '');
      return '''
        <div class="queueItem ${isRunning ? 'running' : ''}">
          <span class="queueBadge">$sourceLabel</span>
          <span class="queueStatus">$statusLabel</span>
          <span class="queueText">$preview</span>
        </div>
      ''';
    }).join().toJS;
  }

  final btn = web.document.getElementById('queueBtn') as web.HTMLButtonElement;
  btn.textContent = items.isEmpty ? '📋 큐' : '📋 큐 (${items.length})';
}

// Ollama tag recommendations from SPEC.md, used as a fallback when no
// models are pulled locally yet (so the dropdown is never empty).
const _recommendedModels = [
  'gemma3:1b',
  'gemma3:4b',
  'llama3.2:1b',
  'phi3:mini',
  'exaone3.5:2.4b',
  'exaone3.5:7.8b',
  'moondream:1.8b',
];

Future<void> _populateModelSelect({String? preselect}) async {
  final installed = await tauri.invoke('ollama_models') as List? ?? [];
  final options = {...installed.cast<String>(), ..._recommendedModels}.toList()..sort();

  final select = web.document.getElementById('cfgModel') as web.HTMLSelectElement;
  select.innerHTML = options.map((m) => '<option value="$m">$m</option>').join().toJS;
  if (preselect != null && options.contains(preselect)) {
    select.value = preselect;
  }
}

Future<void> _loadModelPanel() async {
  final cfg = await tauri.invoke('load_config') as Map?;
  await _populateModelSelect(preselect: cfg?['ollama_model'] as String?);
  await _refreshModelHealth();
}

Timer? _healthPollTimer;

/// Live-tracks whether the model is actually loaded: Ollama unloads an idle
/// model from memory after a few minutes, and loads it on the very first
/// request, so "로드됨" is not a one-shot fact -- it changes on its own
/// while the panel is open. Polls every 3s only while the model panel is
/// visible (stopped on any other panel/navigation) so it doesn't hammer
/// Ollama in the background for no reason.
void _startModelHealthPolling() {
  _refreshModelHealth();
  _healthPollTimer?.cancel();
  _healthPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshModelHealth());
}

void _stopModelHealthPolling() {
  _healthPollTimer?.cancel();
  _healthPollTimer = null;
}

/// Auto-populated "동작 현황": Ollama reachability, whether the currently
/// selected model is actually installed, and how many models are pulled --
/// checked automatically whenever the panel is opened, no button press
/// needed (unlike the connection-check button, which also refreshes the
/// dropdown list itself).
Future<void> _refreshModelHealth() async {
  final health = web.document.getElementById('modelHealth')!;
  health.textContent = '현황 확인 중...';
  try {
    final running = await tauri.invoke('ollama_status') as bool? ?? false;
    final cfg = await tauri.invoke('load_config') as Map?;
    final selected = cfg?['ollama_model'] as String?;

    if (!running) {
      health.innerHTML = '''
        <div class="healthRow bad">🔴 Ollama 서버 연결 안 됨 (localhost:11434)</div>
      '''
          .toJS;
      return;
    }

    final installed = (await tauri.invoke('ollama_models') as List? ?? []).cast<String>();
    final loaded = (await tauri.invoke('ollama_running_models') as List? ?? []).cast<String>();
    final selectedInstalled = selected != null && installed.contains(selected);
    final selectedLoaded = selected != null && loaded.contains(selected);

    final rows = <String>[
      '<div class="healthRow good">🟢 Ollama 서버 연결됨</div>',
      if (selected == null)
        '<div class="healthRow warn">⚠ 선택된 모델 없음 -- 아래에서 골라 저장하세요</div>'
      else if (!selectedInstalled)
        '<div class="healthRow warn">⚠ 선택 모델: $selected (아직 설치 안 됨 -- ollama pull 필요)</div>'
      else if (selectedLoaded)
        '<div class="healthRow good">🟢 선택 모델: $selected (설치됨 · 지금 메모리에 로드되어 동작 중)</div>'
      else
        '<div class="healthRow">⚪ 선택 모델: $selected (설치됨 · 아직 로드 안 됨 -- 첫 요청 시 자동 로드)</div>',
      '<div class="healthRow">설치된 모델 ${installed.length}개 · 현재 로드된 모델 ${loaded.length}개</div>',
    ];
    health.innerHTML = rows.join().toJS;
  } catch (e) {
    health.textContent = '현황 확인 실패: $e';
  }
}

/// Hits the Ollama HTTP API (via Rust) to confirm it's actually reachable,
/// then refreshes the installed-model list -- the "관리성" verification
/// the settings panel was missing before (freetext model name had no way
/// to confirm it was real or spelled correctly).
Future<void> _verifyOllama() async {
  final status = web.document.getElementById('modelConnStatus')!;
  status.textContent = '확인 중...';
  try {
    final running = await tauri.invoke('ollama_status') as bool? ?? false;
    if (!running) {
      status.textContent = '❌ Ollama에 연결할 수 없음 (localhost:11434) -- 설치/실행 여부를 확인하세요';
      return;
    }
    final cfg = await tauri.invoke('load_config') as Map?;
    await _populateModelSelect(preselect: cfg?['ollama_model'] as String?);
    status.textContent = '✅ 연결됨 -- 목록 새로고침 완료';
  } catch (e) {
    status.textContent = '오류: $e';
  }
}

Future<void> _saveModel() async {
  final status = web.document.getElementById('modelStatus')!;
  status.textContent = '저장 중...';
  try {
    final model = (web.document.getElementById('cfgModel') as web.HTMLSelectElement).value;
    final current = await tauri.invoke('load_config') as Map? ?? {};
    await tauri.invoke('save_config', {
      'cfg': {
        'ollama_model': model,
        'telegram_bot_token': current['telegram_bot_token'],
        'telegram_chat_id': current['telegram_chat_id'],
        'telegram_enabled': current['telegram_enabled'] ?? false,
        'context_size': (current['context_size'] as num?)?.toInt() ?? 4096,
        'attachment_prompt': current['attachment_prompt'],
      },
    });
    status.textContent = '저장됨';
    await _refreshModelHealth();
  } catch (e) {
    status.textContent = '오류: $e';
  }
}

Future<void> _loadTelegramPanel() async {
  final cfg = await tauri.invoke('load_config') as Map?;
  if (cfg == null) return;
  (web.document.getElementById('cfgToken') as web.HTMLInputElement).value =
      (cfg['telegram_bot_token'] as String?) ?? '';
  (web.document.getElementById('cfgEnabled') as web.HTMLInputElement).checked =
      (cfg['telegram_enabled'] as bool?) ?? false;
}

Future<void> _saveTelegram() async {
  final status = web.document.getElementById('telegramStatus')!;
  status.textContent = '저장 중...';
  try {
    final token = (web.document.getElementById('cfgToken') as web.HTMLInputElement).value.trim();
    final enabled = (web.document.getElementById('cfgEnabled') as web.HTMLInputElement).checked;

    final current = await tauri.invoke('load_config') as Map? ?? {};
    await tauri.invoke('save_config', {
      'cfg': {
        'ollama_model': current['ollama_model'],
        'telegram_bot_token': token.isEmpty ? null : token,
        'telegram_chat_id': current['telegram_chat_id'],
        'telegram_enabled': enabled,
        'context_size': (current['context_size'] as num?)?.toInt() ?? 4096,
        'attachment_prompt': current['attachment_prompt'],
      },
    });

    if (enabled) {
      final started = await tauri.invoke('start_telegram');
      status.textContent = started == true
          ? '저장됨 · 텔레그램 브릿지 시작됨'
          : '저장됨 · 텔레그램 브릿지는 이미 실행 중이거나 재시작 시 적용됩니다';
    } else {
      status.textContent = '저장됨';
    }
  } catch (e) {
    status.textContent = '오류: $e';
  }
}

Future<void> _loadPromptPanel() async {
  final cfg = await tauri.invoke('load_config') as Map?;
  (web.document.getElementById('cfgAttachmentPrompt') as web.HTMLTextAreaElement).value =
      (cfg?['attachment_prompt'] as String?) ?? '';
}

Future<void> _savePrompt() async {
  final status = web.document.getElementById('promptStatus')!;
  status.textContent = '저장 중...';
  try {
    final attachmentPrompt =
        (web.document.getElementById('cfgAttachmentPrompt') as web.HTMLTextAreaElement).value.trim();

    final current = await tauri.invoke('load_config') as Map? ?? {};
    await tauri.invoke('save_config', {
      'cfg': {
        'ollama_model': current['ollama_model'],
        'telegram_bot_token': current['telegram_bot_token'],
        'telegram_chat_id': current['telegram_chat_id'],
        'telegram_enabled': current['telegram_enabled'] ?? false,
        'context_size': (current['context_size'] as num?)?.toInt() ?? 4096,
        'attachment_prompt': attachmentPrompt.isEmpty ? null : attachmentPrompt,
      },
    });
    status.textContent = '저장됨';
  } catch (e) {
    status.textContent = '오류: $e';
  }
}

Future<void> _loadSettingsPanel() async {
  final cfg = await tauri.invoke('load_config') as Map?;
  final contextSize = (cfg?['context_size'] as num?)?.toInt() ?? 4096;
  (web.document.getElementById('cfgContextSize') as web.HTMLInputElement).value =
      contextSize.toString();
  web.document.getElementById('cfgContextSizeValue')!.textContent = '$contextSize';
}

Future<void> _saveGeneralSettings() async {
  final status = web.document.getElementById('settingsStatus')!;
  status.textContent = '저장 중...';
  try {
    final contextSize =
        int.tryParse((web.document.getElementById('cfgContextSize') as web.HTMLInputElement).value) ?? 4096;
    final current = await tauri.invoke('load_config') as Map? ?? {};
    await tauri.invoke('save_config', {
      'cfg': {
        'ollama_model': current['ollama_model'],
        'telegram_bot_token': current['telegram_bot_token'],
        'telegram_chat_id': current['telegram_chat_id'],
        'telegram_enabled': current['telegram_enabled'] ?? false,
        'context_size': contextSize,
        'attachment_prompt': current['attachment_prompt'],
      },
    });
    status.textContent = '저장됨';
  } catch (e) {
    status.textContent = '오류: $e';
  }
}

// ---------------------------------------------------------------------
// 🧑 메모리 panel -- personal persistent memory (survives restarts, always
// injected into every request; see src-tauri/src/personal_memory.rs).
// ---------------------------------------------------------------------

String? _memoryEditingId;

Future<void> _loadMemoryPanel() async {
  final entries = await tauri.invoke('personal_memory_list') as List? ?? [];
  _renderMemoryList(entries);
}

void _renderMemoryList(List entries) {
  final list = web.document.getElementById('memoryList')!;
  if (entries.isEmpty) {
    list.textContent = '저장된 항목 없음';
    return;
  }
  final sorted = entries.cast<Map>().toList()
    ..sort((a, b) {
      final pinnedCmp = (b['pinned'] == true ? 1 : 0) - (a['pinned'] == true ? 1 : 0);
      if (pinnedCmp != 0) return pinnedCmp;
      return (b['updated_at'] as String? ?? '').compareTo(a['updated_at'] as String? ?? '');
    });

  list.innerHTML = sorted.map((e) {
    final id = e['id'] as String;
    final pin = e['pinned'] == true ? '📌 ' : '';
    final category = _escapeHtml(e['category'] as String? ?? '');
    final content = _escapeHtml(e['content'] as String? ?? '');
    return '''
      <div class="entryItem" data-id="$id">
        <div class="entryText">$pin[$category] $content</div>
        <div class="entryActions">
          <button type="button" class="entryEdit" data-id="$id">편집</button>
          <button type="button" class="entryDelete" data-id="$id">삭제</button>
        </div>
      </div>
    ''';
  }).join().toJS;

  _forEachElement(list.querySelectorAll('.entryEdit'), (btn) {
    final id = btn.getAttribute('data-id')!;
    final entry = sorted.firstWhere((e) => e['id'] == id);
    void onEdit(web.Event e) => _startEditMemory(entry);
    btn.addEventListener('click', onEdit.toJS);
  });
  _forEachElement(list.querySelectorAll('.entryDelete'), (btn) {
    final id = btn.getAttribute('data-id')!;
    void onDelete(web.Event e) => unawaited(_deleteMemoryEntry(id));
    btn.addEventListener('click', onDelete.toJS);
  });
}

void _startEditMemory(Map entry) {
  _memoryEditingId = entry['id'] as String;
  (web.document.getElementById('memoryContent') as web.HTMLTextAreaElement).value =
      entry['content'] as String? ?? '';
  (web.document.getElementById('memoryCategory') as web.HTMLSelectElement).value =
      entry['category'] as String? ?? 'fact';
  (web.document.getElementById('memoryPinned') as web.HTMLInputElement).checked = entry['pinned'] == true;
  (web.document.getElementById('memorySave') as web.HTMLButtonElement).textContent = '수정 저장';
  web.document.getElementById('memoryCancelEdit')!.classList.remove('hidden');
}

void _resetMemoryForm() {
  _memoryEditingId = null;
  (web.document.getElementById('memoryContent') as web.HTMLTextAreaElement).value = '';
  (web.document.getElementById('memoryCategory') as web.HTMLSelectElement).value = 'fact';
  (web.document.getElementById('memoryPinned') as web.HTMLInputElement).checked = false;
  (web.document.getElementById('memorySave') as web.HTMLButtonElement).textContent = '추가';
  web.document.getElementById('memoryCancelEdit')!.classList.add('hidden');
}

Future<void> _saveMemoryEntry() async {
  final status = web.document.getElementById('memoryStatus')!;
  status.textContent = '저장 중...';
  try {
    final content = (web.document.getElementById('memoryContent') as web.HTMLTextAreaElement).value.trim();
    final category = (web.document.getElementById('memoryCategory') as web.HTMLSelectElement).value;
    final pinned = (web.document.getElementById('memoryPinned') as web.HTMLInputElement).checked;
    if (content.isEmpty) {
      status.textContent = '내용을 입력하세요';
      return;
    }

    if (_memoryEditingId != null) {
      await tauri.invoke('personal_memory_update', {
        'id': _memoryEditingId,
        'content': content,
        'category': category,
        'pinned': pinned,
      });
    } else {
      await tauri.invoke('personal_memory_add', {
        'content': content,
        'category': category,
        'pinned': pinned,
      });
    }
    _resetMemoryForm();
    status.textContent = '저장됨';
    await _loadMemoryPanel();
  } catch (e) {
    status.textContent = '오류: $e';
  }
}

Future<void> _deleteMemoryEntry(String id) async {
  await tauri.invoke('personal_memory_delete', {'id': id});
  await _loadMemoryPanel();
}

// ---------------------------------------------------------------------
// 📚 위키 panel -- curated knowledge-base documents (survives restarts,
// never auto-injected; see src-tauri/src/wiki.rs). Only grows when the
// user explicitly saves something here.
// ---------------------------------------------------------------------

String? _wikiEditingId;

Future<void> _loadWikiPanel() async {
  final entries = await tauri.invoke('wiki_list') as List? ?? [];
  _renderWikiList(entries);
}

void _renderWikiList(List entries) {
  final list = web.document.getElementById('wikiList')!;
  if (entries.isEmpty) {
    list.textContent = '저장된 문서 없음';
    return;
  }
  final sorted = entries.cast<Map>().toList()
    ..sort((a, b) => (b['updated_at'] as String? ?? '').compareTo(a['updated_at'] as String? ?? ''));

  list.innerHTML = sorted.map((e) {
    final id = e['id'] as String;
    final title = _escapeHtml(e['title'] as String? ?? '');
    final summary = _escapeHtml(e['summary'] as String? ?? '');
    final tags = (e['tags'] as List?)?.cast<String>().join(', ') ?? '';
    return '''
      <div class="entryItem" data-id="$id">
        <div class="entryText"><strong>$title</strong> -- $summary${tags.isEmpty ? '' : ' [$tags]'}</div>
        <div class="entryActions">
          <button type="button" class="entryEdit" data-id="$id">편집</button>
          <button type="button" class="entryDelete" data-id="$id">삭제</button>
        </div>
      </div>
    ''';
  }).join().toJS;

  _forEachElement(list.querySelectorAll('.entryEdit'), (btn) {
    final id = btn.getAttribute('data-id')!;
    final entry = sorted.firstWhere((e) => e['id'] == id);
    void onEdit(web.Event e) => _startEditWiki(entry);
    btn.addEventListener('click', onEdit.toJS);
  });
  _forEachElement(list.querySelectorAll('.entryDelete'), (btn) {
    final id = btn.getAttribute('data-id')!;
    void onDelete(web.Event e) => unawaited(_deleteWikiEntry(id));
    btn.addEventListener('click', onDelete.toJS);
  });
}

void _startEditWiki(Map entry) {
  _wikiEditingId = entry['id'] as String;
  (web.document.getElementById('wikiTitle') as web.HTMLInputElement).value = entry['title'] as String? ?? '';
  (web.document.getElementById('wikiSummary') as web.HTMLInputElement).value =
      entry['summary'] as String? ?? '';
  (web.document.getElementById('wikiBody') as web.HTMLTextAreaElement).value = entry['body'] as String? ?? '';
  (web.document.getElementById('wikiTags') as web.HTMLInputElement).value =
      (entry['tags'] as List?)?.cast<String>().join(', ') ?? '';
  (web.document.getElementById('wikiSave') as web.HTMLButtonElement).textContent = '수정 저장';
  web.document.getElementById('wikiCancelEdit')!.classList.remove('hidden');
}

void _resetWikiForm() {
  _wikiEditingId = null;
  (web.document.getElementById('wikiTitle') as web.HTMLInputElement).value = '';
  (web.document.getElementById('wikiSummary') as web.HTMLInputElement).value = '';
  (web.document.getElementById('wikiBody') as web.HTMLTextAreaElement).value = '';
  (web.document.getElementById('wikiTags') as web.HTMLInputElement).value = '';
  (web.document.getElementById('wikiSave') as web.HTMLButtonElement).textContent = '저장';
  web.document.getElementById('wikiCancelEdit')!.classList.add('hidden');
}

Future<void> _saveWikiEntry() async {
  final status = web.document.getElementById('wikiStatus')!;
  status.textContent = '저장 중...';
  try {
    final title = (web.document.getElementById('wikiTitle') as web.HTMLInputElement).value.trim();
    final summary = (web.document.getElementById('wikiSummary') as web.HTMLInputElement).value.trim();
    final body = (web.document.getElementById('wikiBody') as web.HTMLTextAreaElement).value.trim();
    final tags = (web.document.getElementById('wikiTags') as web.HTMLInputElement)
        .value
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (title.isEmpty) {
      status.textContent = '제목을 입력하세요';
      return;
    }

    if (_wikiEditingId != null) {
      await tauri.invoke('wiki_update', {
        'id': _wikiEditingId,
        'title': title,
        'summary': summary,
        'body': body,
        'tags': tags,
      });
    } else {
      await tauri.invoke('wiki_save', {
        'title': title,
        'summary': summary,
        'body': body,
        'tags': tags,
        'relatedIds': <String>[],
      });
    }
    _resetWikiForm();
    status.textContent = '저장됨';
    await _loadWikiPanel();
  } catch (e) {
    status.textContent = '오류: $e';
  }
}

Future<void> _deleteWikiEntry(String id) async {
  await tauri.invoke('wiki_delete', {'id': id});
  await _loadWikiPanel();
}

Future<void> _sendToOllama(String text) async {
  final placeholder = await _appendMessage('assistant', '...');
  final cfg = await tauri.invoke('load_config') as Map?;

  try {
    // Ollama request preprocessing (default-model fallback, context-size
    // clamping) happens in the worker -- see worker/logic.dart.
    final request = await _worker.call('buildOllamaRequest', {
      'model': cfg?['ollama_model'],
      'prompt': text,
      'numCtx': (cfg?['context_size'] as num?)?.toInt() ?? 4096,
    });

    final result = await tauri.invoke('ollama_chat', request) as Map?;

    final reply = (result?['content'] as String?) ?? '(no response)';
    final tokensUsed = (result?['tokens_used'] as num?)?.toInt();
    final elapsedMs = (result?['elapsed_ms'] as num?)?.toInt();
    await _updateMessage(placeholder, reply, tokensUsed: tokensUsed, elapsedMs: elapsedMs);
  } catch (e) {
    await _updateMessage(placeholder, '오류: $e');
  }

  if (_healthPollTimer != null) unawaited(_refreshModelHealth());
}
