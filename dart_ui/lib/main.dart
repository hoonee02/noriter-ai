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

        <div class="wikiTool">
          <p class="panelDesc">
            📝 검토 대기 -- 질문 답변은 여기 쌓이고, <strong>위키에 반영하기 전까지는 다음
            질문의 근거로 쓰이지 않습니다.</strong> 내용을 확인한 뒤 반영하세요.
          </p>
          <div id="wikiDraftList" class="entryList"></div>
        </div>

        <div class="wikiTool">
          <label>📥 자료 통합 (Ingest) -- 원문을 붙여넣으면 모델이 제목/요약/태그/본문을 알아서 정리해 저장합니다
            <textarea id="wikiIngestText" rows="4" placeholder="여기에 원문을 붙여넣으세요"></textarea>
          </label>
          <div class="panelActions">
            <button id="wikiIngestBtn" type="button">통합 실행</button>
            <span id="wikiIngestStatus"></span>
          </div>
        </div>

        <div class="wikiTool">
          <label>🏢 기업 스코프 -- 비워두면 위키 전체가 대상입니다. 지정하면 그 기업 문서 + 기업 무관 문서만 봅니다
            <input id="wikiScope" type="text" placeholder="예: 삼성전자 (비워두면 전체)" />
          </label>
          <div class="panelActions">
            <span id="wikiScopeStatus"></span>
          </div>
        </div>

        <div class="wikiTool">
          <label>❓ 위키에 질문 (Query) -- 답변은 위 "검토 대기"에 쌓입니다 (확인 후 반영)
            <input id="wikiQueryText" type="text" placeholder="예: 저번에 정리한 엑셀 자료 요약해줘" />
          </label>
          <div class="panelActions">
            <button id="wikiQueryBtn" type="button">질문하기</button>
            <span id="wikiQueryStatus"></span>
          </div>
          <div id="wikiQueryAnswer" class="wikiAnswer"></div>
        </div>

        <div class="wikiTool">
          <div class="panelActions">
            <button id="wikiLintBtn" type="button">🔍 위키 점검 (Lint)</button>
            <span id="wikiLintStatus"></span>
          </div>
          <div id="wikiLintReport" class="wikiAnswer"></div>
        </div>

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
        <label>기업 (선택) -- DART 기업 목록에서 찾은 경우에만 기록됩니다
          <input id="wikiCompany" type="text" placeholder="예: 삼성전자" />
        </label>
        <label>회계 기간 (선택)
          <input id="wikiPeriod" type="text" placeholder="예: 2025-FY" />
        </label>
        <label class="checkbox">
          <input id="wikiBodyRequired" type="checkbox" />
          본문에 재무 수치가 있음 -- 컨텍스트가 모자라도 요약으로 대체하지 않고, 대신 제외 사실을 답변에 밝힙니다
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

        <label>OpenDART API 키 -- 기업 고유번호 조회에 씁니다. 없으면 기업 스코프 기능이 꺼진 채 동작합니다
          <input id="cfgDartKey" type="text" placeholder="OpenDART에서 발급받은 키" />
        </label>
        <div class="panelActions">
          <button id="dartKeySave" type="button">키 저장</button>
          <button id="dartRefresh" type="button">기업 목록 내려받기</button>
          <span id="dartStatus"></span>
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

  final dartKeySaveBtn = web.document.getElementById('dartKeySave') as web.HTMLButtonElement;
  void onDartKeySave(web.Event e) => unawaited(_saveDartKey());
  dartKeySaveBtn.addEventListener('click', onDartKeySave.toJS);

  final dartRefreshBtn = web.document.getElementById('dartRefresh') as web.HTMLButtonElement;
  void onDartRefresh(web.Event e) => unawaited(_refreshDartCorpCodes());
  dartRefreshBtn.addEventListener('click', onDartRefresh.toJS);

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

  final wikiIngestBtn = web.document.getElementById('wikiIngestBtn') as web.HTMLButtonElement;
  void onWikiIngest(web.Event e) => unawaited(_runWikiIngest());
  wikiIngestBtn.addEventListener('click', onWikiIngest.toJS);

  final wikiQueryBtn = web.document.getElementById('wikiQueryBtn') as web.HTMLButtonElement;
  void onWikiQuery(web.Event e) => unawaited(_runWikiQuery());
  wikiQueryBtn.addEventListener('click', onWikiQuery.toJS);

  final wikiLintBtn = web.document.getElementById('wikiLintBtn') as web.HTMLButtonElement;
  void onWikiLint(web.Event e) => unawaited(_runWikiLint());
  wikiLintBtn.addEventListener('click', onWikiLint.toJS);
}

