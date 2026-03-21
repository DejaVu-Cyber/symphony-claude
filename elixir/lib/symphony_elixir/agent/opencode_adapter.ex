defmodule SymphonyElixir.Agent.OpenCodeAdapter do
  @moduledoc """
  OpenCode/Charm adapter for Symphony.

  This is a placeholder for OpenCode CLI integration.
  OpenCode uses `-p` for prompt mode and `-f json` for JSON output.

  Note: OpenCode does not support streaming JSON like Claude Code.
  The implementation will need to handle single JSON responses.

  TODO: Implement when OpenCode CLI capabilities are confirmed
  """

  alias SymphonyElixir.Agent.Behaviour

  @behaviour Behaviour

  @impl true
  def start_session(_workspace, _opts \\ []) do
    {:error, {:not_implemented, "OpenCode adapter not yet implemented"}}
  end

  @impl true
  def run_turn(_session, _prompt, _issue, _opts \\ []) do
    {:error, {:not_implemented, "OpenCode adapter not yet implemented"}}
  end

  @impl true
  def stop_session(_session) do
    :ok
  end

  @impl true
  def list_tools do
    []
  end

  @impl true
  def adapter_config(settings) do
    settings.opencode || %{}
  end

  @impl true
  def api_key_env, do: "OPENCODE_API_KEY"
end
