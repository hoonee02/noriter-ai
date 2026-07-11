# Noriter AI — Program Specification

## Overview

Noriter AI is a standalone Windows desktop application that runs a local LLM-powered AI agent entirely on-device — no cloud services, no VS Code, no LM Studio required.

The app is distributed as a single EXE (`noriter-ai-0.0.x.exe`, ~7–8 MB) with no installer and no code signing. It works on Windows 10/11 without admin rights.

---

## Architecture

```
noriter-ai-0.0.8.exe
└── Dart AOT binary (single file, no runtime dependency)
    ├── HTTP server  (shelf)  → localhost:3742
    │   ├── GET  /          → embedded HTML (chat UI)
    │   ├── GET  /main.css  → embedded CSS
    │   ├── GET  /main.js   → embedded JS
    │   └── WS   /ws        → WebSocket (bidirectional agent communication)
    │
    ├── LlamaEngineManager
    │   ├── Downloads llama-server.exe from github.com/ggerganov/llama.cpp releases
    │   ├── Extracts to %APPDATA%\noriter-ai\engine\
    │   ├── Starts llama-server as a subprocess on port 8080
    │   └── Exposes OpenAI-compatible API at http://127.0.0.1:8080/v1
    │
    ├── ModelDownloadService
    │   ├── Downloads GGUF model files (Hugging Face URLs)
    │   └── Stores in %APPDATA%\noriter-ai\models\
    │
    ├── LocalAgent  (ReAct loop)
    │   ├── Thought → Tool → Observation loop
    │   ├── Calls LLM via OpenAI-compatible /v1/chat/completions
    │   ├── Auto-recovers from exceed_context_size_error by trimming oldest context and retrying
    │   └── Uses 9 built-in tools (see Tools section)
    │
    ├── TelegramBridge
    │   ├── Long-polls the Telegram Bot API (getUpdates)
    │   ├── Auto-binds to the first chat that messages the bot if no chat ID is configured
    │   ├── Routes messages through the same LocalAgent/history as the web chat
    │   └── Settings persisted to .noriter-ai/telegram-config.json (gitignored)
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
| **Embedded** (default) | `NORITER_MODEL_ENDPOINT` not set | `http://127.0.0.1:8080/v1` (llama-server) |
| **External** | `NORITER_MODEL_ENDPOINT=http://...` env var | Custom OpenAI-compatible URL (e.g. LM Studio) |

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

## Recommended GGUF Models

| Model | Size | Notes |
|-------|------|-------|
| Qwen2.5-0.5B-Instruct-GGUF | ~400 MB | Fastest, low RAM |
| Llama-3.2-1B-Instruct-GGUF | ~800 MB | Good balance |
| Phi-3-mini-4k-instruct-GGUF | ~2.2 GB | High quality small model |
| Gemma-2-2B-GGUF | ~1.6 GB | Google Gemma 2 |

---

## WebSocket Message Protocol

### Client → Server

| `type` | Payload | Action |
|--------|---------|--------|
| `sendMessage` | `{ value: string }` | Run agent with user message |
| `stopAgent` | — | Cancel current agent run |
| `clearHistory` | — | Clear chat history |
| `downloadEngine` | — | Download llama-server.exe |
| `startEngine` | `{ modelPath: string, contextSize?: int }` | Start llama-server with a model (contextSize clamped 512–32768, default 4096) |
| `downloadModel` | `{ url, filename? }` | Download a GGUF model |
| `getEngineStatus` | — | Request current engine state |
| `listLocalModels` | — | List downloaded GGUF models |
| `getTelegramStatus` | — | Request current Telegram bridge status |
| `updateTelegramConfig` | `{ botToken?, chatId?, enabled? }` | Save Telegram settings and start/stop the bridge |

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
| `engineStatus` | `{ state, isInstalled, localModels, ... }` | Engine state update (`state.contextSize` included) |
| `localModelsList` | `{ models }` | List of downloaded models |
| `telegramStatus` | `{ config, running, statusMessage }` | Telegram bridge state (`config` is redacted — no full token) |

---

## File Layout

```
noriter-ai-0.0.8.exe          ← Standalone Windows EXE (no installer needed)
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
    llama_engine_manager.dart  ← llama-server.exe lifecycle manager
    model_download_service.dart← GGUF model downloader
    engine_state.dart          ← EngineMode / EngineStatus enums + state
    history_service.dart       ← Chat history persistence (JSON)
    memory_service.dart        ← Agent memory file (Markdown)
    goal_service.dart          ← Agent goal file (Markdown)
    model_provider.dart        ← OpenAI-compatible HTTP client
    telegram_bridge.dart       ← Telegram Bot API long-polling bridge
    telegram_config_service.dart← Telegram bot token / chat ID persistence
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
```

---

## How to Run

```batch
REM Just double-click or run from terminal:
noriter-ai-0.0.8.exe

REM Optionally specify a workspace path:
noriter-ai-0.0.8.exe C:\MyProject

REM Use external LLM (e.g. LM Studio on port 1234):
set NORITER_MODEL_ENDPOINT=http://localhost:1234/v1
noriter-ai-0.0.8.exe
```

The app opens `http://localhost:3742` in your default browser automatically.

---

## Build

Requires [Dart SDK](https://dart.dev/get-dart) 3.3+.

```batch
cd dart_platform
dart pub get
dart compile exe bin/noriter_ai.dart -o ..\noriter-ai-0.0.8.exe
```
