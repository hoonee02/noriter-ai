# Noriter AI

Local AI Agent inside VSCode powered by LM Studio.

## Features
- Sidebar Chat View with Local LLM.
- Workspace tools (Read/Write files, run terminal commands).
- Theme-responsive design with collapsible agent thoughts.
- Conversation history is persisted per workspace and restored on reopen.
- Recent conversation turns are automatically sent back to LM Studio as context for follow-up prompts.
- Agent memory space is persisted in workspace at `.noriter-ai/agent-memory.md` and can be managed with memory tools (`saveMemory`, `getMemory`, `listMemoryKeys`, `deleteMemory`).
- A "메모리" button in the extension sidebar opens the memory markdown file for direct user editing and review.
- A "목표" button opens `.noriter-ai/agent-goal.md`, and its content is injected into the agent system prompt so users can directly control the agent's objective.
- A "텔레그램" button opens a dedicated Telegram integration window where users can save bot settings and send a test message.
- Agent tool `sendTelegramMessage` can send runtime updates to Telegram when needed.
- Telegram integration window includes "Enable Telegram chat bridge" so users can chat with the AI agent directly from the configured Telegram chat.

### Telegram bridge commands
- `/start`: show quick-start guidance and available commands.
- `/reset`: clear Telegram-side conversation context for the current chat.
- `/status`: show bridge state, context usage, and current goal summary.
- `/goal`: show current goal markdown content summary.
- `/goal <text>`: update agent goal remotely from Telegram.

### Telegram troubleshooting
- If you get `Bad Request: chat not found`, open the Telegram integration window and click `Find Chat IDs`.
- Before clicking it, send at least one message to your bot (or add bot to a group/channel and post a message) so `getUpdates` can discover the chat.