Future<Map<String, dynamic>> _currentModelAndCtx() async {
  final cfg = await tauri.invoke('load_config') as Map?;
  return {
    'model': (cfg?['ollama_model'] as String?) ?? 'gemma3:4b',
    'numCtx': (cfg?['context_size'] as num?)?.toInt() ?? 4096,
  };
}

Future<void> _runWikiIngest() async {
  final status = web.document.getElementById('wikiIngestStatus')!;
  final textarea = web.document.getElementById('wikiIngestText') as web.HTMLTextAreaElement;
  final sourceText = textarea.value.trim();
  if (sourceText.isEmpty) {
    status.textContent = '통합할 자료를 입력하세요';
    return;
  }
  status.textContent = '통합 중... (형식이 어긋나면 최대 3회까지 다시 시도합니다)';
  try {
    final mc = await _currentModelAndCtx();
    await tauri.invoke('wiki_ingest', {
      'model': mc['model'],
      'numCtx': mc['numCtx'],
      'sourceText': sourceText,
      'sourceLabel': '수동 입력',
    });
    textarea.value = '';
    status.textContent = '통합 완료 -- 새 문서가 아래 목록에 추가됨';
    await _loadWikiPanel();
  } catch (e) {
    status.textContent = '오류: $e';
  }
}

Future<void> _runWikiQuery() async {
  final status = web.document.getElementById('wikiQueryStatus')!;
  final answerBox = web.document.getElementById('wikiQueryAnswer')!;
  final input = web.document.getElementById('wikiQueryText') as web.HTMLInputElement;
  final question = input.value.trim();
  if (question.isEmpty) {
    status.textContent = '질문을 입력하세요';
    return;
  }
  status.textContent = '검색 중...';
  answerBox.textContent = '';
  try {
    final mc = await _currentModelAndCtx();
    final answer = await tauri.invoke('wiki_query', {
      'model': mc['model'],
      'numCtx': mc['numCtx'],
      'question': question,
      'scope': await _resolveWikiScope(),
    }) as String?;
    answerBox.textContent = answer ?? '(응답 없음)';
    status.textContent = '완료 -- 답변이 검토 대기에 추가됨';
    await _loadWikiPanel();
  } catch (e) {
    status.textContent = '오류: $e';
  }
}

