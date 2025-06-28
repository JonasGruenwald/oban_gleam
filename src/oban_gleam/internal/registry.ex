defmodule ObanGleam.Internal.WorkerRegistry do
  @moduledoc """
  A GenServer that manages a protected ETS table for storing worker function references.
  """

  use GenServer

  @table_name :oban_gleam_worker_registry_table
  @server_name :oban_gleam_worker_registry

  # Client API

  @doc """
  Starts the WorkerRegistry GenServer with initial worker entries.
  (Standard GenServer start_link function)
  """
  @spec start_link([{String.t(), function()}]) :: GenServer.on_start()
  def start_link(workers) do
    GenServer.start_link(__MODULE__, workers, name: @server_name)
  end

  @doc """
  Starts the WorkerRegistry GenServer, returning a gleam_otp-compatible response.
  """
  def start_from_gleam(workers) do
    ObanGleam.start_elixir_module(
      __MODULE__,
      workers
    )
  end

  @doc """
  Retrieves a worker function by key.
  """
  @spec get_worker(String.t()) :: {:ok, function()} | {:error, String.t()}
  def get_worker(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, callback}] -> {:ok, callback}
      [] -> {:error, "Worker '#{key}' not found"}
    end
  end

  # GenServer Callbacks

  @impl true
  def init(workers) do
    table =
      :ets.new(@table_name, [
        :set,
        :protected,
        :named_table,
        {:read_concurrency, true}
      ])

    # Insert all workers
    Enum.each(workers, fn {key, callback} ->
      :ets.insert(@table_name, {key, callback})
    end)

    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ets.delete(@table_name)
    :ok
  end
end
