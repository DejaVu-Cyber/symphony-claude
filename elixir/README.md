# Symphony Elixir With Claude and Codex Support

This directory contains the current Elixir/OTP implementation of Symphony, based on
[`SPEC.md`](../SPEC.md) at the repository root.

> [!WARNING]
> Symphony Elixir is prototype software intended for evaluation only and is presented as-is.
> We recommend implementing your own hardened version based on `SPEC.md`.

## What's Different In This Fork

Relative to the original upstream Symphony reference repository, this Elixir fork now includes:

- `agent.adapter` workflow selection for both `codex` and `claude`
- Claude CLI adapter support in addition to Codex App Server support
- Anthropic-compatible Claude backend routing, including MiniMax-style setups
- Claude-aware stall timeout, token accounting, and rate-limit handling
- terminal dashboard runtime labeling for Codex, Claude, and Claude-via-MiniMax
- full retry error rendering in the dashboard instead of truncated backoff errors
- live estimated token counts for Claude while a turn is still streaming

## Screenshot

![Symphony Elixir screenshot](../.github/media/elixir-screenshot.png)

## How it works

1. Polls Linear for candidate work
2. Creates a workspace per issue
3. Launches the configured agent runtime inside the workspace
4. Sends a workflow prompt to that runtime
5. Keeps the agent working on the issue until the work is done

This fork supports two agent adapters:

- `codex` via Codex App Server mode
- `claude` via the Claude CLI, including Anthropic-compatible backends such as MiniMax when the
  relevant environment overrides are provided

During app-server sessions, Symphony also serves a client-side `linear_graphql` tool so that repo
skills can make raw Linear GraphQL calls.

If a claimed issue moves to a terminal state (`Done`, `Closed`, `Cancelled`, or `Duplicate`),
Symphony stops the active agent for that issue and cleans up matching workspaces.

## How to use it

