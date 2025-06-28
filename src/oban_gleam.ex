defmodule ObanGleam do
  use Oban.Worker

  @impl true
  def perform(%Oban.Job{
        args: %{"__worker__" => oban_gleam_worker_name} = args,
        tags: tags,
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    case ObanGleam.Internal.WorkerRegistry.get_worker(oban_gleam_worker_name) do
      {:ok, worker} ->
        worker.({:job, args, tags, attempt, max_attempts})

      {:error, reason} ->
        {:error, reason}
    end
  end

  def start_elixir_module("Elixir." <> _ = name, opts) when is_binary(name) do
    module = String.to_atom(name)
    Code.ensure_loaded(module)
    start_elixir_module(module, opts)
  end

  def start_elixir_module(module, opts) when is_atom(module) do
    if function_exported?(module, :start_link, 1) do
      try do
        case module.start_link(opts) do
          {:ok, pid} ->
            {:ok, {:started, pid, nil}}

          :ignore ->
            {:error, {:init_failed, "Module #{module} start_link/1 returned :ignore"}}

          {:error, reason} ->
            {:error, {:init_failed, "Failed to start module #{module}: #{inspect(reason)}"}}
        end
      catch
        :exit, {:timeout, _} ->
          {:error, :init_timeout}

        :exit, reason ->
          {:error, {:init_failed, "Module #{module} start_link/1 exited: #{inspect(reason)}"}}

        kind, reason ->
          {:error,
           {:init_failed, "Module #{module} start_link/1 failed with #{kind}: #{inspect(reason)}"}}
      end
    else
      {:error, {:init_failed, "Module #{module} does not export start_link/1"}}
    end
  end

  def start_elixir_module(name, _) do
    {:error, {:init_failed, "Invalid module name #{name}. It must start with 'Elixir.'"}}
  end

  def transform_oban_config(config) do
    {:config, repo, engine, notifier, peer, queues, prune_interval, cron_jobs, _workers} = config

    plugins = []

    plugins =
      case prune_interval do
        :none -> plugins
        {:some, interval} -> [{Oban.Plugins.Pruner, max_age: interval} | plugins]
      end

    plugins =
      case cron_jobs do
        [] ->
          plugins

        jobs ->
          [
            {Oban.Plugins.Cron,
             crontab:
               Enum.map(cron_jobs, fn {:cron, expression, {:job_builder, worker, args, opts}} ->
                 complete_args = Map.put(args, "__worker__", worker)
                 opts = Keyword.put(opts, :args, complete_args)

                 {
                   expression,
                   __MODULE__,
                   opts
                 }
               end)}
            | plugins
          ]
      end

    [
      repo: repo,
      engine: engine,
      notifier: notifier,
      peer: peer,
      queues: Enum.map(queues, fn {name, concurrency} -> {String.to_atom(name), concurrency} end),
      plugins: plugins
    ]
  end

  def attach_default_logger(level, encode) do
    case Oban.Telemetry.attach_default_logger(
           level: level,
           encode: encode
         ) do
      :ok ->
        {:ok, nil}

      {:error, _} ->
        {:error, nil}
    end
  end

  def insert({:job_builder, worker, args, opts}) do
    complete_args = Map.put(args, "__worker__", worker)

    case __MODULE__.new(complete_args, opts)
         |> Oban.insert() do
      {:ok, job} ->
        {:ok, job}

      {:error, reason} ->
        {:error, {:insert_failure, inspect(reason)}}
    end
  end

  def time_to_datetime(unix_seconds, unix_nanoseconds) do
    DateTime.from_unix!(
      unix_seconds,
      :second
    )
    |> DateTime.add(unix_nanoseconds, :nanosecond)
  end
end
