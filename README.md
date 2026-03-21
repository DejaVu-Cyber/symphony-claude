# Symphony With Claude and Codex Integration

Symphony turns project work into isolated, autonomous implementation runs, allowing teams to manage
work instead of supervising coding agents.

This fork extends the original Symphony reference implementation with multi-runtime agent support.
The Elixir implementation supports both Codex and Claude-compatible runtimes, including Claude CLI
setups routed through Anthropic-compatible providers such as MiniMax.

[![Symphony demo video preview](.github/media/symphony-demo-poster.jpg)](.github/media/symphony-demo.mp4)

_In this [demo video](.github/media/symphony-demo.mp4), Symphony monitors a Linear board for work and spawns agents to handle the tasks. The agents complete the tasks and provide proof of work: CI status, PR review feedback, complexity analysis, and walkthrough videos. When accepted, the agents land the PR safely. Engineers do not need to supervise Codex; they can manage the work at a higher level._

> [!WARNING]
> Symphony is a low-key engineering preview for testing in trusted environments.

## Fork Changes

Compared with the original upstream Symphony repository, this fork adds and documents:

- dual runtime support for both `codex` and `claude`
- Claude CLI orchestration in the Elixir implementation
- Claude-compatible workflow configuration via `agent.adapter: claude`
- support for Anthropic-compatible Claude backends such as MiniMax
- Claude-aware stall timeout selection during orchestration
- Claude token accounting and rate-limit handling in the orchestrator
- dashboard runtime labeling for Codex, Claude, and Claude-via-MiniMax
- dashboard error visibility improvements and live estimated token reporting for Claude sessions
- normalized adapter/event plumbing so non-Codex runtimes can run through the same orchestration loop

## Workflow Changes

The main workflow-level change from upstream is that this fork is no longer Codex-only.

- `agent.adapter` can now be set to `codex` or `claude`
- `claude:` is now a first-class config block alongside `codex:`
- the checked-in example workflow in this fork currently defaults to Claude

The concrete `WORKFLOW.md` additions that make Claude integration work are:

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
    - Glob
    - Grep
  max_turns: 30
  api_key: $ANTHROPIC_API_KEY
  turn_timeout_ms: 3600000
  stall_timeout_ms: 300000
```

Compared with the original Codex-only workflow shape, the key additions are:

- `agent.adapter: claude`
- the entire `claude:` config block
- Claude-specific runtime controls such as `permission_mode`, `allowed_tools`, and timeout values

If you route Claude through an Anthropic-compatible provider such as MiniMax, the effective model
can come from environment variables like `ANTHROPIC_BASE_URL` and `ANTHROPIC_MODEL`, even if the
workflow still contains a `claude.model` value.

The detailed setup and the fuller Elixir-specific configuration notes live in
[elixir/README.md](elixir/README.md).

## Running Symphony

### Requirements

Symphony works best in codebases that have adopted
[harness engineering](https://openai.com/index/harness-engineering/). Symphony is the next step --
moving from managing coding agents to managing work that needs to get done.

### Option 1. Make your own

Tell your favorite coding agent to build Symphony in a programming language of your choice:

> Implement Symphony according to the following spec:
> https://github.com/openai/symphony/blob/main/SPEC.md

### Option 2. Use our experimental reference implementation

Check out [elixir/README.md](elixir/README.md) for instructions on how to set up your environment
and run the Elixir-based Symphony implementation. This fork supports both `codex` and `claude`
adapters via `WORKFLOW.md`. You can also ask your favorite coding agent to help with the setup:

> Set up Symphony for my repository based on
> https://github.com/openai/symphony/blob/main/elixir/README.md

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).
