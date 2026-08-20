# Noriter AI - Changelog

See [BUGFIXES.md](BUGFIXES.md) for a detailed, symptom → root cause → fix log of every bug found during development.

## [0.1.6] - 2026-08-03

### Changed
- **One input path: the prompt.** The wiki panel's separate boxes (paste-source, company scope, ask-a-question) and its save form (title / summary / tags / body / company / period / "contains figures") are gone. You type — or attach a file — and the chairman decides whether it is a question for the wiki, material to file into it, or ordinary chat (`chairman::decide_intent`, design §2.4).

  Roughly half those fields existed because the agents that should fill them do not exist yet: Taxonomy assigns the company (§4.1.2), preprocessing parses the period, and O-22 still hasn't settled who marks a page as carrying figures. Asking the user instead was a shortcut taken while closing D-04/D-05 — it worked, but it left an unfinished mechanism sitting on the product surface, where "LLM wiki" and "type your own metadata" contradict each other in plain sight.

  Company scope now comes out of the sentence (`match_known_company`, §8.2.3) rather than a field that stayed set between questions.
- **File attachments in web chat** (📎), sharing the Telegram bridge's extraction rules via a new `attachment` module — images to the model as images, `.xlsx` through `calamine`, everything else as text, capped at 8000 chars with the truncation stated rather than silent.

### Fixed
- **Wiki answers had lost the conversation.** Routing a message to the wiki skipped `memory::build_messages` entirely, so "이 정보에 대한 날짜는?" reached the model with no idea what "이 정보" referred to — and the turn was never recorded, leaving a hole for later messages too. Wiki paths now carry the same remembered turns as ordinary chat, and the context budget subtracts what the history occupies so the two cannot overflow the window together (that overflow would truncate the tail silently — the D-04 failure one layer out). A regression introduced by this release's own entry-point merge: the wiki query used to be its own button, where standing outside the conversation made sense.
- `Cargo.toml`'s description no longer claims "offline AI assistant" — it is local-first, with on-demand OpenDART lookups (O-25).

### Removed
- `wiki_save`, `wiki_ingest`, `wiki_query` commands and `wiki::update`, along with the wiki list's 편집 button. Pages are created by routing a prompt and reviewed in the draft queue; a page that came out wrong is discarded there or deleted, not hand-patched. **Trade-off**: partial edits are no longer possible — a one-line mistake means regenerating the page. Recorded in the v0.1.6 design note as the first thing to revisit if it proves annoying.

### Note
`company`, `period` and `body_required` now have no writer until preprocessing and Taxonomy land — the scope filter (D-05a) and the context budget (D-04) are implemented but will not have values to act on until then. That is the cost of removing the stopgap rather than shipping it.

See `구성도/v0.1.6_적용/00_v0.1.6_설계서.md`.

## [0.1.5.2] - 2026-08-03

Versioning note: the design documents run to **v0.1.5.2** (D1 → D2 → D3 →
v0.1.5.1 → checklist v0.1.5.2), and the shipped binary is named after that
document revision -- `noriter-ai-0.1.5.2.exe`. Cargo and Tauri only accept
three-part semver, so the package version reads `0.1.5`.

