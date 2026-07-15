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

  const panels = ['queuePanel', 'modelPanel', 'telegramPanel', 'settingsPanel'];

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

  final settingsSaveBtn = web.document.getElementById('settingsSave') as web.HTMLButtonElement;
  void onSettingsSave(web.Event e) => _saveGeneralSettings();
  settingsSaveBtn.addEventListener('click', onSettingsSave.toJS);

  final contextSlider = web.document.getElementById('cfgContextSize') as web.HTMLInputElement;
  void onContextSliderInput(web.Event e) {
    web.document.getElementById('cfgContextSizeValue')!.textContent = contextSlider.value;
  }

  contextSlider.addEventListener('input', onContextSliderInput.toJS);
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
      },
    });
    status.textContent = '저장됨';
  } catch (e) {
    status.textContent = '오류: $e';
  }
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
