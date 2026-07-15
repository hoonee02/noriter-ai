# Noriter AI — Session Handoff

Written for whichever agent/person picks this up next. See also
[SPEC.md](SPEC.md) (architecture), [CHANGELOG.md](CHANGELOG.md) (release
history), [BUGFIXES.md](BUGFIXES.md) (symptom → root cause → fix log).

Branch: `agents/project-brief-overview`. **A full rewrite onto Tauri + Rust
(`v0.1.3`) is complete for this pass**, replacing the v0.1.2 single-EXE Dart
server described in the rest of this file. The v0.1.2 section below is kept
for history/reference but is **not the current codebase shape** -- see the
v0.1.3 section immediately below for what's actually being worked on now.

---

## v0.1.3 session — Tauri + Rust rewrite

Not yet packaged as an installer; only runs via `cargo tauri dev` /
`target/debug/noriter-ai.exe` from source. See
[SPEC.md#architecture-v013-tauri--rust](SPEC.md#architecture-v013-tauri--rust)
for the architecture this section assumes.

### What this session did, in order

1. **Scaffolded `src-tauri/`** — Cargo.toml, `tauri.conf.json`, `main.rs`
   with system tray + close-to-hide + IPC command registration. Had to
   `rustup update stable` (1.86 → 1.97) -- some Tauri 2 deps need 1.88+.
2. **`src/ollama.rs`** — Rust HTTP client for Ollama (`chat`, `is_running`,
   `list_models`, `running_models`). `chat()` returns `ChatResult { content,
   tokens_used, elapsed_ms }`, timed on the Rust side so elapsed time is
   always available even if Ollama's own duration fields are absent.
3. **`src/telegram.rs`** — `teloxide`-based long-poll loop, spawned once in
   `setup()` so it survives window hide/show. Ported from the old
   `dart_platform/lib/src/telegram_bridge.dart`: auto-binds to the first
   chat that messages the bot and persists the chat ID to config; ignores
   messages from any other chat once bound; ignores bot-authored messages;
   truncates outgoing replies to Telegram's ~4096-char limit; echoes the
   original prompt (`> {text}`) above the generated reply. Explicitly
   **not** ported: photo/document attachment handling, conversation history
   (every message is a fresh 1-turn exchange).
4. **`dart_ui/`** — new Dart Wasm frontend package, zero `dart:io` usage
   (dart2wasm can't compile it — no filesystem/process/socket access in a
   browser/Wasm target). Chat UI talks to Rust exclusively through
   `window.__TAURI__` (`withGlobalTauri: true` in `tauri.conf.json`).
   `dart_ui/build.sh` compiles it and assembles `build/web`
   (Tauri's `frontendDist`).
5. **Web Worker split** (explicit user request, matching the original spec's
   requirement 1.1) — `lib/worker_main.dart` compiles to a *separate* Wasm
   module (`worker.dart.wasm`) that runs inside a dedicated Web Worker.
   `lib/worker/logic.dart` holds pure functions (message
   timestamp/stats/HTML-escape formatting, Ollama request preprocessing) —
   no DOM or Tauri access, since neither exists inside a worker.
   `lib/worker_bridge.dart` is the main-thread request/response wrapper
   (correlates replies by an incrementing id since `postMessage` is a bare
   event, not a `Future`). Verified in a real browser: `worker_bootstrap.js`
   actually loads as a separate network request and the round-trip through
   it produces correctly formatted messages.
6. **🧠 모델 / ✈ 텔레그램 / ⚙ 설정 panel split** — originally one combined
   "설정" panel, split into three per explicit user request ("설정버튼은
   관리적 기능을 보완 강화하는 방향으로"). Model panel has a live "동작
   현황" section (Ollama connected / model installed / model **actually
   loaded into memory**, via `/api/ps`) that polls every 3s while open and
   refreshes right after any chat reply.
7. **📋 큐 panel** — `src-tauri/src/queue.rs`: `queue::run_queued()` wraps
   every Ollama call (web chat's `ollama_chat` command *and* each Telegram
   message) in one shared FIFO (`tokio::sync::Mutex`), so the two surfaces
   never call Ollama concurrently. Broadcasts `queue-update` events; the
   panel renders live entries and a count badge on the button itself even
   when the panel is closed.
8. **Message timestamps + generation stats** — every message gets a
   `YYYY-MM-DD HH:mm:ss` timestamp; assistant replies additionally show
   `N tokens · X.Xs`. Formatting happens in the Web Worker (item 5), not
   inline in the UI thread.
9. **HANDOFF.md/SPEC.md/CHANGELOG.md/BUGFIXES.md updated** for the rewrite
   (this pass) — none of it had been touched while the Tauri work was
   happening; caught only when the user asked directly.

### Real bugs found this session (see BUGFIXES.md for full detail)
- **Duplicate tray icon** — both `tauri.conf.json`'s declarative `trayIcon`
  config *and* the imperative `TrayIconBuilder` in `main.rs` created one.
  Fixed by removing the config-based one.
- **Settings save silently stuck on "저장 중..."** — no `try`/`catch`
  around the IPC calls masked the real error, which was the Model
  `<input>`'s gray placeholder text being mistaken for an actual value
  (sent as `null`). Fixed by adding error surfacing *and* replacing
  freetext with a `<select>` so this class of bug can't recur.
- **`start_telegram` required both token and model** — relaxed to only
  require the token; a missing model degrades to an in-chat guidance
  message instead of blocking the bridge from starting at all (see item 3
  in "what this session did" — this was an explicit user correction against
  an earlier silent-default-to-`gemma3:4b` approach).

### Known gaps (deliberately deferred, not accidental — confirmed with user)
- No chat history / Telegram conversation-context persistence — explicitly
  told **not needed** when offered as a next step.
- No Ollama response streaming (waits for the full reply).
- No Telegram photo/document attachments (the old Dart bridge had both).
- Config stored as plaintext JSON (bot token not encrypted).
- No window chrome control (frameless/opacity/always-on-top from the
  original spec's requirement 3.1).
- No cold-start memory budget or background process-priority tuning
  (requirement 3.2).
- No installer packaging — only `cargo tauri dev` / a `target/debug` exe
  has been run, never `cargo tauri build`.
- Real icons are still placeholder solid-color PNGs generated by a raw PNG
  encoder in this session (`icons/*.png`, `icons/icon.ico`) — swap for real
  artwork before any real distribution.

### Workflow notes specific to the Tauri rewrite
- **Every `cargo build` requires killing the running exe first** — same
  file-lock issue as the old Dart build, just with `noriter-ai.exe` under
  `src-tauri/target/debug/`.
- **This sandbox has no interactive desktop/window station** — `cargo tauri
  dev` compiles and the process launches but exits almost immediately with
  no error (just a benign WebView2 teardown log line), because `tao`/`wry`
  can't paint an actual window here. All real window/tray verification in
  this session was done by the user running the built exe themselves and
  reporting back — that loop (build here, user runs + reports, iterate) is
  the only way to verify UI/tray/window behavior for this project.
- **`dart_ui/build/web/index.html` gets overwritten by `build.sh`** on every
  real build — this session repeatedly swapped in a temporary version with
  a mocked `window.__TAURI__` to unit-test the Dart Wasm UI logic (message
  formatting, panel toggling, worker round-trip) in the Browser pane
  *before* spending a full Rust rebuild + asking the user to re-test. Worth
  continuing this pattern: it caught real bugs (e.g. the innerHTML `.toJS`
  requirement, the `.mjs`/`.wasm` MIME-type issue with Python's
  `http.server`) without needing a user round-trip each time.
- **`dart compile wasm` needs correct `Content-Type` headers to boot in a
  browser** — `.mjs` must serve as `application/javascript`/`text/javascript`
  and `.wasm` as `application/wasm`, or `WebAssembly.compileStreaming`/the
  module `<script>` tag fails silently with no console error captured by
  the tooling used this session. Tauri's own asset server handles this
  correctly; only matters when standalone-testing the built `dart_ui/build/web`
  folder with a throwaway static server.
- **`src-tauri/target/` reached ~4.4GB during this session** — was never
  gitignored until the very end of the session (right before the first
  commit was attempted). Added `src-tauri/target/`, `src-tauri/gen/`,
  `dart_ui/.dart_tool/`, and `dart_ui/build/` to `.gitignore`. If you see a
  huge/slow `git add`/`git status`, check `.gitignore` actually took effect
  (`git status` should not list anything under those paths) before
  investigating further.
- **An earlier attempt to commit/push in this session hit a transient
  failure** (exact error text wasn't preserved — it happened in a part of
  the session that got summarized away before this note was written). The
  user reported their internet connection was fine and asked to retry /
  reset / disconnect+reconnect the `origin` remote. Before doing anything
  destructive to remote config, `git fetch origin` was run standalone and
  returned exit code 0 immediately — i.e. **the connection was actually
  fine by the time this was investigated**, so no remote reset was needed
  and none was performed (`git remote -v` still points at
  `https://github.com/hoonee02/noriter-ai.git`, unchanged). If push
  failures recur, check for the 4.4GB `target/` directory above being
  accidentally staged first (`git add -A` before the gitignore fix would
  have tried to push gigabytes) before assuming it's a real network issue.

---

## Previous session (v0.1.2, Dart/shelf architecture — superseded by the Tauri rewrite above)

### What this session did, in order

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
16. **EXAONE-4.5-33B, Moondream-1.8B, Gemma-4-12B added to the recommended
    list** — EXAONE-4.5-33B is LG's *only* vision-capable EXAONE (no small
    variant exists; pulled via `hf.co/mradermacher/EXAONE-4.5-33B-i1-GGUF:Q2_K`,
    ~10GB, explicitly labeled ⚠ slow on a 6GB-VRAM GPU). Moondream-1.8b is the
    properly hardware-appropriate vision pick (fast, fits comfortably).
    Gemma-4-12b is a newer-generation, similarly-sized upgrade over
    `gemma3:4b` (256K context vs 128K, ~7.6GB vs ~7.2GB download for the
    `gemma4:e2b` edge variant).
17. **Telegram image analysis** — photos sent to the bot are downloaded via
    `getFile` and sent through the same multimodal path as the web chat's
    image attachment, with the same vision-capability pre-check.
18. **Excel (.xlsx) attachment** — new `excel_service.dart` (pure Dart, no
    native deps) converts uploaded bytes to a plain-text table, then reuses
    the exact same text-attachment path as any other file. **PDF was
    explicitly deferred** -- the only viable Dart PDF-text libraries require
    bundling native DLLs alongside the EXE, which breaks the single-file
    distribution model; user chose Excel-only for this scope, revisit PDF
    separately if that tradeoff becomes acceptable later.
19. **Telegram file (document) attachments were being silently dropped** --
    Telegram sends non-photo attachments as a `document` field, completely
    separate from `photo`/`text`/`caption`, and the bridge never checked it.
    An Excel file sent via Telegram got only the bare caption forwarded (no
    file content), producing a confusing empty-response error. Fixed by
    downloading `document` the same way as photos and embedding its content
    like the web chat's file attachment (`.xlsx` via `excelBytesToText()`,
    else UTF-8 text). Also fixed a stale "LM Studio" wording left over from
    before the Ollama swap in `local_agent.dart`'s empty-response error.
20. **Visual request queue** — web chat and Telegram previously called into
    the same `_agent`/`_cancelled` fields with **no serialization** -- a
    latent race where two near-simultaneous requests (either surface) could
    run the agent concurrently and interleave history/broadcast events.
    Fixed with `_runQueued()`: a single `Future`-chained FIFO both entry
    points now go through. Queue state is broadcast as `queueUpdate` and
    rendered as a "📋 Request Queue" panel above the chat (💬 web / ✈️
    telegram badges), visible only when something is waiting/running.
21. **Token count + generation time per reply** — `OnFinalAnswer` now carries
    optional `tokensUsed`/`elapsedMs` (summed/measured across the whole
    turn, including tool-calling iterations). Persisted on `ChatEntry` so it
    survives a reload. Rendered as "N tokens · X.Xs" under each assistant
    message. Verified live: a real reply rendered "1930 tokens · 14.9s".
22. **Context-size "Apply" button** — context size can't change on an
    already-running model without a reload (llama.cpp/Ollama allocate the KV
    cache at load time); the slider previously only applied on the *next*
    Run. New `applyContextSize` WS message reloads the active model
    in-place, but is rejected server-side (via an `error` broadcast) if the
    queue is non-empty or no model is active -- and disabled client-side
    the same way, so it's never even clickable mid-generation.
23. **Timestamps now date-aware** — `HH:mm` for today's messages, `MM/DD
    HH:mm` (`YYYY/MM/DD HH:mm` across a year boundary) for older ones.
    Previously always time-only, ambiguous once history spans multiple days.

---

## ✅ Verified end-to-end on real hardware (updated from earlier draft)

The Ollama backend swap (item 13) was originally shipped **unverified** --
this sandbox had no Ollama install. That has since been confirmed working:
`exaone3.5:7.8b` was pulled and run through the app's Engine panel on the
user's real machine (GTX 1660 / 32GB RAM), and a plain-text chat round-trip
through it produced a correct, coherent reply (confirmed *after* the
message-type widening for image support too, so that refactor didn't
regress ordinary text chat either).

**Image upload → vision model (item 15) is now confirmed working** on the
user's real hardware with `moondream:1.8b` -- it correctly described a real
screenshot's contents. That run also surfaced two follow-up bugs, both
fixed: (a) a tiny vision model's 2K context window was blown by the full
tool-calling system prompt on a second image request, causing prompt-echo/
gibberish -- fixed by using a short direct prompt + dropping prior history
for image turns; (b) sending an image while a non-vision model was loaded
surfaced Ollama's raw rejection JSON -- fixed with an upfront
`modelSupportsVision()` check (see BUGFIXES.md for both).

**Still not independently verified in this sandbox** (no way to trigger
them here, but each is a small, low-risk code path):
- Telegram *document* (file/Excel) attachment end-to-end against a live
  Telegram chat -- verified via `dart analyze` + a standalone script that
  fed a real in-memory .xlsx through `excelBytesToText()` directly, and the
  app boots/runs the Telegram bridge without error, but no actual Telegram
  message was sent in this environment.
- The request queue actually visibly queuing multiple entries (item 20) --
  confirmed it doesn't crash the server, but reproducing genuine queue
  depth > 1 needs two real overlapping requests, which wasn't set up here.
- Context-size Apply button's *enabled* state end-to-end (confirmed
  correctly *disabled* when no model is running; the enabled+reload path
  wasn't exercised because the Ollama model list wasn't populating in this
  session's browser test for unrelated reasons -- worth a quick manual
  check: load a model, confirm Apply enables, click it, confirm the model
  reloads and `engineStatus` cycles through `starting` → `ready`).

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
- **PDF support was deferred, not rejected** -- see item 18. If a native-DLL
  bundling approach becomes acceptable (or a pure-Dart option shows up),
  `pdf_text_extraction` (xpdf-based FFI bindings) was the one viable
  candidate found; revisit if the user asks for PDF again.
- **`excel: ^4.0.6` was added to `pubspec.yaml` by the user directly**
  (outside this agent's edits) before the Excel feature was implemented --
  worth knowing in case the dependency's origin is confusing later; it's
  now genuinely used by `excel_service.dart`.
- **The request queue is a single global FIFO**, not per-chat-session --
  fine for this single-user desktop app, but would need rethinking if
  multi-user/multi-workspace support is ever added.
- **EXAONE-4.5-33B is genuinely slow** on the reference hardware (6GB VRAM +
  32GB RAM) -- it's intentionally included anyway per explicit user request
  for an EXAONE-specific vision option, with a ⚠ warning in its label. Don't
  "fix" this by removing it without checking with the user first.

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
  compile-time checking of the JS portion. `javascript_tool` (direct
  `document.getElementById(...).click()`) turned out more reliable than
  `computer` clicks by coordinate/ref for this app's UI in a later session.
- **Be careful with `cd ..` in Bash** — the working directory is a git
  worktree nested several levels under the user's real OneDrive folder;
  more than once a `cd ..` chain (e.g. from `dart_platform/` expecting one
  level up) overshot into the OneDrive root itself, which is full of the
  user's personal files. No harm was done (only ever ran read-only `git
  status` there before catching it and it auto-recovers), but prefer
  absolute paths or `git -C "<repo path>"` over relative `cd ..` chains.
- **The user often has their own instance of the app running in parallel**
  (multiple sessions this project saw a live Ollama pull or chat already in
  progress on a "fresh" test launch) -- if `tasklist | grep noriter` shows
  a running exe you didn't start, ask before killing it rather than
  assuming it's a stale leftover.
- **`.noriter-ai/chat-history.json` and `.noriter-ai/last-engine.json` are
  session state, not source** — don't commit changes to them unless the
  user specifically asks. They get modified just by running the app.
