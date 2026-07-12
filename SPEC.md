# Noriter AI — Program Specification

## Overview

Noriter AI is a standalone Windows desktop application that runs a local LLM-powered AI agent entirely on-device — no cloud services, no VS Code, no LM Studio required.

The app is distributed as a single EXE (`noriter-ai-0.0.x.exe`, ~7–8 MB) with no installer and no code signing. It works on Windows 10/11 without admin rights.

See also: [CHANGELOG.md](CHANGELOG.md) for release history, [BUGFIXES.md](BUGFIXES.md) for a symptom → root cause → fix log of bugs found during development.

---

## Architecture

```
noriter-ai-0.1.1.exe
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
    ├── TelegramBridge
    │   ├── Long-polls the Telegram Bot API (getUpdates)
    │   ├── Auto-binds to the first chat that messages the bot if no chat ID is configured
    │   ├── Routes messages through the same LocalAgent/history as the web chat
    │   └── Settings persisted to .noriter-ai/telegram-config.json (gitignored)
    │
    ├── Local file/image attachment (chat UI)
    │   ├── Paperclip button reads a local text file client-side (FileReader, max 500 KB)
    │   │   and embeds its content in the next chat message
    │   └── Also accepts images (png/jpg/jpeg/gif/webp, max 4MB) via readAsDataURL,
    │       sent as a multimodal message part -- requires a vision-capable model
    │       (e.g. gemma3:4b; smaller Gemma 3 sizes and most other models are text-only)
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
| `sendMessage` | `{ value: string, attachment?: { name, content, isImage? } }` | Run agent with user message, optionally embedding an attached local file's text content or (if `isImage`, with `content` as a base64 data URL) sending it as a multimodal image part |
| `stopAgent` | — | Cancel current agent run |
| `clearHistory` | — | Clear chat history |
| `downloadEngine` | — | If Ollama isn't installed, opens its download page in the browser; if installed, starts `ollama serve` |
| `startEngine` | `{ modelPath: <ollama tag>, contextSize?: int }` | Loads a model into Ollama (contextSize clamped 512–32768, default 4096; `modelPath` holds the Ollama tag despite the legacy field name) |
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
| `finalAnswer` | `{ value }` | Agent final response |
| `error` | `{ value }` | Error message |
| `engineStatus` | `{ state, isInstalled, localModels, engineBackend, modelsDir, engineDir, ... }` | Engine state update (`state.contextSize`, `engineBackend` label, and on-disk `modelsDir`/`engineDir` paths included) |
| `localModelsList` | `{ models }` | List of downloaded models |
| `telegramStatus` | `{ config, running, statusMessage }` | Telegram bridge state (`config` is redacted — no full token) |
| `lastEngineFound` | `{ modelPath, contextSize }` | Sent once per app run if a remembered engine exists and none is running yet; frontend shows a confirm dialog before auto-starting it |

---

## File Layout

```
noriter-ai-0.1.1.exe          ← Standalone Windows EXE (no installer needed)
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
noriter-ai-0.1.1.exe

REM Optionally specify a workspace path:
noriter-ai-0.1.1.exe C:\MyProject

REM Use external LLM (e.g. LM Studio on port 1234):
set NORITER_MODEL_ENDPOINT=http://localhost:1234/v1
noriter-ai-0.1.1.exe
```

The app opens `http://localhost:3742` in your default browser automatically.

Requires [Ollama](https://ollama.com/download) to be installed for embedded mode. If it isn't found, the [Engine] panel's Install button opens the download page for you.

---

## Build

Requires [Dart SDK](https://dart.dev/get-dart) 3.3+.

```batch
cd dart_platform
dart pub get
dart compile exe bin/noriter_ai.dart -o ..\noriter-ai-0.1.1.exe
```
