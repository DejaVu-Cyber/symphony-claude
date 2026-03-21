defmodule SymphonyElixir.Agent.MiniMaxAdapter do
  @moduledoc """
  MiniMax adapter for Symphony.

  This is a placeholder for MiniMax CLI integration.
  MiniMax is assumed to have a similar interface to Claude Code CLI.

  TODO: Implement when MiniMax CLI documentation is available
  """

  alias SymphonyElixir.Agent.Behaviour

  @behaviour Behaviour

  @impl true
  def start_session(_workspace, _opts \\ []) do
    {:error, {:not_implemented, "MiniMax adapter not yet implemented"}}
  end

  @impl true
  def run_turn(_session, _prompt, _issue, _opts \\ []) do
    {:error, {:not_implemented, "MiniMax adapter not yet implemented"}}
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
    settings.minimax || %{}
  end

  @impl true
  def api_key_env, do: "MINIMAX_API_KEY"
end
