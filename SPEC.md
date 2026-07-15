# Noriter AI — Program Specification

## Overview

Noriter AI is a Windows desktop application that runs a local LLM-powered AI agent entirely on-device — no cloud services, no VS Code, no LM Studio required.

**v0.1.3 is a from-scratch rewrite** onto Tauri + Rust, replacing the v0.1.2 single-EXE Dart server. See [Architecture (v0.1.3)](#architecture-v013-tauri--rust) below for the current design, and [Architecture (v0.1.2, superseded)](#architecture-v012-superseded) for the still-shipped previous build. The rewrite is **not yet packaged as an installer** -- it currently runs via `cargo tauri dev` from source (see [Build](#build-v013)).

See also: [CHANGELOG.md](CHANGELOG.md) for release history, [BUGFIXES.md](BUGFIXES.md) for a symptom → root cause → fix log of bugs found during development.

---

## Architecture (v0.1.3, Tauri + Rust)

```
src-tauri/                      ← Rust backend (Tauri 2)
  src/main.rs                   ← App bootstrap: tray icon, close-to-hide,
  │                                IPC command registration, Telegram
  │                                autostart from saved config
  src/ollama.rs                 ← Ollama HTTP client (chat/status/models/
  │                                running_models), returns ChatResult
  │                                { content, tokens_used, elapsed_ms }
  src/telegram.rs               ← teloxide long-poll loop, runs for the
  │                                process lifetime independent of window
  │                                visibility; auto-binds to the first
  │                                chat that messages the bot and persists
  │                                the chat ID; ignores other chats/bots;
  │                                echoes the prompt above the reply;
  │                                replies with setup guidance instead of
  │                                calling Ollama if no model is picked yet
  src/queue.rs                  ← Shared FIFO (QueueState) serializing
  │                                Ollama calls from web chat + Telegram
  │                                through one lock; broadcasts
  │                                `queue-update` events for the UI
  src/config.rs                 ← AppConfig persistence to the OS config
                                   dir (plaintext JSON -- not yet encrypted,
                                   see BUGFIXES.md/known gaps)

dart_ui/                        ← Dart Wasm frontend (no dart:io anywhere --
  │                                Wasm has no filesystem/process/socket
  │                                access, so all of that lives in Rust)
  lib/main.dart                 ← UI thread: renders the chat log + the
  │                                🧠모델/✈텔레그램/⚙설정/📋큐 panels,
  │                                owns all `window.__TAURI__` IPC calls
  lib/tauri_bridge.dart         ← invoke()/listen() JS-interop wrapper;
  │                                no-ops outside the real Tauri webview
  lib/worker_bridge.dart        ← Main-thread side of the Web Worker
  │                                request/response protocol
  lib/worker_main.dart          ← Worker entry point (compiled to a
  │                                separate Wasm module, worker.dart.wasm)
  lib/worker/logic.dart         ← Pure business logic run in the worker:
  │                                message timestamp/stats formatting +
  │                                HTML-escaping, Ollama request
  │                                preprocessing (default model, context
  │                                clamping) -- no DOM/Tauri access here
  build.sh                      ← Compiles both Wasm modules + assembles
                                   build/web (Tauri's frontendDist)
```

**Threading model:** the UI thread (`main.dart.wasm`) owns the DOM and all Tauri IPC; a Web Worker (`worker.dart.wasm`) owns pure data transformation, reached via `postMessage`+JSON (`WorkerBridge.call(type, payload)` on the main side, `logic.handle(type, payload)` in the worker). Neither module can see into the other's Dart runtime -- everything crossing the boundary is jsify'd/dartify'd JSON.

**Generation queue:** every Ollama call (web chat's `ollama_chat` command, and each Telegram message) is wrapped in `queue::run_queued()`, which enqueues a `{id, preview, source, status}` entry, waits on a shared `tokio::sync::Mutex` so only one generation runs at a time, and broadcasts the queue's contents as a `queue-update` event. The 📋 큐 panel renders this live and shows a count badge even when closed.

**System tray:** `[X]` hides the window (`WindowEvent::CloseRequested` → `window.hide()` + `prevent_close()`) instead of quitting; the Telegram bridge is spawned once in `setup()` independent of the window, so it keeps polling while hidden. Tray icon is built imperatively via `TrayIconBuilder` (not the declarative `tauri.conf.json` `trayIcon` key -- using both created two icons, see BUGFIXES.md). Process priority drops to `IDLE_PRIORITY_CLASS` while hidden and restores to `NORMAL_PRIORITY_CLASS` on show (`src/power.rs`, Windows-only).

**Conversation working memory** (`src/memory.rs`, session-only, not persisted): each source (`"web"`, or `"telegram:{chat_id}"`) keeps its own in-memory turn history. The last 3 turns are replayed to Ollama verbatim; turns 4-8 back are compressed into one short summary via an extra Ollama call (itself routed through the same `queue::run_queued` FIFO, so it never runs concurrently with a real generation); anything older than 8 turns back is dropped with no summary. Attachment payloads (image bytes, extracted file text) are only ever sent for the turn they arrived in -- remembered turns store plain prompt text only, so a multi-turn conversation about a file/image stays coherent without the payload growing every turn.

**Personal persistent memory** (`src/personal_memory.rs`, persisted to `<config dir>/noriter-ai/memory.json`, survives restarts -- distinct from the session-only working memory above): durable facts/preferences about the user. Injected into the front of every request (pinned entries first, then most recently updated, capped at ~2000 chars). Grows two ways: manually via the 🧑 메모리 panel (add/edit/delete/pin), or automatically every 5th turn per source via a short extra Ollama call that either extracts one durable fact or returns `NONE`.

**LLM wiki** (`src/wiki.rs`, persisted to `<config dir>/noriter-ai/wiki/index.json`): user-curated documents (title/summary/body/tags/related_ids) via the 📚 위키 panel. Unlike personal memory, entries are never auto-injected into requests and never auto-created -- it's a "look things up" store, not an "always on" one, to avoid every conversation turning into wiki noise.

**Not yet ported from the v0.1.2 Dart build** (explicitly deferred, not accidental gaps):
- Chat history *persistence* -- working memory (above) covers same-session follow-ups, but nothing survives an app restart
- Ollama streaming responses (token-by-token) -- `ollama_chat` waits for the full response
- Config file encryption (bot token currently stored as plaintext JSON)
- Window chrome control (frameless/opacity/always-on-top)
- Installer packaging (`.msi`/`.exe`) -- only `cargo tauri dev` has been run

### Logging (v0.1.3)

No structured logging or log file yet -- everything below is ad-hoc `println!`/`console` output, only visible when the app is launched from a terminal (a plain double-click of the `.exe` shows nothing, since Windows console subsystem is suppressed in release builds via `windows_subsystem = "windows"`).

| Where | What | Visible how |
|-------|------|-------------|
| `src-tauri/src/queue.rs` (`broadcast()`) | `println!("queue broadcast: {n} item(s)")`, `println!("queue broadcast: emit ok")` / `eprintln!("queue broadcast: emit FAILED: {e}")` on every queue state change | Rust process stdout/stderr -- run `.\target\debug\noriter-ai.exe` from a PowerShell/terminal window, not by double-clicking, to see it. Added while diagnosing the `queue-update` event not reaching the frontend (see BUGFIXES.md). |
| `dart_ui/web/bootstrap.js`, `dart_ui/web/worker_bootstrap.js` | `console.error('... wasm boot failed:', e)` if the respective Wasm module fails to compile/instantiate | Webview devtools console (right-click → 검사, if enabled) -- for the main UI thread and the Web Worker respectively |
| `dart2wasm` runtime (`main.dart.mjs`/`worker.dart.mjs`, generated) | Dart's built-in top-level `print()` compiles down to a `console.log` call in the generated JS glue | Not currently used anywhere in `dart_ui/lib/**` -- no `print()` calls exist yet, so this path is dormant, but any future `print()` in Dart source will surface here automatically |

**Not present in v0.1.3** (were in the old v0.1.2 Dart server, not carried over): the `WS_DEBUG=1` env var that logged every WebSocket event/agent turn to stdout, and any per-request history/log file under `.noriter-ai/`.

### Build (v0.1.3)

Requires Rust 1.88+ (`rustup update stable`), `cargo install tauri-cli --version "^2.0"`, and Dart SDK 3.4+.

```powershell
cd dart_ui
bash build.sh              # compiles main.dart.wasm + worker.dart.wasm into build/web

cd ../src-tauri
cargo tauri dev             # or: cargo build, then run target/debug/noriter-ai.exe
```

---

## Architecture (v0.1.2, superseded)

```
noriter-ai-0.1.2.exe
└── Dart AOT binary (single file, no runtime dependency)
    ├── HTTP server  (shelf)  → localhost:3742
    │   ├── GET  /          → embedded HTML (chat UI)
    │   ├── GET  /main.css  → embedded CSS
    │   ├── GET  /main.js   → embedded JS
    │   └── WS   /ws        → WebSocket (bidirectional agent communication)
    │
    ├── OllamaEngineManager
    │   ├── Detects a local Ollama install (default install paths, then PATH)
    │   ├── Starts `ollama serve` if installed but not running
    │   ├── Pulls/lists models via Ollama's HTTP API (/api/pull, /api/tags)
    │   ├── "Runs" a model by warming it with an empty /api/generate call
    │   │   (num_ctx set here persists for later chat calls while it stays loaded)
    │   ├── If not installed, opens ollama.com/download in the browser --
    │   │   the app does not silently download/run the installer itself
    │   └── Exposes OpenAI-compatible API at http://127.0.0.1:11434/v1
    │
    ├── LocalAgent  (ReAct loop)
    │   ├── Thought → Tool → Observation loop
    │   ├── Calls LLM via OpenAI-compatible /v1/chat/completions (max_tokens: 2048)
    │   ├── Auto-recovers from exceed_context_size_error by trimming oldest context and retrying
    │   ├── Repairs/self-corrects malformed tool-call JSON instead of aborting the turn
    │   └── Uses 9 built-in tools (see Tools section)
    │
    ├── Request queue (NoriterServer._runQueued)
    │   ├── Serializes web chat + Telegram requests through one FIFO so they
    │   │   never run the agent concurrently against shared _agent/_cancelled state
    │   └── Broadcasts queue state (queueUpdate) for the "📋 Request Queue" UI panel
    │
    ├── TelegramBridge
    │   ├── Long-polls the Telegram Bot API (getUpdates)
    │   ├── Auto-binds to the first chat that messages the bot if no chat ID is configured
    │   ├── Routes messages through the same LocalAgent/history as the web chat
    │   ├── Photos are downloaded via getFile and sent as a multimodal message
    │   │   (same vision-capability check as the web chat's image attachment)
    │   ├── Documents (Telegram's "document" message field, e.g. .xlsx) are
    │   │   also downloaded and embedded the same way as the web chat's file
    │   │   attachment (.xlsx via excelBytesToText(), else UTF-8 text)
    │   └── Settings persisted to .noriter-ai/telegram-config.json (gitignored)
    │
    ├── Local file/image/spreadsheet attachment (chat UI)
    │   ├── Paperclip button reads a local text file client-side (FileReader, max 500 KB)
    │   │   and embeds its content in the next chat message
    │   ├── Also accepts images (png/jpg/jpeg/gif/webp, max 4MB) via readAsDataURL,
    │   │   sent as a multimodal message part -- requires a vision-capable model
    │   │   (e.g. gemma3:4b; smaller Gemma 3 sizes and most other models are text-only)
    │   └── Also accepts .xlsx (max 8MB) via readAsDataURL; server decodes the base64
    │       and parses it with the `excel` package into plain text (one section per
    │       sheet, pipe-separated cells), then handles it like a text attachment.
    │       PDF is not supported yet (viable Dart libraries need bundled native DLLs).
    │
    ├── LastEngineService
    │   ├── Remembers the last model path + context size that started successfully
    │   ├── Persisted to .noriter-ai/last-engine.json
    │   └── On next launch, offers a confirm dialog to auto-relaunch it if the file still exists
    │
    └── Services
        ├── HistoryService   → .noriter-ai/chat-history.json
        ├── MemoryService    → .noriter-ai/agent-memory.md
        └── GoalService      → .noriter-ai/agent-goal.md
```

---

## Engine Modes

| Mode | Trigger | LLM endpoint |
|------|---------|-------------|
| **Embedded** (default) | `NORITER_MODEL_ENDPOINT` not set | `http://127.0.0.1:11434/v1` (Ollama) |
| **External** | `NORITER_MODEL_ENDPOINT=http://...` env var | Custom OpenAI-compatible URL (e.g. LM Studio) |

Prior to v0.1.0 the embedded engine was a bundled llama.cpp (`llama-server.exe`)
subprocess reading GGUF files directly. That constrained models to whatever
had been manually converted to GGUF and downloaded by URL. Ollama replaces
that: it manages its own model registry, handles pulling/quantization
internally, and is addressed purely by model tag (e.g. `gemma3:4b`) instead
of a filesystem path -- a much lower-friction "pick a model, click Run" flow.

---

## Built-in Tools (ReAct Agent)

| Tool | Description |
|------|-------------|
| `readFile` | Read a file from the workspace |
| `writeFile` | Write/overwrite a file in the workspace |
| `listFiles` | List files in a directory |
| `searchFiles` | Search file contents with a pattern |
| `runCommand` | Execute a shell command |
| `fetchUrl` | HTTP GET a URL and return the body |
| `readMemory` | Read agent-memory.md |
| `writeMemory` | Write agent-memory.md |
| `webSearch` | Perform a web search (via DuckDuckGo) |

---

## Recommended Models (Ollama tags)

| Model | Ollama tag | Notes |
|-------|-----------|-------|
| Gemma-3-1B-Instruct | `gemma3:1b` | Fastest, low RAM |
| Llama-3.2-1B-Instruct | `llama3.2:1b` | Alternative to Gemma-3-1B |
| Gemma-3-4B-Instruct | `gemma3:4b` | Best overall quality/speed; **image-capable** (vision) |
| Phi-3-mini | `phi3:mini` | Quality alternative |
| EXAONE-3.5-2.4B-Instruct | `exaone3.5:2.4b` | LG AI Research, light |
| EXAONE-3.5-7.8B-Instruct | `exaone3.5:7.8b` | LG AI Research, fits a 6GB-VRAM GPU (e.g. GTX 1660) + 32GB RAM comfortably |
| EXAONE-4.5-33B | `hf.co/mradermacher/EXAONE-4.5-33B-i1-GGUF:Q2_K` | LG's only **image-capable** EXAONE (no smaller vision variant exists). ⚠ Does not fit a 6GB-VRAM GPU -- mostly runs on system RAM and will be slow. Included for users who specifically want EXAONE for vision despite the tradeoff. |
| Moondream-1.8B | `moondream:1.8b` | Tiny, fast, **image-capable**; fits a 6GB-VRAM GPU comfortably -- the hardware-appropriate vision pick |
| Gemma-4-12B | `gemma4:12b` | Newer than Gemma 3, **image-capable**, 256K context; ~7.6GB download (barely more than the e2b edge variant) for meaningfully more capability |

---

## WebSocket Message Protocol

### Client → Server

| `type` | Payload | Action |
|--------|---------|--------|
| `sendMessage` | `{ value: string, attachment?: { name, content, isImage?, isExcel? } }` | Run agent with user message, optionally embedding an attached local file's text content, sending it as a multimodal image part (`isImage`, `content` a base64 data URL), or parsing it as a spreadsheet (`isExcel`, `content` a base64 data URL of the .xlsx bytes) |
| `stopAgent` | — | Cancel current agent run |
| `clearHistory` | — | Clear chat history |
| `downloadEngine` | — | If Ollama isn't installed, opens its download page in the browser; if installed, starts `ollama serve` |
| `startEngine` | `{ modelPath: <ollama tag>, contextSize?: int }` | Loads a model into Ollama (contextSize clamped 512–32768, default 4096; `modelPath` holds the Ollama tag despite the legacy field name) |
| `applyContextSize` | `{ contextSize: int }` | Reloads the currently active model with a new context size; rejected (via an `error` broadcast) if a request is running/queued or no model is loaded |
| `downloadModel` | `{ tag: <ollama tag> }` | Pulls a model via Ollama |
| `getEngineStatus` | — | Request current engine state |
| `listLocalModels` | — | List models already pulled into Ollama |
| `getTelegramStatus` | — | Request current Telegram bridge status |
| `updateTelegramConfig` | `{ botToken?, chatId?, enabled? }` | Save Telegram settings and start/stop the bridge |
| `openModelsFolder` | — | Opens Ollama's model storage folder in Windows Explorer |

### Server → Client

| `type` | Payload | Description |
|--------|---------|-------------|
| `history` | `{ entries }` | Full chat history on connect |
| `sessionStart` | `{ userPrompt }` | Agent started processing |
| `thought` | `{ value }` | Agent reasoning step |
| `toolStart` | `{ name, args }` | Tool call started |
| `toolEnd` | `{ name, output }` | Tool call completed |
| `finalAnswer` | `{ value, tokensUsed?, elapsedMs? }` | Agent final response; `tokensUsed`/`elapsedMs` cover the whole turn (all tool-calling iterations), persisted to history and shown under the message |
| `error` | `{ value }` | Error message |
| `engineStatus` | `{ state, isInstalled, localModels, engineBackend, modelsDir, engineDir, ... }` | Engine state update (`state.contextSize`, `engineBackend` label, and on-disk `modelsDir`/`engineDir` paths included) |
| `localModelsList` | `{ models }` | List of downloaded models |
| `telegramStatus` | `{ config, running, statusMessage }` | Telegram bridge state (`config` is redacted — no full token) |
| `lastEngineFound` | `{ modelPath, contextSize }` | Sent once per app run if a remembered engine exists and none is running yet; frontend shows a confirm dialog before auto-starting it |
| `queueUpdate` | `{ items: [{ id, preview, source, status }] }` | Current request queue (web chat + Telegram share one FIFO); `status` is `waiting` or `running`, `source` is `web` or `telegram` |

---

## File Layout

```
noriter-ai-0.1.2.exe          ← Standalone Windows EXE (no installer needed)
CHANGELOG.md                   ← Version history
SPEC.md                        ← This file

dart_platform/                 ← Dart source code
  bin/noriter_ai.dart          ← Entry point
  lib/src/
    server.dart                ← HTTP + WebSocket server (shelf)
    assets.dart                ← Embedded HTML/CSS/JS (inline strings)
    config.dart                ← AppConfig (port, endpoint, engine mode)
    local_agent.dart           ← ReAct agent loop
    tools.dart                 ← 9 built-in tools
    engine_state.dart          ← EngineMode / EngineStatus enums + state
    history_service.dart       ← Chat history persistence (JSON)
    memory_service.dart        ← Agent memory file (Markdown)
    goal_service.dart          ← Agent goal file (Markdown)
    model_provider.dart        ← OpenAI-compatible HTTP client
    excel_service.dart         ← .xlsx bytes -> plain-text table conversion
    ollama_engine_manager.dart ← Ollama detection/serve/pull/run + recommended model list
    telegram_bridge.dart       ← Telegram Bot API long-polling bridge
    telegram_config_service.dart← Telegram bot token / chat ID persistence
    last_engine_service.dart   ← Remembers last-started model tag + context size
    agent_app.dart             ← (legacy CLI bootstrap, superseded by server.dart)
    plan_logger.dart           ← Appends to project-plan-log.md

src/                           ← Legacy VS Code extension (TypeScript, v0.0.5)
  extension.ts
  agent/
  telegram/
  webview/

.noriter-ai/                   ← Per-workspace agent state
  chat-history.json
  agent-memory.md
  agent-goal.md
  project-plan-log.md
  telegram-config.json         ← Bot token / chat ID (gitignored, contains secrets)
  last-engine.json             ← Last-started Ollama model tag + context size
```

---

## How to Run

```batch
REM Just double-click or run from terminal:
noriter-ai-0.1.2.exe

REM Optionally specify a workspace path:
noriter-ai-0.1.2.exe C:\MyProject

REM Use external LLM (e.g. LM Studio on port 1234):
set NORITER_MODEL_ENDPOINT=http://localhost:1234/v1
noriter-ai-0.1.2.exe
```

The app opens `http://localhost:3742` in your default browser automatically.

Requires [Ollama](https://ollama.com/download) to be installed for embedded mode. If it isn't found, the [Engine] panel's Install button opens the download page for you.

---

## Build

Requires [Dart SDK](https://dart.dev/get-dart) 3.3+.

```batch
cd dart_platform
dart pub get
dart compile exe bin/noriter_ai.dart -o ..\noriter-ai-0.1.2.exe
```
