# Noriter AI - Changelog

## [0.0.7] - 2026-07-09
### Fixed
- Fixed encoding corruption in `assets.dart` — all broken Korean characters in HTML/JS UI replaced with English equivalents
- Fixed broken Korean strings in `server.dart` status messages (engine status, model download progress, error messages)

### Changed
- All UI text in the embedded web frontend is now in English for encoding stability

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