### Added
- **Wiki Ingest/Query/Lint** (extends the 📚 위키 panel from 0.1.4): three LLM-driven operations inspired by the "LLM wiki" pattern (accumulate structured knowledge over time instead of re-deriving it per query, à la Karpathy's write-up).
  - **Ingest**: paste raw source text -> one extra Ollama call turns it into a structured page (title/summary/tags/body via a parsed `TITLE:`/`SUMMARY:`/`TAGS:`/`BODY:` response, not JSON -- more reliable with small local models) and saves it.
  - **Query**: ask a question -> answered using the wiki's contents as context, and the answer accumulates instead of vanishing into chat history. (Answers now land in a review queue rather than the wiki itself -- see the two-store split below.)
  - **Lint**: asks the model to review the title/summary/tag index for contradictions, orphaned pages, under-covered concepts, and follow-up questions -- a report, not a stored page.
  - `wiki/log.md`: append-only, grep-able activity log (`## [date] action | title`), written on every save/lint.

- **OpenDART integration** (`dart.rs`): downloads the corp-code directory once and caches it to `dart/corp_codes.json`, then resolves company names locally. Gives every company one stable key, so `삼성전자`, `삼성전자(주)` and `005930` stop being three different companies. API key lives in `config.json` and is entered in ⚙ 설정. This is the app's first outbound request -- it fetches one specific table on demand, so the "no crawling" rule still holds, but "offline" is now "offline after the first fetch".
- **🏢 company scope + 📝 검토 대기** in the 위키 panel, plus per-page 기업/회계 기간/재무 수치 여부 fields.

### Fixed
Design review of the v0.1.5 agent architecture surfaced eight defects in the existing wiki code (3 Critical, 5 High). All are now fixed; each shipped with a regression test reproducing the original failure (20 tests total). Every one of them was silent -- the app kept working and returned plausible answers while the result was wrong.

- **Queue re-entrancy deadlock**: a coordinating function that ran itself through the generation queue and then called a sub-agent would wait on a non-reentrant lock forever. `queue::call_llm` is now the only entry point, and `run_queued` is private -- so the deadlock is ruled out by the compiler rather than by remembering the rule.
- **Wiki wiped on schema change**: adding a field to `WikiEntry` made the whole index fail to parse, the loader silently started empty, and the next save overwrote the file. Now `#[serde(default)]` at the struct level (the same fix `AppConfig` got in 0.1.4, which had not been applied here).
- **Query answers self-contaminating the wiki**: generated answers were saved straight into the wiki and became evidence for the next answer. Split into two stores -- `draft.json` (never read back) and `index.json` (promoted) -- so the feedback path no longer exists rather than being filtered out. Promotion is an explicit step in 📝 검토 대기.
- **Context threshold discarded all bodies**: one `< 6000` check chose between the entire wiki and titles-only, so a single financial statement pushed every body out while the answer still looked fine. Replaced with ranked tiers and a budget derived from `num_ctx` (`preflight.rs`). Pages whose figures cannot survive summarising are dropped and **named in the answer** instead of being reduced to a number-free summary.
- **No company scope**: one company's figures could be cited in another's analysis -- and the verification agent would confirm them, since the number really was in the wiki. Reads are now scoped by `corp_code`, with company-agnostic concept pages still included; an unscoped answer says so.
- **ID collisions**: millisecond-precision ids collided in tight save loops, after which editing a page touched only the first and deleting it removed both. Now timestamp + atomic counter.
- **Non-atomic index writes**: a crash mid-save left a truncated file that the loader treated as an empty wiki. Now temp-file + rename.
- **Parser silently produced empty pages**: `BODY:` was honoured only as an exact standalone line, so a model writing `BODY: 내용` yielded a page with no body -- saved without complaint. Label matching now tolerates markdown, case and leading text; an empty body or title is an explicit failure, retried three times before being handed to `wiki/미결작업.md`. The `"제목 없음"` fallback is gone (titles are link anchors, so a shared placeholder collides unrelated pages), and same-title pages get a `제목(구분자)` suffix derived from company or period.

### Security
- **A Telegram bot token was committed in plain text** in `.vscode/settings.json` (since `0.0.5`) and reached the remote. The value has been cleared and the file untracked, but **the token in git history must be treated as compromised and revoked via BotFather** -- clearing it here does not un-publish it. `.noriter-ai/chat-history.json` was likewise tracked despite being listed in `.gitignore`; both are now untracked (ignoring a file has no effect while it is still tracked, which is how these persisted).

## [0.1.4] - 2026-07-16
### Added
- **Telegram photo/document attachments**: photos are downloaded and sent to Ollama as multimodal `images` (requires a vision-capable model); `.xlsx` documents are parsed into a plain-text table via `calamine`, everything else decoded as UTF-8 text -- both ported from the old Dart bridge's attachment handling.
- **📝 프롬프트 panel**: a dedicated button/panel to view and edit the "첨부파일 기본 프롬프트" (used when a Telegram photo/document arrives with no caption) -- previously buried inside the 텔레그램 panel.
- **Conversation working memory** (session-only, not persisted): last 3 turns replayed verbatim, turns 4-8 back compressed into a short summary (one extra Ollama call), anything older dropped. Applies separately to web chat and each Telegram chat. Attachment payloads are never carried into remembered turns -- only their plain text.
- **Cold-start / background tuning**: release profile now builds with `opt-level="s"`, LTO, and stripped symbols; process priority drops to idle while the window is hidden (tray) and restores on show.
- Added a Tauri `capabilities/default.json` -- was missing entirely, which silently blocked the `queue-update`/`telegram-event` frontend event listeners (custom commands worked regardless since they aren't gated by the same ACL).
- **🧑 메모리 panel -- personal persistent memory**: durable facts about the user (`<config dir>/noriter-ai/memory.json`), injected into every request. Grows manually (add/edit/delete/pin in the panel) or automatically (every 5th turn, a short extra Ollama call extracts one fact or returns `NONE`).
- **📚 위키 panel -- LLM wiki/encyclopedia**: user-curated documents (`<config dir>/noriter-ai/wiki/index.json`) with title/summary/body/tags. Manual-only (no auto-injection, no auto-creation) -- a "look things up" store, separate in purpose from the always-on personal memory.

### Fixed
- **Telegram reply to an attachment showed the file dump instead of the generated answer** -- the outgoing message echoed the *full prompt* (including the entire extracted attachment text) above the reply, and the combined string was truncated to Telegram's ~4096-char limit before ever reaching the actual generated answer. Now only a short caption/`[첨부파일]` preview is echoed, and the reply is truncated on its own separate budget. See BUGFIXES.md.
- `AppConfig` deserialization now has `#[serde(default)]` at the struct level -- without it, any field missing from an on-disk `config.json` (e.g. after adding a new field) silently discarded the *entire* saved config back to defaults, not just the missing field.

## [0.1.3] - 2026-07-16
Full rewrite onto **Tauri + Rust**, replacing the v0.1.2 single-EXE Dart server. Not yet packaged as an installer -- runs via `cargo tauri dev` from source. See [SPEC.md](SPEC.md#architecture-v013-tauri--rust) for the new architecture.

### Added
- **Rust backend**: Ollama HTTP client, always-on Telegram long-poll bridge (`teloxide`), system tray with close-to-hide, and config persistence -- all replacing the corresponding `dart_platform` modules, which used `dart:io` and can't compile to Wasm.
- **Dart Wasm frontend**: chat UI compiled with `dart compile wasm`, talking to the Rust backend purely through Tauri IPC (`window.__TAURI__`). No `dart:io` anywhere in `dart_ui/`.
- **Web Worker split**: message formatting (timestamp, token/time stats, HTML-escaping) and Ollama request preprocessing (default-model fallback, context-size clamping) run in a separately-compiled Wasm module (`worker.dart.wasm`) inside a Web Worker, off the main/UI thread. Communication is `postMessage` + JSON only.
- **🧠 모델 panel**: dropdown of installed + recommended Ollama models, a connection-check button that verifies Ollama is actually reachable and refreshes the installed list, and a live "동작 현황" section (server connected / model installed / model currently loaded into memory) that polls every 3s while the panel is open and refreshes immediately after any chat reply.
- **✈ 텔레그램 panel**: bot token + enable toggle, calling a `start_telegram` command that's safe to call repeatedly (guarded so the long-poll loop is never double-spawned). Starting only requires the token -- no model chosen yet is fine; the bridge replies with setup guidance in-chat instead of failing.
- **Telegram bridge feature parity (partial) with the old Dart bridge**: auto-binds to the first chat that messages the bot and persists the chat ID; ignores messages from any other chat once bound; ignores bot-authored messages; truncates outgoing replies to Telegram's ~4096-char limit; echoes the original prompt (`> {text}`) above the generated reply.
- **📋 큐 panel**: web chat and Telegram requests now funnel through one Rust-side FIFO (`queue::run_queued`) so they never call Ollama concurrently; the queue's live contents (waiting/running, source, preview) are broadcast as `queue-update` events and rendered with a count badge on the button itself.
- **Message timestamps + generation stats**: every message (web chat and mirrored Telegram traffic) gets a `YYYY-MM-DD HH:mm:ss` generation timestamp; assistant replies additionally show `N tokens · X.Xs` (Ollama's `eval_count` + wall-clock time measured in Rust).
- **⚙ 설정 panel**: context size, saved independently of the model/Telegram panels.

### Known gaps (deliberately deferred, see SPEC.md)
No chat history or Telegram conversation-context persistence, no Ollama response streaming, no Telegram photo/document attachments, config stored as plaintext JSON (not encrypted), no window chrome control (frameless/opacity/always-on-top), no installer packaging yet.

## [0.1.2] - 2026-07-12
### Added
- **Context size "Apply" button**: llama.cpp/Ollama allocate the KV cache at model-load time, so context size can't change on a running model without a reload -- the slider previously only took effect on the *next* Run. Now an Apply button next to it reloads the currently running model with the new size on click. Disabled whenever a request is running or queued (reloading mid-generation would cut off or error out the in-progress reply) or when no model is running yet.
- **Date shown in message timestamps**: each message's timestamp now shows just `HH:mm` for today's messages, or `MM/DD HH:mm` (`YYYY/MM/DD HH:mm` across a year boundary) for anything older -- previously every timestamp was time-only, ambiguous once the history spans multiple days. Verified live against real multi-day history (e.g. `07/12 21:28` for an older message).
- **Token/time display per reply**: each assistant message now shows "N tokens · X.Xs" underneath it -- total tokens used (from the API's `usage.total_tokens`, summed across any tool-calling iterations) and wall-clock generation time for the whole turn. Persisted to history so it survives a reload. Verified live: a real reply rendered "1930 tokens · 14.9s".
- **Visual request queue**: generation requests from the web chat and Telegram now share a single serialized queue (they can't run the agent concurrently anyway) and their state is broadcast to the UI. A "📋 Request Queue" panel appears above the chat whenever one or more requests are waiting/running, showing each entry's source (💬 web / ✈️ telegram) and a text preview -- previously concurrent requests could silently interleave against the same agent state with no visibility into what was pending.
- **Excel (.xlsx) attachment**: the 📎 button now also accepts spreadsheets (up to 8MB). Parsed client-uploaded bytes are decoded with the `excel` package into a plain-text table (one section per sheet, pipe-separated cell values) and handled exactly like a text file attachment from there (same truncation/history-placeholder policy). PDF support was considered but deferred -- the viable Dart libraries require bundling native DLLs alongside the EXE, which breaks the single-file distribution model; revisit later if that tradeoff becomes acceptable.
- **Telegram image analysis**: sending a photo to the Telegram bot (with or without a caption) now downloads it via Telegram's `getFile` API, sends it to the agent as a multimodal message (same code path as the web chat's image attachment), and replies with the analysis. Checks the active model's vision capability first and gives a clear "switch to a vision-capable model" reply instead of erroring if the loaded model is text-only.
- **EXAONE-4.5-33B (image-capable)** added to the recommended list for users who specifically want vision analysis from an EXAONE model. LG has no smaller vision-capable EXAONE -- the only image-capable release is 33B. Pulled via `hf.co/mradermacher/EXAONE-4.5-33B-i1-GGUF:Q2_K` (~10GB, the smallest available quant). Labeled with an explicit ⚠ warning: on a 6GB-VRAM GPU it mostly runs on system RAM and will be noticeably slow. `gemma3:4b` remains the fast/comfortable vision option for anyone not specifically tied to EXAONE.
- **Moondream-1.8B** added as a properly hardware-appropriate vision option (`moondream:1.8b`, ~1.7GB) -- fits a 6GB-VRAM GPU with plenty of headroom and runs fast, for anyone who wants quick image description/analysis without the EXAONE-4.5-33B slowdown.
- **Gemma-4-12B** (`gemma4:12b`) added -- Gemma 4 (newer than Gemma 3), image-capable, 256K context. Its ~7.6GB download is barely larger than the smallest edge variant (`gemma4:e2b`, ~7.2GB) but doubles the context window and has more real parameters, making it a better pick than `gemma3:4b` at essentially the same resource cost -- still slightly over the 6GB VRAM budget so some layers spill to system RAM, but far more comfortable than the EXAONE-4.5-33B option.

### Fixed
- Attaching an image while a non-vision model was loaded showed a raw JSON API error ("Multimodal data provided, but model does not support multimodal requests"). Now checked upfront via Ollama's `/api/show` capabilities and shown as a clear message telling you to switch to a vision-capable model (e.g. `gemma3:4b`) instead.
- **Telegram file attachments were silently dropped.** Telegram sends non-photo attachments (e.g. .xlsx) as a `document` field, which the bridge never checked -- only the caption text reached the model, sometimes producing a confusing empty-response error. Documents are now downloaded and embedded the same way the web chat handles file attachments (Excel parsed via `excelBytesToText()`, everything else as UTF-8 text). Also fixed a stale error message that referenced "LM Studio" from before the Ollama backend swap.

## [0.1.1] - 2026-07-12
### Added
- **Image attachment for vision-capable models**: the 📎 attach button now also accepts images (png/jpg/jpeg/gif/webp, up to 4MB). Images are read client-side as a base64 data URL and sent as a multimodal chat message (not inlined as text), so a vision-capable model (e.g. `gemma3:4b`, marked "image-capable" in the recommended list) can actually look at them. Like file attachments, only a short placeholder is kept in history -- the image data itself is never persisted or resent on later turns.
- **Recommended model lineup**: added `exaone3.5:2.4b` and `exaone3.5:7.8b` (LG AI Research), the latter sized to fit comfortably within a 6GB-VRAM GPU (e.g. GTX 1660) alongside 32GB system RAM.

### Verified live
- `exaone3.5:7.8b` pulled and ran successfully end-to-end through the new Ollama backend on real hardware, confirming the v0.1.0 backend swap works outside the sandbox it was built in.
- Sent a plain-text chat message through the running engine after the multimodal message-type refactor and got a correct, coherent reply back, confirming ordinary text chat wasn't regressed.

## [0.1.0] - 2026-07-11
### Changed
- **Embedded engine backend switched from llama.cpp to Ollama.** Priority was frictionless local model use ("no manual GGUF hunting, one click to chat"); Ollama manages model pulling/quantization internally and is addressed by tag (`gemma3:4b`) instead of a downloaded file path.
  - `OllamaEngineManager` replaces `LlamaEngineManager` -- detects an Ollama install, starts `ollama serve` if needed, pulls/lists models via its HTTP API, and "runs" a model by warming it into memory (previously a `llama-server.exe` subprocess per model).
  - Embedded endpoint moved from `http://127.0.0.1:8080/v1` to Ollama's OpenAI-compatible `http://127.0.0.1:11434/v1`.
  - Recommended model list now references Ollama tags (`gemma3:1b`, `llama3.2:1b`, `gemma3:4b`, `phi3:mini`) instead of Hugging Face GGUF URLs; `model_download_service.dart` and `llama_engine_manager.dart` removed as dead code.
  - The app does not silently install Ollama on your behalf -- if it's missing, the Engine panel's button opens the official download page instead.
  - `.noriter-ai/last-engine.json` now stores an Ollama tag rather than a file path.

## [0.0.9] - 2026-07-11
### Added
- **Local file attachment in chat**: new paperclip button next to the chat input lets you attach a local text-based file (txt, md, json, csv, code, log, etc., up to 500 KB); its content is read client-side and embedded in the next message sent to the agent, so it can review/summarize/edit it like any other conversation turn
- **Remember last engine + confirm-to-relaunch**: the app now remembers the last model + context size that was successfully started (`.noriter-ai/last-engine.json`). On the next launch, if that model file still exists and no engine is running yet, a confirmation dialog offers to start it automatically
- **Per-bubble timestamps**: every chat message now shows an `HH:mm` time so the conversation reads like a real chat thread
- **`WS_DEBUG=1`**: optional environment variable that logs every WebSocket event and agent turn to stdout, for tracing activity that's collapsed or otherwise hidden in the UI
- **Redesigned Engine panel**: status message (1 line) and a model-select dropdown with a Run button to its right (1 line) replace the old scattered action-button layout; the button's label/action switches contextually (Download Engine / Run / Stop)
- **Recommended model lineup reworked around Gemma 3**: replaced the outdated Gemma-2-2B entry with Gemma-3-1B-Instruct and Gemma-3-4B-Instruct (a generation newer, noticeably better at the same size), alongside Llama-3.2-1B and Phi-3-mini-4k

### Fixed
- Agent replies were being cut off mid-sentence (`max_tokens` was never set on the `/chat/completions` request, so llama-server fell back to a small default completion length)
- Attaching a file permanently bloated conversation context for all later turns (full attachment body was persisted to history instead of a placeholder)
- Attached-file requests got a generic "I apologize... still learning to interact with files" reply because the model tried to `readFile` a file that only existed inline in the prompt, not in the workspace
- Malformed tool-call JSON (JS-style string concatenation) killed the whole agent turn instead of letting the model self-correct
- Telegram bridge always replied "Done." instead of the real answer (fire-and-forget callback race)
- Telegram messages were read but never replied to (misconfigured `chatId`; bridge now auto-binds to the first sender)

See [BUGFIXES.md](BUGFIXES.md) for details on each of these.

## [0.0.8] - 2026-07-11
### Added
- **Telegram bot bridge** (`telegram_bridge.dart`, `telegram_config_service.dart`): long-polls the Telegram Bot API and routes messages through the same `LocalAgent`/history used by the web chat, so both surfaces stay in sync
- **Telegram panel in frontend**: new `[Telegram]` header button opens a panel to set bot token / chat ID and enable/disable the bridge; settings persist to `.noriter-ai/telegram-config.json` (gitignored, never echoed back in full)
- **Auto-bind chat ID**: if no chat ID is configured, the bridge binds to whichever chat sends the first message and persists it automatically, so a manual chat-ID lookup is no longer required
- **Context size slider**: Engine panel now has a 512–32768 token slider controlling llama-server's `-c` context size (previously hardcoded to 4096)

### Fixed
- **Telegram messages read but never replied to**: the bridge was consuming `getUpdates` (advancing the offset) for every incoming message but silently dropping ones whose `chat.id` didn't match the configured `chatId`. Root cause in practice: the shipped local config had `chatId` set to the bot's own numeric ID (the token prefix) instead of the human user's chat ID. Fixed by auto-binding to the first sender when `chatId` is unset, and by surfacing a clear status message ("Ignored message from chat X — bridge is bound to chat Y") on any future mismatch instead of failing silently
- **`exceed_context_size_error` (HTTP 400)**: agent now trims the oldest context messages and retries instead of surfacing a raw JSON error to the user

## [0.0.7] - 2026-07-09
### Fixed
- Fixed encoding corruption in `assets.dart` — all broken Korean characters in HTML/JS UI replaced with English equivalents
- Fixed broken Korean strings in `server.dart` status messages (engine status, model download progress, error messages)

### Added
- **Engine guard in `server.dart`**: in embedded mode, chat is blocked when engine is not running — returns `engineNotReady` message instead of crashing with SocketException
- **`engineStatus` WebSocket handler in frontend**: UI now receives and reacts to engine state changes
- **Engine-not-ready banner**: orange warning bar shown at top of chat when engine is not started; clicking it opens the Engine panel automatically
- **Input placeholder guidance**: textarea shows "Start the engine first → click [Engine]" when engine is offline
- **`updateEngineActions` / `updateLocalModels` / `updateRecommendedModels`**: Engine panel now dynamically renders action buttons and model lists from server data
- **Run button per model**: each downloaded model shows a Run button in the Engine panel
- **Stop Engine button**: shown when engine is running
- CSS: `.action-btn`, `.run-btn`, `.danger-btn` button styles

---

## [0.0.6] - 2026-07-09
### Added
- **Dart platform rewrite** (`dart_platform/`) — full standalone GUI app replacing the VS Code extension runtime
- `LlamaEngineManager` — downloads `llama-server.exe` from GitHub releases, manages its lifecycle (start/stop), stores engine in `%APPDATA%\noriter-ai\engine\`
- `ModelDownloadService` — downloads GGUF model files from Hugging Face with progress reporting, stores in `%APPDATA%\noriter-ai\models\`
- Built-in Engine Panel UI: download engine, download recommended models, start/stop engine — all from the browser UI
- `EngineState` / `EngineMode` — tracks embedded vs external LLM mode
- Auto-detect embedded mode: if `NORITER_MODEL_ENDPOINT` env var is unset, the app starts in embedded mode (llama.cpp) instead of requiring LM Studio
- Recommended GGUF models: Qwen2.5-0.5B, Llama-3.2-1B, Phi-3-mini, Gemma-2-2B
- WebSocket messages: `downloadEngine`, `startEngine`, `downloadModel`, `getEngineStatus`, `listLocalModels`
- `/engine` chat command shows current engine status

### Changed
- Single `noriter-ai-0.0.6.exe` (7.7 MB) — no installer, no code signing required, runs on Windows without admin rights

---

## [0.0.5] - prior
### Added
- VS Code extension (`src/`) with ReAct agent loop
- 9 built-in tools: readFile, writeFile, listFiles, searchFiles, runCommand, fetchUrl, readMemory, writeMemory, webSearch
- Telegram bridge for remote interaction
- Memory file (`agent-memory.md`) and Goal file (`agent-goal.md`) persistence
- LM Studio integration (external OpenAI-compatible endpoint)
- `/models` command in chat and Telegram
- `project-plan-log.md` cumulative work log

---

## [0.0.4 and earlier]
- VS Code extension prototype (TypeScript + OpenAI SDK)
- Basic chat UI in VS Code sidebar (webview)
- LM Studio as the only supported LLM backend
