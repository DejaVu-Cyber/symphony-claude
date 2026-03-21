defmodule SymphonyElixir.Agent.Behaviour do
  @moduledoc """
  Behaviour for AI coding agent adapters.

  Implement this behaviour to support different AI coding agents
  such as Claude Code, Codex, MiniMax, OpenCode, etc.

  Each adapter is responsible for:
  - Starting a session in a workspace
  - Running turns with prompts
  - Streaming events back via callback
  - Handling tool execution (either natively or via DynamicTool)
  - Stopping the session gracefully
  """

  alias SymphonyElixir.Linear.Issue

  @type session :: map()
  @type tool_result :: %{success: boolean(), output: String.t(), content_items: [map()]}
  @type event :: SymphonyElixir.Agent.Event.t()
  @type tool_executor :: (String.t(), map(), map() -> tool_result())
  @type adapter_config :: map()

  @doc """
  Start a new agent session in the given workspace.

  Returns {:ok, session} or {:error, reason}
  """
  @callback start_session(workspace :: Path.t(), opts :: keyword()) ::
              {:ok, session()} | {:error, term()}

  @doc """
  Run a single turn with the given prompt.

  The session should emit events via the on_message callback.
  Returns {:ok, %{session_id: String.t(), thread_id: String.t() | nil, turn_id: String.t() | nil}} or {:error, reason}
  """
  @callback run_turn(
              session :: session(),
              prompt :: String.t(),
              issue :: Issue.t(),
              opts :: keyword()
            ) :: {:ok, %{session_id: String.t(), thread_id: String.t() | nil, turn_id: String.t() | nil}} | {:error, term()}

  @doc """
  Stop the session gracefully.
  """
  @callback stop_session(session :: session()) :: :ok

  @doc """
  Get the list of tools supported by this agent adapter.
  Returns a list of tool specs in the format expected by DynamicTool.
  """
  @callback list_tools() :: [map()]

  @doc """
  Get the adapter-specific configuration for this agent.
  This is called to merge adapter-specific config with the main config.
  """
  @callback adapter_config(settings :: SymphonyElixir.Config.Schema.t()) :: adapter_config()

  @doc """
  Get the API key environment variable name for this adapter.
  """
  @callback api_key_env() :: String.t()
end
