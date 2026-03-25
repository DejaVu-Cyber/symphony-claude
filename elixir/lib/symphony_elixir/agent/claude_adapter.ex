defmodule SymphonyElixir.Agent.ClaudeAdapter do
  @moduledoc """
  Claude Code adapter for Symphony.

  This adapter integrates with Claude Code CLI using the same approach
  as the TypeScript implementation:
  - Spawns `bash -lc "claude --print --output-format stream-json ..."`
  - Writes prompt to temp file and redirects via stdin
  - Parses line-delimited JSON events from stdout
  - Extracts session_id, token usage, rate limits from events
  """

  require Logger

  alias SymphonyElixir.{Agent.Behaviour, Agent.Event, Config, PathSafety, SessionLogger}

  @behaviour Behaviour

  @max_line_bytes 10 * 1024 * 1024

  @impl true
  def start_session(workspace, opts \\ []) do
    worker_host = Keyword.get(opts, :worker_host)

    with {:ok, validated_workspace} <- validate_workspace(workspace, worker_host),
         {:ok, config} <- get_runtime_config(validated_workspace) do
      {:ok,
       %{
         workspace: validated_workspace,
         config: config,
         worker_host: worker_host,
         pid: nil,
         port: nil,
         session_id: nil
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def run_turn(session, prompt, issue, opts \\ []) do
    on_message = Keyword.get(opts, :on_message, fn _ -> :ok end)
    config = session.config

    prompt_file = write_prompt_file(prompt)
    command = build_command(config, prompt_file)

    Logger.info("Starting Claude Code session for #{issue_context(issue)} workspace=#{session.workspace}")

    env = build_env(config)
    cwd = if session.worker_host, do: session.workspace, else: session.workspace

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(System.find_executable("bash"))},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: [~c"-lc", String.to_charlist(command)],
          cd: String.to_charlist(cwd),
          env: env,
          line: @max_line_bytes
        ]
      )

    os_pid =
      case :erlang.port_info(port, :os_pid) do
        {:os_pid, pid} -> to_string(pid)
        _ -> nil
      end

    session_id = nil
    turn_id = to_string(System.system_time(:millisecond))

    session_log =
      case SessionLogger.open(:claude, issue, turn_id) do
        {:ok, handle} -> handle
        {:error, _} -> nil
      end

    Process.put(:session_log, session_log)
    SessionLogger.log_sent(session_log, prompt)

    state = %{
      session: %{session | port: port, pid: os_pid},
      issue: issue,
      on_message: on_message,
      session_id: session_id,
      turn_id: turn_id,
      done: false,
      stall_timeout_ms: config.stall_timeout_ms
    }

    send_initial_event(state, :session_started)

    result =
      try do
        await_completion(state)
      after
        SessionLogger.close(session_log)
        Process.delete(:session_log)
        Port.close(port)
        File.rm(prompt_file)
      end

    case result do
      {:ok, result} ->
        {:ok,
         %{
           session_id: result.session_id || session_id,
           thread_id: nil,
           turn_id: turn_id
         }}

      {:error, reason} ->
        Logger.warning("Claude Code session failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stop_session(session) do
    if session.port && is_port(session.port) do
      Port.close(session.port)
    end

    :ok
  end

  @impl true
  def list_tools do
    []
  end

  @impl true
  def adapter_config(settings) do
    settings.claude
  end

  @impl true
  def api_key_env, do: "ANTHROPIC_API_KEY"

  # Private functions

  defp validate_workspace(workspace, nil) when is_binary(workspace) do
    expanded_workspace = Path.expand(workspace)
    expanded_root = Path.expand(Config.settings!().workspace.root)

    with {:ok, canonical_workspace} <- PathSafety.canonicalize(expanded_workspace),
         {:ok, canonical_root} <- PathSafety.canonicalize(expanded_root) do
      cond do
        canonical_workspace == canonical_root ->
          {:error, {:invalid_workspace_cwd, :workspace_root, canonical_workspace}}

        String.starts_with?(canonical_workspace <> "/", canonical_root <> "/") ->
          {:ok, canonical_workspace}

        true ->
          {:error, {:invalid_workspace_cwd, :outside_workspace_root, canonical_workspace, canonical_root}}
      end
    else
      {:error, {:path_canonicalize_failed, path, reason}} ->
        {:error, {:invalid_workspace_cwd, :path_unreadable, path, reason}}
    end
  end

  defp validate_workspace(workspace, worker_host) when is_binary(workspace) and is_binary(worker_host) do
    if String.trim(workspace) == "" do
      {:error, {:invalid_workspace_cwd, :empty_remote_workspace, worker_host}}
    else
      {:ok, workspace}
    end
  end

  defp get_runtime_config(workspace) when is_binary(workspace) do
    settings = Config.settings!()

    config = %{
      command: settings.claude.command,
      model: settings.claude.model,
      permission_mode: settings.claude.permission_mode,
      allowed_tools: settings.claude.allowed_tools,
      disallowed_tools: settings.claude.disallowed_tools,
      max_turns: settings.claude.max_turns,
      api_key: settings.claude.api_key,
      system_prompt: settings.claude.system_prompt,
      turn_timeout_ms: settings.claude.turn_timeout_ms,
      stall_timeout_ms: settings.claude.stall_timeout_ms
    }

    {:ok, config}
  end

  defp build_env(config) do
    env =
      Enum.reduce(System.get_env(), [], fn {k, v}, acc ->
        [{String.to_charlist(k), String.to_charlist(v)} | acc]
      end)

    env =
      if config.api_key do
        put_env_var(env, ~c"ANTHROPIC_API_KEY", String.to_charlist(config.api_key))
      else
        env
      end

    # Clear nested Claude session detection for the child process without
    # constructing an invalid Port env option.
    put_env_var(env, ~c"CLAUDECODE", ~c"")
  end

  defp put_env_var(env, key, value) when is_list(env) and is_list(key) and is_list(value) do
    case List.keymember?(env, key, 0) do
      true -> List.keyreplace(env, key, 0, {key, value})
      false -> [{key, value} | env]
    end
  end

  defp build_command(config, prompt_file) do
    parts = [
      config.command,
      "--print",
      "--verbose",
      "--output-format",
      "stream-json"
    ]

    parts =
      if config.max_turns do
        parts ++ ["--max-turns", to_string(config.max_turns)]
      else
        parts
      end

    parts =
      if config.model do
        parts ++ ["--model", config.model]
      else
        parts
      end

    parts =
      if config.permission_mode do
        parts ++ ["--permission-mode", config.permission_mode]
      else
        parts
      end

    parts =
      if config.allowed_tools && config.allowed_tools != [] do
        parts ++ ["--allowedTools", Enum.join(config.allowed_tools, ",")]
      else
        parts
      end

    parts =
      if config.disallowed_tools && config.disallowed_tools != [] do
        parts ++ ["--disallowedTools", Enum.join(config.disallowed_tools, ",")]
      else
        parts
      end

    parts =
      if config.system_prompt do
        parts ++ ["--system-prompt", shell_escape(config.system_prompt)]
      else
        parts
      end

    parts = parts ++ ["< #{shell_escape(prompt_file)}"]

    Enum.join(parts, " ")
  end

  defp write_prompt_file(prompt) do
    tmp_dir = System.tmp_dir!()
    filename = Path.join(tmp_dir, "symphony-prompt-#{:crypto.strong_rand_bytes(16) |> Base.encode16()}.txt")
    File.write!(filename, prompt)
    filename
  end

  defp await_completion(state) do
    port = state.session.port
    timeout_ms = state.session.config.turn_timeout_ms

    stall_timer =
      if state.stall_timeout_ms > 0 do
        Process.send_after(self(), :stall_check, state.stall_timeout_ms)
      end

    result = receive_loop(state, port, timeout_ms, "", nil)

    if stall_timer, do: Process.cancel_timer(stall_timer)

    result
  end

  defp receive_loop(state, port, timeout_ms, pending_line, session_id) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        complete_line = pending_line <> to_string(chunk)
        SessionLogger.log_received(Process.get(:session_log), complete_line)
        handle_line(state, complete_line, session_id)

      {^port, {:data, {:noeol, chunk}}} ->
        receive_loop(state, port, timeout_ms, pending_line <> to_string(chunk), session_id)

      {^port, {:exit_status, status}} ->
        if status != 0 do
          {:error, {:port_exit, status}}
        else
          {:ok, %{session_id: session_id}}
        end

      :stall_check ->
        {:error, :stall_timeout}
    after
      timeout_ms ->
        Port.close(port)
        {:error, :turn_timeout}
    end
  end

  defp handle_line(state, line, session_id) do
    event = parse_line(line, state, session_id)

    new_session_id = event.session_id || session_id
    new_state = %{state | session_id: new_session_id}

    cond do
      event.event == :session_started ->
        send_event(new_state, event)
        receive_loop(new_state, state.session.port, state.session.config.turn_timeout_ms, "", new_session_id)

      event.event == :turn_completed ->
        send_event(new_state, event)
        {:ok, %{session_id: new_session_id}}

      event.event == :turn_failed ->
        send_event(new_state, event)
        {:error, {:turn_failed, event.error}}

      true ->
        send_event(new_state, event)
        receive_loop(new_state, state.session.port, state.session.config.turn_timeout_ms, "", new_session_id)
    end
  end

  defp parse_line(line, state, session_id) do
    case Jason.decode(line) do
      {:ok, %{"type" => "system"} = payload} ->
        sid = payload["session_id"]
        pid = payload["pid"] || state.session.pid

        %Event{
          event: :session_started,
          timestamp: DateTime.utc_now(),
          agent_pid: pid,
          session_id: sid || session_id,
          payload: payload
        }

      {:ok, %{"type" => "result"} = payload} ->
        stop_reason = payload["stop_reason"] || ""
        usage = extract_usage(payload)
        rate_limits = extract_rate_limits(payload)

        pid = payload["pid"] || state.session.pid

        known_failure_reasons = ["error", "error_result"]

        if stop_reason in known_failure_reasons do
          %Event{
            event: :turn_failed,
            timestamp: DateTime.utc_now(),
            agent_pid: pid,
            session_id: session_id,
            usage: usage,
            stop_reason: stop_reason,
            error: "stop_reason=#{stop_reason}",
            rate_limits: rate_limits,
            payload: payload
          }
        else
          if stop_reason not in ["end_turn", "max_turns", "tool_use"] do
            Logger.warning("Claude session completed with unexpected stop_reason=#{stop_reason}; treating as success")
          end

          %Event{
            event: :turn_completed,
            timestamp: DateTime.utc_now(),
            agent_pid: pid,
            session_id: session_id,
            usage: usage,
            stop_reason: stop_reason,
            rate_limits: rate_limits,
            payload: payload
          }
        end

      {:ok, %{"type" => "assistant"} = payload} ->
        message = extract_assistant_message(payload)

        %Event{
          event: :notification,
          timestamp: DateTime.utc_now(),
          agent_pid: state.session.pid,
          session_id: session_id,
          message: message,
          payload: payload
        }

      {:ok, %{"type" => type} = payload} ->
        %Event{
          event: :other_message,
          timestamp: DateTime.utc_now(),
          agent_pid: state.session.pid,
          session_id: session_id,
          message: type,
          payload: payload
        }

      _ ->
        %Event{
          event: :malformed,
          timestamp: DateTime.utc_now(),
          agent_pid: state.session.pid,
          session_id: session_id,
          message: String.slice(line, 0, 200),
          payload: %{}
        }
    end
  end

  defp extract_usage(payload) do
    with %{"usage" => usage} <- payload,
         true <- is_map(usage) do
      %{
        input_tokens: usage["input_tokens"] || 0,
        output_tokens: usage["output_tokens"] || 0,
        total_tokens: usage["total_tokens"] || 0,
        cost_usd: usage["cost_usd"]
      }
    else
      _ -> nil
    end
  end

  defp extract_rate_limits(payload) do
    with %{"rate_limits" => rl} <- payload,
         true <- is_map(rl) do
      %{
        requests_limit: rl["requests_limit"],
        requests_remaining: rl["requests_remaining"],
        tokens_limit: rl["tokens_limit"],
        tokens_remaining: rl["tokens_remaining"]
      }
    else
      _ -> nil
    end
  end

  defp extract_assistant_message(payload) do
    with %{"message" => %{"content" => content}} <- payload,
         true <- is_list(content) do
      content
      |> Enum.find(fn item -> item["type"] == "text" end)
      |> case do
        %{"text" => text} -> String.slice(text, 0, 200)
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  defp send_event(state, event) do
    try do
      state.on_message.(event)
    rescue
      _ -> :ok
    end
  end

  defp send_initial_event(state, event_type) do
    event = %Event{
      event: event_type,
      timestamp: DateTime.utc_now(),
      agent_pid: state.session.pid,
      session_id: nil,
      payload: %{}
    }

    send_event(state, event)
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end

  defp issue_context(%{id: id, identifier: identifier}) do
    "issue_id=#{id} issue_identifier=#{identifier}"
  end
end
