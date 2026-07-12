# Noriter AI — Bug Fix Log

Chronological record of bugs found and fixed during development, kept alongside
[CHANGELOG.md](CHANGELOG.md) (features/releases) and [SPEC.md](SPEC.md) (architecture).

---

## Telegram file (document) attachments silently dropped, producing an empty response
**Symptom:** Sending an Excel file to the Telegram bot with a caption like "이건 어떤 파일인지 설명" replied with `Error: Received empty response from local model. Make sure the model is loaded and running in LM Studio.`
**Root cause:** Telegram sends non-photo file attachments as a `document` field on the message, completely separate from `photo`. `telegram_bridge.dart` only ever checked `text`/`caption`/`photo` -- it silently ignored `document` entirely, so the actual file content was thrown away and only the bare caption text ("이건 어떤 파일인지 설명") reached the model with no file content to work with, in some cases returning a genuinely empty completion. Separately, the error message itself was stale -- it referenced "LM Studio", a leftover from before the Ollama backend swap (v0.1.0).
**Fix:** `telegram_bridge.dart` now detects `message.document`, downloads it via `getFile`, and embeds its content the same way the web chat's file attachment does: `.xlsx` is parsed with `excelBytesToText()`, everything else is decoded as UTF-8 text, both truncated at 8000 characters. The download logic for photos and documents was unified into a single `_downloadFile()` helper. Also updated the stale "LM Studio" error message in `local_agent.dart` to be backend-agnostic. (`telegram_bridge.dart`, `local_agent.dart`)

---

## Image analysis regurgitating prompt fragments / gibberish with small vision models
**Symptom:** With `moondream:1.8b` loaded, the first image analysis in a session worked correctly, but a later image request in the same conversation returned a fragment of the app's own system prompt (`"...and not use any tools for analysis unless explicitly requested...Action Input: {}"`) or outright gibberish (`가장나치로 파이썬의 경로들이 없다.`) instead of describing the image.
**Root cause:** Vision models tend to be much smaller than text models -- `moondream:1.8b` has only a **2K-token context window** by default. The app was sending the *full* tool-calling system prompt (tool list, ReAct Thought/Action/Observation format, worked example) plus the entire prior conversation history on every request, including image ones. None of that scaffolding is needed for a simple "describe this image" task, and it was blowing straight through the tiny context budget, causing the model to lose coherence and echo back its own instructions or hallucinate.
**Fix:** `LocalAgent.run()` now uses a short, direct system prompt for image requests (no tool list, no ReAct format) and drops prior conversation history entirely for that turn, leaving the model's limited context budget almost entirely for the image + question. The full tool-calling prompt (extracted into `_buildToolAgentSystemPrompt()`) is unchanged for ordinary text messages. (`local_agent.dart`)

---

## Raw JSON API error when attaching an image to a non-vision model
**Symptom:** Attaching an image and sending it produced a raw error bubble: `API Error: {"error":{"message":"{...\"Multimodal data provided, but model does not support multimodal requests.\"...}"}}`.
**Root cause:** Not a bug in the strict sense -- the image-attachment feature (see CHANGELOG v0.1.1) sends the image to whatever model is currently loaded, but most models (including EXAONE 3.5, Llama 3.2, Phi-3, and Gemma 3 below 4B) are text-only. Ollama correctly rejects the request; the app just surfaced that rejection as an unhelpful raw JSON blob instead of explaining what happened.
**Fix:** Added `OllamaEngineManager.modelSupportsVision(tag)`, which checks Ollama's `/api/show` `capabilities` field (with a name-based fallback for older Ollama versions lacking that field). `server.dart`'s `sendMessage` handler now checks this *before* sending an image, and if the active model can't handle it, shows a clear message ("The current model does not support images. Switch to a vision-capable model, e.g. gemma3:4b.") instead of hitting the chat API and relaying its raw error. (`ollama_engine_manager.dart`, `server.dart`)

---

## Fragment/incomplete generations ("Thought: I", "Okay, I understand. I'm ready to") shown as the final answer
**Symptom:** Even after fixing the missing `max_tokens` (below), some turns still produced a broken half-sentence as the visible reply -- e.g. the entire response was just `Thought: I`.
**Root cause:** Two layers. (1) The underlying local model (typically a small ~0.5B-parameter model) sometimes stops generating almost immediately when the prompt is large -- a long system prompt plus tool list plus accumulated Korean conversation history can overwhelm a small model and cause it to emit a near-empty completion or hit its own stop condition early; this is a genuine model-capability limitation, not something the app can fully paper over. (2) A real code bug compounded it: any model output that didn't contain an explicit `Action:` or `Final Answer:` marker was unconditionally treated as if it *were* the final answer and shown to the user as-is, even when it was obviously just a truncated stub like `Thought: I`.
**Fix:** `LocalAgent.run()` now detects likely-truncated fragments (a bare `Thought:` stub, or fewer than 5 words with no Action/Final Answer) and, instead of surfacing them as the answer, feeds an Observation back asking the model to continue or give a complete `Final Answer:` (retried up to twice before giving up and showing whatever it has). (`local_agent.dart`)
**Also recommended:** if this keeps happening on a given model, switch to a larger one from the Engine panel (e.g. Llama-3.2-1B-Instruct or Phi-3-mini-4k instead of Qwen2.5-0.5B) -- small models are the most prone to this under the ReAct prompt's size.

