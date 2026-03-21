defmodule SymphonyElixir.Agent.CodexAdapter do
  @moduledoc """
  Codex adapter for Symphony.

  This adapter wraps the existing AppServer implementation to provide
  a unified interface for the agent behaviour.
  """

  alias SymphonyElixir.{Agent.Behaviour, Codex.DynamicTool}
  alias SymphonyElixir.Codex.AppServer

  @behaviour Behaviour

  @impl true
  def start_session(workspace, opts \\ []) do
    case AppServer.start_session(workspace, opts) do
      {:ok, session} ->
        {:ok, Map.put(session, :adapter_type, :codex)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def run_turn(session, prompt, issue, opts \\ []) do
    on_message = Keyword.get(opts, :on_message)

    wrapped_opts =
      if on_message do
        wrapped_callback = fn message ->
          event = adapt_codex_event(message)
          on_message.(event)
        end

        Keyword.put(opts, :on_message, wrapped_callback)
      else
        opts
      end

    AppServer.run_turn(session, prompt, issue, wrapped_opts)
  end

  @impl true
  def stop_session(session) do
    AppServer.stop_session(session)
  end

  @impl true
  def list_tools do
    DynamicTool.tool_specs()
  end

  @impl true
  def adapter_config(settings) do
    settings.codex
  end

  @impl true
  def api_key_env, do: "OPENAI_API_KEY"

  defp adapt_codex_event(message) do
    SymphonyElixir.Agent.Event.from_codex_event(message)
  end
end
