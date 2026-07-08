# Noriter AI - Changelog

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