1. Make sure your codebase is set up to work well with agents: see
   [Harness engineering](https://openai.com/index/harness-engineering/).
2. Get a new personal token in Linear via Settings → Security & access → Personal API keys, and
   set it as the `LINEAR_API_KEY` environment variable.
3. Copy this directory's `WORKFLOW.md` to your repo.
4. Optionally copy the `commit`, `push`, `pull`, `land`, and `linear` skills to your repo.
   - The `linear` skill expects Symphony's `linear_graphql` app-server tool for raw Linear GraphQL
     operations such as comment editing or upload flows.
5. Customize the copied `WORKFLOW.md` file for your project.
   - To get your project's slug, right-click the project and copy its URL. The slug is part of the
     URL.
   - When creating a workflow based on this repo, note that it depends on non-standard Linear
     issue statuses: "Rework", "Human Review", and "Merging". You can customize them in
     Team Settings → Workflow in Linear.
6. Follow the instructions below to install the required runtime dependencies and start the service.

## Prerequisites

We recommend using [mise](https://mise.jdx.dev/) to manage Elixir/Erlang versions.

```bash
mise install
mise exec -- elixir --version
```

## Run

```bash
git clone https://github.com/openai/symphony
cd symphony/elixir
mise trust
mise install
mise exec -- mix setup
mise exec -- mix build
mise exec -- ./bin/symphony ./WORKFLOW.md
```

## Configuration

Pass a custom workflow file path to `./bin/symphony` when starting the service:

```bash
./bin/symphony /path/to/custom/WORKFLOW.md
```

If no path is passed, Symphony defaults to `./WORKFLOW.md`.

Optional flags:

- `--logs-root` tells Symphony to write logs under a different directory (default: `./log`)
- `--port` also starts the Phoenix observability service (default: disabled)

The `WORKFLOW.md` file uses YAML front matter for configuration, plus a Markdown body used as the
agent session prompt.

Minimal example:

```md
---
tracker:
  kind: linear
  project_slug: "..."
workspace:
  root: ~/code/workspaces
hooks:
  after_create: |
    git clone git@github.com:your-org/your-repo.git .
agent:
  adapter: codex
  max_concurrent_agents: 10
  max_turns: 20
codex:
  command: codex app-server
---

You are working on a Linear issue {{ issue.identifier }}.

Title: {{ issue.title }} Body: {{ issue.description }}
```

Upstream workflow users should note these fork-specific changes:

- the `agent:` block now accepts `adapter: codex` or `adapter: claude`
- `claude:` is a first-class config block alongside `codex:`
- the shipped example `WORKFLOW.md` in this fork defaults to Claude
- the dashboard now reads runtime/provider details from both workflow config and environment
- the top-level [README.md](../README.md) now quotes the exact `WORKFLOW.md` additions that enable
  Claude integration in this fork

Notes:

- If a value is missing, defaults are used.
- `agent.adapter` selects the runtime. Supported values are `codex` and `claude`.
- Safer Codex defaults are used when policy fields are omitted:
  - `codex.approval_policy` defaults to `{"reject":{"sandbox_approval":true,"rules":true,"mcp_elicitations":true}}`
  - `codex.thread_sandbox` defaults to `workspace-write`
  - `codex.turn_sandbox_policy` defaults to a `workspaceWrite` policy rooted at the current issue workspace
- Claude-specific settings live under the `claude:` block. Typical fields include `command`,
  `model`, `permission_mode`, `allowed_tools`, `turn_timeout_ms`, and `stall_timeout_ms`.
- A Claude workflow typically looks like this:

```yaml
agent:
  adapter: claude
claude:
  command: claude
  model: claude-sonnet-4-6
  permission_mode: bypassPermissions
  allowed_tools:
    - Bash
    - Read
    - Write
    - Edit
```

- If you route Claude through an Anthropic-compatible provider such as MiniMax, the effective model
  can come from environment variables like `ANTHROPIC_BASE_URL` and `ANTHROPIC_MODEL` rather than
  the literal `claude.model` string in the workflow.
- Supported `codex.approval_policy` values depend on the targeted Codex app-server version. In the current local Codex schema, string values include `untrusted`, `on-failure`, `on-request`, and `never`, and object-form `reject` is also supported.
- Supported `codex.thread_sandbox` values: `read-only`, `workspace-write`, `danger-full-access`.
- When `codex.turn_sandbox_policy` is set explicitly, Symphony passes the map through to Codex
  unchanged. Compatibility then depends on the targeted Codex app-server version rather than local
  Symphony validation.
- `agent.max_turns` caps how many back-to-back agent turns Symphony will run in a single agent
  invocation when a turn completes normally but the issue is still in an active state. Default: `20`.
- If the Markdown body is blank, Symphony uses a default prompt template that includes the issue
  identifier, title, and body.
- Use `hooks.after_create` to bootstrap a fresh workspace. For a Git-backed repo, you can run
  `git clone ... .` there, along with any other setup commands you need.
- If a hook needs `mise exec` inside a freshly cloned workspace, trust the repo config and fetch
  the project dependencies in `hooks.after_create` before invoking `mise` later from other hooks.
- `tracker.api_key` reads from `LINEAR_API_KEY` when unset or when value is `$LINEAR_API_KEY`.
- For path values, `~` is expanded to the home directory.
- For env-backed path values, use `$VAR`. `workspace.root` resolves `$VAR` before path handling,
  while `codex.command` stays a shell command string and any `$VAR` expansion there happens in the
  launched shell.

```yaml
tracker:
  api_key: $LINEAR_API_KEY
workspace:
  root: $SYMPHONY_WORKSPACE_ROOT
hooks:
  after_create: |
    git clone --depth 1 "$SOURCE_REPO_URL" .
codex:
  command: "$CODEX_BIN app-server --model gpt-5.3-codex"
```

- If `WORKFLOW.md` is missing or has invalid YAML at startup, Symphony does not boot.
- If a later reload fails, Symphony keeps running with the last known good workflow and logs the
  reload error until the file is fixed.
- `server.port` or CLI `--port` enables the optional Phoenix LiveView dashboard and JSON API at
  `/`, `/api/v1/state`, `/api/v1/<issue_identifier>`, and `/api/v1/refresh`.

## Debug Session Logs

Every agent session (Codex and Claude) is automatically logged to
`{logs-root}/log/session-logs/` as a JSONL transcript file. Each file captures every raw message
sent to and received from the agent process, making it straightforward to diagnose protocol-level
issues after the fact.

**Filename format:** `{adapter}_{issue-identifier}_{session-id}_{timestamp}.jsonl`

For example: `codex_MT-620_thread1-turn3_20260325T100000.jsonl`

**Each line is a JSON object:**

```json
{"ts":"2026-03-25T10:00:00.123Z","dir":"sent","data":"{\"method\":\"turn/start\",...}"}
{"ts":"2026-03-25T10:00:01.456Z","dir":"recv","data":"{\"method\":\"turn/completed\",...}"}
```

- `ts`: UTC timestamp of the log entry
- `dir`: `sent` for messages to the agent, `recv` for messages from the agent
- `data`: the raw string exactly as transmitted

The `--logs-root` flag controls the parent directory. With the default log root, session logs live
at `./log/session-logs/`.

**Cleanup:** Session logs can grow during extended debugging. Remove them when no longer needed:

```bash
rm -rf log/session-logs/
```

Or, if using a custom logs root:

```bash
rm -rf /your/logs-root/log/session-logs/
```

## Web dashboard

The observability UI now runs on a minimal Phoenix stack:

- LiveView for the dashboard at `/`
- JSON API for operational debugging under `/api/v1/*`
- Bandit as the HTTP server
- Phoenix dependency static assets for the LiveView client bootstrap

## Project Layout

- `lib/`: application code and Mix tasks
- `test/`: ExUnit coverage for runtime behavior
- `WORKFLOW.md`: in-repo workflow contract used by local runs
- `../.codex/`: repository-local agent skills and setup helpers

## Testing

```bash
make all
```

Run the real external end-to-end test only when you want Symphony to create disposable Linear
resources and launch a real agent session:

```bash
cd elixir
export LINEAR_API_KEY=...
make e2e
```

Optional environment variables:

- `SYMPHONY_LIVE_LINEAR_TEAM_KEY` defaults to `SYME2E`
- `SYMPHONY_LIVE_SSH_WORKER_HOSTS` uses those SSH hosts when set, as a comma-separated list

`make e2e` runs two live scenarios:
- one with a local worker
- one with SSH workers

If `SYMPHONY_LIVE_SSH_WORKER_HOSTS` is unset, the SSH scenario uses `docker compose` to start two
disposable SSH workers on `localhost:<port>`. The live test generates a temporary SSH keypair,
mounts the host `~/.codex/auth.json` into each worker, verifies that Symphony can talk to them
over real SSH, then runs the same orchestration flow against those worker addresses. This keeps
the transport representative without depending on long-lived external machines.

Set `SYMPHONY_LIVE_SSH_WORKER_HOSTS` if you want `make e2e` to target real SSH hosts instead.

The live test creates a temporary Linear project and issue, writes a temporary `WORKFLOW.md`, runs
a real agent turn, verifies the workspace side effect, requires the configured runtime to comment on
and close the Linear issue, then marks the project completed so the run remains visible in Linear.

## FAQ

### Why Elixir?

Elixir is built on Erlang/BEAM/OTP, which is great for supervising long-running processes. It has an
active ecosystem of tools and libraries. It also supports hot code reloading without stopping
actively running subagents, which is very useful during development.

### What's the easiest way to set this up for my own codebase?

Launch your preferred agent in your repo, give it the URL to the Symphony repo, and ask it to set
things up for you. If you are using this fork specifically, mention whether you want the generated
workflow to target `codex` or `claude`.

## License

This project is licensed under the [Apache License 2.0](../LICENSE).
