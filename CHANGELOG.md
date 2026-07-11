# Noriter AI - Changelog

See [BUGFIXES.md](BUGFIXES.md) for a detailed, symptom → root cause → fix log of every bug found during development.

## [Unreleased]
### Added
- **EXAONE-4.5-33B (image-capable)** added to the recommended list for users who specifically want vision analysis from an EXAONE model. LG has no smaller vision-capable EXAONE -- the only image-capable release is 33B. Pulled via `hf.co/mradermacher/EXAONE-4.5-33B-i1-GGUF:Q2_K` (~10GB, the smallest available quant). Labeled with an explicit ⚠ warning: on a 6GB-VRAM GPU it mostly runs on system RAM and will be noticeably slow. `gemma3:4b` remains the fast/comfortable vision option for anyone not specifically tied to EXAONE.
- **Moondream-1.8B** added as a properly hardware-appropriate vision option (`moondream:1.8b`, ~1.7GB) -- fits a 6GB-VRAM GPU with plenty of headroom and runs fast, for anyone who wants quick image description/analysis without the EXAONE-4.5-33B slowdown.

### Fixed
- Attaching an image while a non-vision model was loaded showed a raw JSON API error ("Multimodal data provided, but model does not support multimodal requests"). Now checked upfront via Ollama's `/api/show` capabilities and shown as a clear message telling you to switch to a vision-capable model (e.g. `gemma3:4b`) instead.

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
