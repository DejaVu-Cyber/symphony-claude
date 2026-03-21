defmodule SymphonyElixir.Agent do
  @moduledoc """
  Factory for creating agent adapters based on configuration.

  Supports multiple AI coding agents:
  - `codex` - OpenAI Codex (JSON-RPC over stdio)
  - `claude` - Anthropic Claude Code (CLI with stream-json)
  - `minimax` - MiniMax (CLI - TBD)
  - `opencode` - OpenCode/Charm (CLI with -p -f json)
  """

  @adapters %{
    "codex" => SymphonyElixir.Agent.CodexAdapter,
    "claude" => SymphonyElixir.Agent.ClaudeAdapter,
    "minimax" => SymphonyElixir.Agent.MiniMaxAdapter,
    "opencode" => SymphonyElixir.Agent.OpenCodeAdapter
  }

  @doc """
  Create an agent adapter module for the given agent type.

  ## Examples

      iex> SymphonyElixir.Agent.create("claude")
      SymphonyElixir.Agent.ClaudeAdapter

      iex> SymphonyElixir.Agent.create("codex")
      SymphonyElixir.Agent.CodexAdapter

  """
  @spec create(agent_type :: String.t()) :: module()
  def create(agent_type) when is_binary(agent_type) do
    case Map.fetch(@adapters, agent_type) do
      {:ok, adapter} ->
        adapter

      :error ->
        raise ArgumentError,
              "Unknown agent type: #{inspect(agent_type)}. Supported: #{inspect(Map.keys(@adapters))}"
    end
  end

  @doc """
  List all supported agent types.
  """
  @spec list_supported() :: [String.t()]
  def list_supported, do: Map.keys(@adapters)

  @doc """
  Check if an agent type is supported.
  """
  @spec supported?(agent_type :: String.t()) :: boolean()
  def supported?(agent_type) when is_binary(agent_type) do
    Map.has_key?(@adapters, agent_type)
  end
end
