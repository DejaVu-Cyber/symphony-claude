defmodule SymphonyElixir.Agent.Event do
  @moduledoc """
  Unified event types for all agent adapters.

  This module defines a standardized event structure that all
  agent adapters (Claude, Codex, MiniMax, etc.) must emit.
  """

  @type event_type ::
          :session_started
          | :startup_failed
          | :turn_completed
          | :turn_failed
          | :turn_stalled
          | :turn_input_required
          | :tool_call
          | :tool_call_completed
          | :tool_call_failed
          | :unsupported_tool_call
          | :approval_required
          | :approval_auto_approved
          | :notification
          | :other_message
          | :malformed

  @type usage :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          total_tokens: non_neg_integer(),
          cost_usd: float() | nil
        }

  @type rate_limits :: %{
          requests_limit: non_neg_integer() | nil,
          requests_remaining: non_neg_integer() | nil,
          tokens_limit: non_neg_integer() | nil,
          tokens_remaining: non_neg_integer() | nil
        }

  @type t :: %__MODULE__{
          event: event_type(),
          timestamp: DateTime.t(),
          agent_pid: String.t() | nil,
          session_id: String.t() | nil,
          thread_id: String.t() | nil,
          turn_id: String.t() | nil,
          usage: usage() | nil,
          stop_reason: String.t() | nil,
          message: String.t() | nil,
          error: String.t() | nil,
          rate_limits: rate_limits() | nil,
          payload: map()
        }

  defstruct [
    :event,
    :timestamp,
    :agent_pid,
    :session_id,
    :thread_id,
    :turn_id,
    :usage,
    :stop_reason,
    :message,
    :error,
    :rate_limits,
    :payload
  ]

  @doc """
  Create a new event with the given type and details.
  """
  def new(event_type, metadata \\ %{}) do
    %__MODULE__{
      event: event_type,
      timestamp: DateTime.utc_now(),
      agent_pid: metadata[:agent_pid],
      session_id: metadata[:session_id],
      thread_id: metadata[:thread_id],
      turn_id: metadata[:turn_id],
      usage: metadata[:usage],
      stop_reason: metadata[:stop_reason],
      message: metadata[:message],
      error: metadata[:error],
      rate_limits: metadata[:rate_limits],
      payload: metadata[:payload] || %{}
    }
  end

  @doc """
  Convert a Codex-style event map to a unified Agent.Event.
  """
  def from_codex_event(codex_message) do
    event_type = normalize_codex_event(Map.get(codex_message, :event))

    %__MODULE__{
      event: event_type,
      timestamp: Map.get(codex_message, :timestamp) || DateTime.utc_now(),
      agent_pid: Map.get(codex_message, :codex_app_server_pid) || Map.get(codex_message, :metadata, %{})[:codex_app_server_pid],
      session_id: Map.get(codex_message, :session_id),
      thread_id: Map.get(codex_message, :thread_id),
      turn_id: Map.get(codex_message, :turn_id),
      usage: normalize_usage(Map.get(codex_message, :usage)),
      stop_reason: Map.get(codex_message, :stop_reason),
      message: Map.get(codex_message, :message),
      error: Map.get(codex_message, :error),
      payload: Map.get(codex_message, :payload) || %{}
    }
  end

  defp normalize_codex_event(event) when is_atom(event), do: event

  defp normalize_codex_event(event) when is_binary(event) do
    String.to_atom(event)
  end

  defp normalize_codex_event(_), do: :other_message

  defp normalize_usage(nil), do: nil

  defp normalize_usage(usage) when is_map(usage) do
    %{
      input_tokens: usage["input_tokens"] || usage[:input_tokens] || 0,
      output_tokens: usage["output_tokens"] || usage[:output_tokens] || 0,
      total_tokens: usage["total_tokens"] || usage[:total_tokens] || 0,
      cost_usd: usage["cost_usd"] || usage[:cost_usd]
    }
  end

  defp normalize_usage(_), do: nil
end
