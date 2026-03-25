# Logging Best Practices

This guide defines logging conventions for Symphony so Codex can diagnose failures quickly.

## Goals

- Make logs searchable by issue and session.
- Capture enough execution context to identify root cause without reruns.
- Keep messages stable so dashboards/alerts are reliable.

## Required Context Fields

When logging issue-related work, include both identifiers:

- `issue_id`: Linear internal UUID (stable foreign key).
- `issue_identifier`: human ticket key (for example `MT-620`).

When logging Codex execution lifecycle events, include:

- `session_id`: combined Codex thread/turn identifier.

## Message Design

- Use explicit `key=value` pairs in message text for high-signal fields.
- Prefer deterministic wording for recurring lifecycle events.
- Include the action outcome (`completed`, `failed`, `retrying`) and the reason/error when available.
- Avoid logging large payloads unless required for debugging.

## Scope Guidance

- `AgentRunner`: log start/completion/failure with issue context, plus `session_id` when known.
- `Orchestrator`: log dispatch, retry, terminal/non-active transitions, and worker exits with issue context. Include `session_id` whenever running-entry data has it.
- `Codex.AppServer`: log session start/completion/error with issue context and `session_id`.

## Checklist For New Logs

- Is this event tied to a Linear issue? Include `issue_id` and `issue_identifier`.
- Is this event tied to a Codex session? Include `session_id`.
- Is the failure reason present and concise?
- Is the message format consistent with existing lifecycle logs?

## Session Transcript Logs

Separate from the Elixir Logger output above, Symphony writes raw protocol transcripts for every
agent session to `{logs-root}/log/session-logs/`. These are JSONL files containing every message
sent to and received from the agent process, with timestamps and direction indicators.

**When to use:** Session transcripts are useful for diagnosing protocol-level issues — malformed
JSON-RPC messages, unexpected event ordering, tool call/response mismatches, or silent failures
that don't surface in the lifecycle Logger output.

**Relationship to Logger output:** Logger captures high-level lifecycle events (session started,
completed, failed) with structured context fields. Session transcripts capture the full raw
protocol exchange. Use Logger output for operational monitoring; use session transcripts for
deep debugging.

**Implementation:** All session transcript logging goes through `SymphonyElixir.SessionLogger`.
Both the Codex and Claude adapters use this module. Do not add ad-hoc file-based session logging
in adapter code.

**Always on:** Session transcripts are written for every session. No configuration flag is needed.

**Cleanup:** Remove `log/session-logs/` when transcript files are no longer needed. See the
"Debug Session Logs" section in `README.md` for details.
