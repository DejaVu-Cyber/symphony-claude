# Session Debug Logging — Spec & Plan

## Goal

Capture raw protocol transcripts for every agent session (Codex and Claude) to
JSONL files under `{logs-root}/session-logs/` for post-hoc debugging.

## Design

### New module: `SymphonyElixir.SessionLogger`

Location: `lib/symphony_elixir/session_logger.ex`

Public API:

```elixir
@spec open(atom(), map(), String.t()) :: {:ok, handle()} | {:error, term()}
@spec log_sent(handle(), String.t()) :: :ok
@spec log_received(handle(), String.t()) :: :ok
@spec close(handle()) :: :ok
```

- `open/3` takes adapter name (`:codex` | `:claude`), issue map, and session_id.
  Creates `{logs-root}/session-logs/{adapter}_{issue_identifier}_{session_id}_{timestamp}.jsonl`.
  Ensures the directory exists via `File.mkdir_p/1`.
  Returns a file device handle.
- `log_sent/2` and `log_received/2` write one JSONL line:
  `{"ts":"2026-03-25T10:00:00.123Z","dir":"sent"|"recv","data":"..."}`
  where `data` is the raw string exactly as sent/received.
- `close/1` flushes and closes the file device.
- All operations are best-effort: failures are logged via `Logger.warning` and
  swallowed so they never break a session.

### Codex integration (`codex/app_server.ex`)

- `run_turn/4`: after `start_turn` succeeds, call `SessionLogger.open(:codex, issue, session_id)`.
  Store handle as `session_log` in local scope (passed through receive_loop).
- `send_message/2`: call `SessionLogger.log_sent(handle, json)` before port write.
- `receive_loop/6`: call `SessionLogger.log_received(handle, raw_line)` for each
  complete line before parsing.
- On turn completion/failure/timeout: call `SessionLogger.close(handle)`.

### Claude integration (`agent/claude_adapter.ex`)

- `start_session/2`: after port starts, call `SessionLogger.open(:claude, issue, session_id)`.
  Store handle in session map as `session_log`.
- Prompt: call `SessionLogger.log_sent(handle, prompt_content)` when writing prompt.
- Port data handler: call `SessionLogger.log_received(handle, raw_line)` for each
  line before parsing.
- Session end: call `SessionLogger.close(handle)` on turn_completed, turn_failed,
  or port exit.

### Session map change

Both adapters add `session_log: handle | nil` to their session/state maps. `nil`
when open fails (graceful degradation).

## Documentation updates

### `elixir/README.md`

New section "Debug Session Logs" after "Configuration":
- All agent sessions are logged to `{logs-root}/session-logs/` as JSONL
- Filename format: `{adapter}_{issue-identifier}_{session-id}_{timestamp}.jsonl`
- Example JSONL line
- `--logs-root` controls the parent directory
- Cleanup: `rm -rf log/session-logs/`

### `elixir/AGENTS.md`

New bullet under "Codebase-Specific Conventions":
- `SessionLogger` is the single entry point for session transcript logging
- Both adapters use it; don't add ad-hoc file logging elsewhere

### `elixir/docs/logging.md`

New section "Session Transcript Logs":
- Distinguishes transcripts (raw protocol) from Logger output (lifecycle events)
- Directory, format, always-on, cleanup guidance

### `.gitignore`

No changes needed — `log/` is already ignored.

## Implementation steps

1. Create `lib/symphony_elixir/session_logger.ex` with the API above
2. Integrate into `codex/app_server.ex` — thread handle through receive_loop
3. Integrate into `agent/claude_adapter.ex` — store handle in session map
4. Update `elixir/README.md` with new section
5. Update `elixir/AGENTS.md` with convention note
6. Update `elixir/docs/logging.md` with new section
7. Run `make all` to verify nothing breaks
