# Noriter AI — Session Handoff

Written for whichever agent/person picks this up next. See also
[SPEC.md](SPEC.md) (architecture), [CHANGELOG.md](CHANGELOG.md) (release
history), [BUGFIXES.md](BUGFIXES.md) (symptom → root cause → fix log).

Branch: `agents/project-brief-overview`. Current version: `v0.1.1`
(`noriter-ai-0.1.1.exe` at repo root).

---

## What this session did, in order

1. **Context-overflow handling** — `exceed_context_size_error` (HTTP 400 from
   the LLM backend) now trims oldest history and retries instead of crashing
   the turn.
2. **Context-size slider** — Engine panel got a 512–32768 token slider
   instead of a hardcoded `-c 4096`.
3. **Telegram bot bridge** — long-polls Telegram, routes messages through the
   same agent/history as the web chat. Two real bugs found and fixed here:
   - `chatId` misconfigured (was set to the bot's own ID) → messages read but
     never replied to. Fixed with auto-bind-to-first-sender.
   - Replies were always the literal text "Done." → fire-and-forget callback
     race in the reply-completion `Completer`. Fixed by awaiting the
     completer instead of racing an unconditional fallback.
4. **Local file attachment in chat** — 📎 button reads a local text file
   client-side and embeds it in the next message. Two bugs found here too:
   - Model tried `readFile`/`writeFile` on the attachment (doesn't exist in
     the workspace) → explicit "don't use tools for this" instructions added.
   - Full attachment content was persisted to `.noriter-ai/chat-history.json`
     and thus resent on *every later turn*, ballooning context. Fixed by
     storing a short placeholder in history and only sending the full body
     for the turn it was attached in.
5. **Remember last engine + confirm-to-relaunch** — `.noriter-ai/last-engine.json`
   remembers the last model + context size; next launch offers a native
   `confirm()` dialog to auto-restart it.
6. **`WS_DEBUG=1`** — env var that logs every WebSocket event + agent turn to
   stdout, for tracing what's happening when the UI doesn't show it clearly.
7. **Thoughts/tool activity shown as live text** — log blocks default to
   expanded instead of collapsed; activity bar shows a live thought preview
   instead of a static "thinking..." label.
8. **Malformed tool-call JSON no longer kills the turn** — small models
   sometimes emit `Action Input` as JS-style string concatenation
   (`"a" + "b"`) instead of one JSON string. Now repaired automatically, or
   fed back to the model as a "please retry with valid JSON" Observation.
9. **Truncated response fragments no longer shown as the final answer** —
   e.g. a bare `"Thought: I"` was being displayed as-is. Detected and
   retried (up to twice) instead.
10. **`max_tokens` was never set** on chat completion requests, so the
    backend silently capped/cut off responses. Now explicitly `2048`.
11. **Engine panel redesigned** — status line + model-select dropdown + Run
    button (was scattered action buttons); model lineup reworked around
    Gemma 3 (`gemma3:1b`/`gemma3:4b`) instead of the older Gemma 2.
12. **Engine backend + models folder made visible** — panel now shows what's
    actually running the LLM and the on-disk model storage path, plus an
    "📁 폴더에서 보기" button that opens it in Explorer.
13. **Backend swap: llama.cpp → Ollama** (the big one, `v0.1.0`). User's
    stated priority: frictionless local model use, no manual GGUF/path
    wrangling. `OllamaEngineManager` replaces `LlamaEngineManager`:
    - Embedded endpoint moved `:8080` (llama-server) → `:11434` (Ollama).
    - Models addressed by Ollama tag (`gemma3:4b`) instead of a downloaded
      file path. `LocalAgent`'s `model` field is kept in sync with whatever
      tag is actually loaded (Ollama requires an exact match; llama-server
      mostly didn't care).
    - If Ollama isn't installed, the app opens its download page rather than
      silently fetching/running a third-party installer.
    - Deleted `llama_engine_manager.dart`, `model_download_service.dart`,
      and the now-unused `archive` pub dependency.
14. **EXAONE 3.5 added to the recommended lineup** (`exaone3.5:2.4b`,
    `exaone3.5:7.8b`) — the 7.8b size was picked to fit comfortably within a
    6GB-VRAM GPU (GTX 1660 class) plus 32GB system RAM.
15. **Image attachment for vision models** — the same 📎 button now also
    accepts images (png/jpg/jpeg/gif/webp, max 4MB), read as a base64 data
    URL and sent as an OpenAI-style multimodal `image_url` content part
    (never inlined as text, never persisted to history -- same "turn-only"
    policy as file attachments). Required widening `LocalAgent`'s internal
    message list from `List<Map<String,String>>` to `List<Map<String,dynamic>>`
    so a message's `content` can be either a plain string or a multimodal
    parts array. `gemma3:4b` is the vision-capable pick in the recommended
    list; `gemma3:1b` and the EXAONE/Phi-3/Llama entries are text-only.

---

## ✅ Verified end-to-end on real hardware (updated from earlier draft)

The Ollama backend swap (item 13) was originally shipped **unverified** --
this sandbox had no Ollama install. That has since been confirmed working:
`exaone3.5:7.8b` was pulled and run through the app's Engine panel on the
user's real machine (GTX 1660 / 32GB RAM), and a plain-text chat round-trip
through it produced a correct, coherent reply (confirmed *after* the
message-type widening for image support too, so that refactor didn't
regress ordinary text chat either).

**Still not verified**: the actual image-upload → vision-model-sees-it path
(item 15). No test image file was available in the sandbox this was built
in. Recommended before relying on it:
1. Pull `gemma3:4b` from the Engine panel.
2. Run it, then attach a real image via 📎 and ask something about it.
3. Confirm the reply describes the image's actual content, not a generic
   "I can't see images" refusal (which would mean the multimodal payload
   isn't reaching the model correctly -- check Ollama's `/v1/chat/completions`
   image_url format expectations first if that happens).

Also still worth a look if you're in this area next: Telegram bridge and
text file attachment haven't been *specifically* re-verified against Ollama
(only against the old llama.cpp backend originally) -- they go through the
same `LocalAgent` code path so should be fine, but haven't been re-run.

---

## Known rough edges / things worth doing next

- **`lastEngineFound` uses a native `confirm()` dialog**, which blocks the
  entire page (including automated browser testing — it hung `screenshot`
  calls in this session until dismissed via `navigate --force`). Consider
  replacing with an in-page modal if this becomes annoying.
- **`EngineState`/`engineStatus` payload still has a leftover `engineDir`
  field** that's now just an alias for `modelsDir` in Ollama's manager (no
  real separate "engine binary directory" concept anymore). Harmless but
  could be cleaned up.
- **No GPU acceleration** — Ollama itself may use GPU automatically depending
  on the user's install, but nothing in this codebase configures or reports
  that; worth checking whether `num_gpu`/similar options should be exposed.
- **`.noriter-ai/telegram-config.json` contains a live bot token in this
  workspace** (gitignored, never committed — verified each time it came up
  this session). If you're continuing work here, don't `cat` it into any
  tool output that might get logged/shared; treat it as a live secret.
- **`src/` (legacy VS Code extension, TypeScript)** was never touched this
  session and is increasingly stale relative to `dart_platform/`. Not in
  scope unless someone explicitly asks for VS Code extension work again.

---

## Workflow notes for whoever continues this

- **Every build requires killing the running exe first** — `dart compile exe`
  fails with a file-lock error otherwise (this came up constantly this
  session; check `tasklist | grep noriter` before compiling).
- **Build command**: from `dart_platform/`, `dart compile exe bin/noriter_ai.dart -o ../noriter-ai-<version>.exe`.
- **`dart analyze`** should show zero issues (one pre-existing unrelated
  warning in `config.dart` was fixed as a side effect of the Ollama config
  change — if it reappears, something regressed).
- **UI changes were verified by actually launching the exe and driving it
  in the Browser pane** (`get_page_text`/`read_page`/`computer` click), not
  just by reading the generated HTML. Worth doing the same for future UI
  changes — `assets.dart` is a giant inline HTML/CSS/JS string with no
  compile-time checking of the JS portion.
- **`.noriter-ai/chat-history.json` and `.noriter-ai/last-engine.json` are
  session state, not source** — don't commit changes to them unless the
  user specifically asks. They get modified just by running the app.