---

## Response cut off mid-sentence ("The file", "Okay, I understand. I'm ready to")
**Symptom:** Final answers frequently ended abruptly, especially for longer responses (e.g. summarizing an attached file).
**Root cause:** The `/chat/completions` request to llama-server never set `max_tokens`, so llama-server's OpenAI-compat layer fell back to a small default completion length and truncated every response.
**Fix:** `local_agent.dart` now sends `max_tokens: 2048` on every request. (`local_agent.dart`)

---

## Attachment content permanently bloating conversation context
**Symptom:** After attaching a file once, later unrelated messages started producing confused, generic replies ("I apologize... still learning to interact with files").
**Root cause:** The full attached-file text was persisted into `.noriter-ai/chat-history.json`, and every future turn resends the entire history as LLM context — so the large attachment kept being re-sent on every later message, compounding with each new attachment and overwhelming small local models' context windows.
**Fix:** The full attachment body is now sent to the agent only for the turn it was attached in. What's persisted to history (and thus resent later) is a short placeholder noting the filename and size. (`server.dart`)

---

## Attached-file requests answered with a generic apology instead of processing the file
**Symptom:** Asking the agent to "정리해줘" (clean up/organize) an attached file returned "You are absolutely right! I apologize for the error... Could you provide the correct file path?" instead of using the file's content.
**Root cause:** The attachment's content was inlined into the chat message, but nothing told the model it didn't need (and couldn't) `readFile`/`writeFile` it from the workspace — the file was never written to disk, only embedded in the prompt. The model kept trying to look it up as a workspace file and failing.
**Fix:** The composed attachment message and the agent's system prompt both now explicitly state the file is not in the workspace and its content is already inlined, so tools must not be used to access it. (`server.dart`, `local_agent.dart`)

---

## Malformed tool JSON killing the whole agent turn
**Symptom:** "Failed to parse tool arguments" errors that ended the turn outright, requiring the user to manually resend the same message.
**Root cause:** Small models sometimes emit `Action Input` as JS-style string concatenation (`"a\n" + "b\n" + "c"`) instead of one JSON string. `jsonDecode` fails on that, and the old code called `progress.onError` and returned immediately.
**Fix:** Added a repair step that strips `"..." + "..."` glue before giving up, and if parsing still fails, feeds an Observation back to the model asking it to re-emit valid JSON so the ReAct loop can self-correct instead of dying. The system prompt also now explicitly forbids string concatenation in `Action Input`. (`local_agent.dart`)

---

## Telegram bridge always replying "Done." regardless of the actual answer
**Symptom:** Every Telegram reply was the literal text "Done.", never the model's real answer.
**Root cause:** `onFinalAnswer`/`onError` are fire-and-forget callbacks — `LocalAgent.run()` invokes them without awaiting and returns immediately, before the callback's async body (history append, broadcast, `completer.complete`) finished. A fallback `completer.complete('Done.')` placed right after `await _agent.run(...)` always won that race.
**Fix:** Await `completer.future` directly (with a 5s timeout fallback) instead of racing it with an unconditional completion. (`server.dart`)

---

## Telegram messages read but never replied to
**Symptom:** Sent messages were consumed by `getUpdates` (the offset advanced) but the bot never sent a reply.
**Root cause:** The local config's `chatId` was set to the bot's own numeric ID (the token's numeric prefix) instead of the human user's chat ID, so every real incoming message failed the `chat.id` filter and was silently dropped.
**Fix:** `TelegramBridge` now auto-binds to whichever chat sends the first message when no chat ID is configured, and persists the discovered ID. Any future mismatch now surfaces a clear status message instead of failing silently. (`telegram_bridge.dart`, `server.dart`)

---

## Raw `exceed_context_size_error` JSON shown to the user
**Symptom:** Long conversations eventually surfaced a raw HTTP 400 JSON blob (`exceed_context_size_error`) instead of a usable response.
**Root cause:** No handling existed for llama-server's context-overflow error; the agent treated it like any other HTTP error and aborted the turn.
**Fix:** On this specific error, the agent now trims the oldest context messages and retries automatically. If trimming can't bring the conversation under the limit, it shows a clear message suggesting a new chat or a larger context size instead of the raw error. (`local_agent.dart`)