Future<void> _runWikiLint() async {
  final status = web.document.getElementById('wikiLintStatus')!;
  final reportBox = web.document.getElementById('wikiLintReport')!;
  status.textContent = '점검 중...';
  reportBox.textContent = '';
  try {
    final mc = await _currentModelAndCtx();
    final report = await tauri.invoke('wiki_lint', {
      'model': mc['model'],
      'numCtx': mc['numCtx'],
      'scope': await _resolveWikiScope(),
    }) as String?;
    reportBox.textContent = report ?? '(결과 없음)';
    status.textContent = '완료';
  } catch (e) {
    status.textContent = '오류: $e';
  }
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

/// Loads the stored config, applies [changes] on top, and saves it back, so
/// each panel names only the fields it owns.
///
/// Every panel used to spell out all fields on save, which meant adding one
/// field required touching all of them -- miss a spot and saving from that
/// panel silently wiped whatever the new field held.
Future<void> _patchConfig(Map<String, dynamic> changes) async {
  final cfg = Map<String, dynamic>.from(await tauri.invoke('load_config') as Map? ?? {});
  cfg['context_size'] = (cfg['context_size'] as num?)?.toInt() ?? 4096;
  cfg['telegram_enabled'] = cfg['telegram_enabled'] ?? false;
  cfg.addAll(changes);
  await tauri.invoke('save_config', {'cfg': cfg});
}

Future<void> _saveModel() async {
  final status = web.document.getElementById('modelStatus')!;
  status.textContent = '저장 중...';
  try {
    final model = (web.document.getElementById('cfgModel') as web.HTMLSelectElement).value;
    await _patchConfig({'ollama_model': model});
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

    await _patchConfig({
      'telegram_bot_token': token.isEmpty ? null : token,
      'telegram_enabled': enabled,
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

    await _patchConfig({'attachment_prompt': attachmentPrompt.isEmpty ? null : attachmentPrompt});
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
  (web.document.getElementById('cfgDartKey') as web.HTMLInputElement).value =
      (cfg?['opendart_api_key'] as String?) ?? '';
  await _refreshDartStatus();
}

Future<void> _saveGeneralSettings() async {
  final status = web.document.getElementById('settingsStatus')!;
  status.textContent = '저장 중...';
  try {
    final contextSize =
        int.tryParse((web.document.getElementById('cfgContextSize') as web.HTMLInputElement).value) ?? 4096;
    await _patchConfig({'context_size': contextSize});
    status.textContent = '저장됨';
  } catch (e) {
    status.textContent = '오류: $e';
  }
}

// OpenDART: the corp-code directory gives every company one stable key, so
// pages about the same firm stop scattering across spelling variants (D-05c).

Future<void> _refreshDartStatus() async {
  final count = await tauri.invoke('dart_corp_count') as num? ?? 0;
  web.document.getElementById('dartStatus')!.textContent =
      count == 0 ? '기업 목록 없음 -- 내려받기 필요' : '기업 $count곳 보관 중';
}

Future<void> _saveDartKey() async {
  final status = web.document.getElementById('dartStatus')!;
  status.textContent = '저장 중...';
  try {
    final key = (web.document.getElementById('cfgDartKey') as web.HTMLInputElement).value.trim();
    await _patchConfig({'opendart_api_key': key.isEmpty ? null : key});
    status.textContent = '키 저장됨';
  } catch (e) {
    status.textContent = '오류: $e';
  }
}

Future<void> _refreshDartCorpCodes() async {
  final status = web.document.getElementById('dartStatus')!;
  status.textContent = '내려받는 중... (약 10만 곳, 시간이 걸립니다)';
  try {
    final count = await tauri.invoke('dart_refresh_corp_codes') as num?;
    status.textContent = '완료 -- 기업 $count곳 보관';
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

/// Resolves the scope box to a `corp_code`, reporting what it found.
///
/// D-05c: the backend filters on `corp_code`, never on the typed name --
/// `삼성전자` and `삼성전자(주)` have to land on one scope or the filter
/// hides pages while looking like it works. An unresolved name falls back to
/// whole-wiki rather than an empty result, and says so.
Future<String?> _resolveWikiScope() async {
  final status = web.document.getElementById('wikiScopeStatus')!;
  final name = (web.document.getElementById('wikiScope') as web.HTMLInputElement).value.trim();
  if (name.isEmpty) {
    status.textContent = '';
    return null;
  }
  final hit = await tauri.invoke('dart_lookup_company', {'name': name}) as Map?;
  if (hit == null) {
    status.textContent = '"$name" -- DART 목록에 없어 전체를 대상으로 합니다';
    return null;
  }
  status.textContent = '${hit['display_name']} (${hit['corp_code']}) 범위';
  return hit['corp_code'] as String?;
}

Future<void> _loadWikiPanel() async {
  final entries = await tauri.invoke('wiki_list') as List? ?? [];
  _renderWikiList(entries);
  final drafts = await tauri.invoke('wiki_draft_list') as List? ?? [];
  _renderWikiDraftList(drafts);
}

// Unpromoted query answers (wiki/draft.json). Deliberately a separate list
// from the wiki proper: these are model output that nothing has checked yet,
// and until someone promotes one it is never fed back as context (D-03).
void _renderWikiDraftList(List entries) {
  final list = web.document.getElementById('wikiDraftList')!;
  if (entries.isEmpty) {
    list.textContent = '검토 대기 중인 답변 없음';
    return;
  }
  final sorted = entries.cast<Map>().toList()
    ..sort((a, b) => (b['created_at'] as String? ?? '').compareTo(a['created_at'] as String? ?? ''));

  list.innerHTML = sorted.map((e) {
    final id = e['id'] as String;
    final title = _escapeHtml(e['canonical_title'] as String? ?? e['title'] as String? ?? '');
    final summary = _escapeHtml(e['summary'] as String? ?? '');
    return '''
      <div class="entryItem" data-id="$id">
        <div class="entryText"><strong>$title</strong> -- $summary</div>
        <div class="entryActions">
          <button type="button" class="draftPromote" data-id="$id">위키에 반영</button>
          <button type="button" class="draftDiscard" data-id="$id">버리기</button>
        </div>
      </div>
    ''';
  }).join().toJS;

  _forEachElement(list.querySelectorAll('.draftPromote'), (btn) {
    final id = btn.getAttribute('data-id')!;
    void onPromote(web.Event e) => unawaited(_promoteWikiDraft(id));
    btn.addEventListener('click', onPromote.toJS);
  });
  _forEachElement(list.querySelectorAll('.draftDiscard'), (btn) {
    final id = btn.getAttribute('data-id')!;
    void onDiscard(web.Event e) => unawaited(_discardWikiDraft(id));
    btn.addEventListener('click', onDiscard.toJS);
  });
}

Future<void> _promoteWikiDraft(String id) async {
  final status = web.document.getElementById('wikiStatus')!;
  try {
    await tauri.invoke('wiki_promote', {'id': id});
    status.textContent = '위키에 반영됨';
    await _loadWikiPanel();
  } catch (e) {
    status.textContent = '오류: $e';
  }
}

Future<void> _discardWikiDraft(String id) async {
  await tauri.invoke('wiki_discard_draft', {'id': id});
  await _loadWikiPanel();
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
    // canonical_title carries the disambiguating suffix when another page
    // shares this title (D-08 ④); `title` stays the bare editable form.
    final title = _escapeHtml(e['canonical_title'] as String? ?? e['title'] as String? ?? '');
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
  (web.document.getElementById('wikiCompany') as web.HTMLInputElement).value =
      ((entry['company'] as Map?)?['display_name'] as String?) ?? '';
  (web.document.getElementById('wikiPeriod') as web.HTMLInputElement).value =
      (entry['period'] as String?) ?? '';
  (web.document.getElementById('wikiBodyRequired') as web.HTMLInputElement).checked =
      (entry['body_required'] as bool?) ?? false;
  (web.document.getElementById('wikiSave') as web.HTMLButtonElement).textContent = '수정 저장';
  web.document.getElementById('wikiCancelEdit')!.classList.remove('hidden');
}

void _resetWikiForm() {
  _wikiEditingId = null;
  (web.document.getElementById('wikiTitle') as web.HTMLInputElement).value = '';
  (web.document.getElementById('wikiSummary') as web.HTMLInputElement).value = '';
  (web.document.getElementById('wikiBody') as web.HTMLTextAreaElement).value = '';
  (web.document.getElementById('wikiTags') as web.HTMLInputElement).value = '';
  (web.document.getElementById('wikiCompany') as web.HTMLInputElement).value = '';
  (web.document.getElementById('wikiPeriod') as web.HTMLInputElement).value = '';
  (web.document.getElementById('wikiBodyRequired') as web.HTMLInputElement).checked = false;
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
      _resetWikiForm();
      status.textContent = '저장됨';
      await _loadWikiPanel();
      return;
    }

    final company =
        (web.document.getElementById('wikiCompany') as web.HTMLInputElement).value.trim();
    final period = (web.document.getElementById('wikiPeriod') as web.HTMLInputElement).value.trim();
    final saved = await tauri.invoke('wiki_save', {
      'title': title,
      'summary': summary,
      'body': body,
      'tags': tags,
      'company': company.isEmpty ? null : company,
      'period': period.isEmpty ? null : period,
      'bodyRequired':
          (web.document.getElementById('wikiBodyRequired') as web.HTMLInputElement).checked,
    }) as Map?;

    _resetWikiForm();
    // A company the DART directory doesn't know is stored as no scope at all
    // rather than as typed text (D-05c). Saying so matters: otherwise the
    // page looks filed under that company and quietly never appears in its
    // scope.
    final resolved = saved?['company'] as Map?;
    status.textContent = company.isNotEmpty && resolved == null
        ? '저장됨 -- 다만 "$company"를 DART 목록에서 찾지 못해 기업 없이 저장했습니다'
        : '저장됨';
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
