defmodule SymphonyElixir.SessionLogger do
  @moduledoc """
  Writes per-session JSONL transcript files for debugging agent protocol exchanges.

  Each session gets a file under `{logs-root}/log/session-logs/` containing every
  raw message sent to and received from the agent process. See `docs/logging.md`
  for format details and cleanup guidance.
  """

  require Logger

  @type handle :: pid()

  @session_logs_dir "session-logs"

  @spec open(atom(), map(), String.t()) :: {:ok, handle()} | {:error, term()}
  def open(adapter, issue, session_id) do
    filename = build_filename(adapter, issue, session_id)
    dir = session_logs_dir()

    with :ok <- File.mkdir_p(dir) do
      path = Path.join(dir, filename)

      case File.open(path, [:write, :utf8]) do
        {:ok, device} ->
          {:ok, device}

        {:error, reason} ->
          Logger.warning("SessionLogger: failed to open #{path}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @spec log_sent(handle() | nil, String.t()) :: :ok
  def log_sent(nil, _data), do: :ok

  def log_sent(device, data) do
    write_entry(device, "sent", data)
  end

  @spec log_received(handle() | nil, String.t()) :: :ok
  def log_received(nil, _data), do: :ok

  def log_received(device, data) do
    write_entry(device, "recv", data)
  end

  @spec close(handle() | nil) :: :ok
  def close(nil), do: :ok

  def close(device) do
    File.close(device)
    :ok
  end

  defp write_entry(device, direction, data) do
    entry = %{
      ts: DateTime.utc_now() |> DateTime.to_iso8601(),
      dir: direction,
      data: String.trim_trailing(to_string(data))
    }

    case Jason.encode(entry) do
      {:ok, json} ->
        IO.puts(device, json)

      {:error, reason} ->
        Logger.warning("SessionLogger: failed to encode entry: #{inspect(reason)}")
    end

    :ok
  rescue
    e ->
      Logger.warning("SessionLogger: write failed: #{inspect(e)}")
      :ok
  end

  defp build_filename(adapter, issue, session_id) do
    identifier = Map.get(issue, :identifier, "unknown") |> sanitize()
    safe_session = sanitize(session_id)
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%dT%H%M%S")
    "#{adapter}_#{identifier}_#{safe_session}_#{timestamp}.jsonl"
  end

  defp sanitize(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_\-]/, "_")
  end

  defp session_logs_dir do
    log_file = Application.get_env(:symphony_elixir, :log_file, SymphonyElixir.LogFile.default_log_file())
    log_dir = Path.dirname(Path.expand(log_file))
    Path.join(log_dir, @session_logs_dir)
  end
end
