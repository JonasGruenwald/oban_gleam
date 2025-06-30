# Oban Bindings

Basic Gleam bindings to [Oban](https://hexdocs.pm/oban/Oban.html)

## Install

Add the package to `gleam.toml`

```toml
oban_gleam = { git = "git@github.com:JonasGruenwald/oban_gleam.git", ref = "main" }
```

## Setup

### Postgrex

Postgrex (used by Oban) needs to be configured to handle JSON.  
By default it will try to use the Elixir Jason library, so you could install that to make it work.

```
gleam add jason
```

It would be nicer to just have it use the built-in JSON library in OTP27, but this needs to be configured at compile time, which is tricky to do from Gleam, see:

https://github.com/gleam-lang/gleam/discussions/4732

possible workaround: https://blog.nytsoi.net/2025/06/28/gleam-elixir-compile-config

### Migrations

Run migrations to add the Oban jobs table to the database (See: https://hexdocs.pm/oban/installation.html#manual-installation)

A Gleam function to do this is provided, first [set the credentials for the postgres database in your environment](https://www.postgresql.org/docs/current/libpq-envars.html).

Then run:

```gleam
gleam run -m oban_gleam/ecto/migrate
```

## Usage

### Config

The package comes with an Ecto repo you can use for oban, it just needs to be configured with the database credentials.

Note that this unfortunately cannot be done in an immutable way but rather through the global application environment, which is why `apply_config` does not return anything.

The repo must be started, by being added to your applications supervision tree.

Oban can be configured through a builder and it's config passed to its start function, it should be added to your supervision tree after the repo.

```gleam
import oban_gleam as oban

fn start_system() {
  // Configure Ecto Repo
  repo.default_config()
  |> repo.database("oban_gleam_dev")
  |> repo.username("oban_gleam_user")
  |> repo.password("dev")
  |> repo.apply_config()

  // Configure Oban
  let oban_config =
    oban.default_config()
    |> oban.worker("hello_worker", hello_worker)
    |> oban.queues([#("default", 10), #("mailers", 1)])
  let assert Ok(_) = oban.attach_default_logger(logging.Debug, False)

  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(repo.supervised())
  |> supervisor.add(oban.supervised(oban_config))
  |> supervisor.start
}
```

### Workers

Oban only allows defining workers by creating modules that implement a behaviour. As this is not possible in Gleam, the bindings provide a single worker that implements this behaviour and then delegates to Gleam worker functions registered through the config.

Worker functions are registered under a key, which is stringly typed, as it gets serialized to the database like all other job data.

Job arguments are a map (Gleam dict) of arbitrary data that is serialized, stored in the database, and deserialized internally by Oban, therefore they are passed as dynamic and must be decoded in the worker function.

```gleam
fn hello_worker(job: Job) -> JobResult {
  case decode.run(job.args, decode.at(["name"], decode.string)) {
    Ok(name) -> {
      io.println("Hello " <> name)
      oban.Ok
    }
    error -> oban.to_job_result(error)
  }
}
```

Worker functions accept a `Job` and return a `JobResult`, see:
https://hexdocs.pm/oban/Oban.Worker.html#t:result/0

The `JobResult`'s `Ok` variant does not accept a value, as that would be discarded by Oban anyways. The result is not a regular Gleam result, as additional variants like `Cancel` and `Snooze` can be returned.

### Scheduling Jobs

Jobs are constructed with a builder and passed to `oban.insert` to be scheduled.

All job config, such as the queue to use, scheduling time, how many times the job should be retried in case of failure etc. is defined through the job builder.

```gleam
oban.new_job("hello_worker")
|> oban.arg("name", dynamic.string("Joe"))
|> oban.max_attempts(10)
|> oban.queue("default")
|> oban.tags(["user"])
|> oban.schedule_in(seconds: 5)
|> oban.insert()
```

### Cron Jobs

Cron jobs can be defined in the config, they are also defined through the job builder.

```gleam
let oban_config =
  oban.default_config()
  |> oban.worker("periodic_worker", periodic_worker)
  |> oban.cron_jobs([
    oban.Cron(expression: "* * * * *", job: oban.new_job("periodic_worker")),
  ])
```

## Type Safety Notes and Considerations

Oban serializes job parameters like the job and queue name and stores them in the database when scheduling a job.

This means that job name and queue persist between application restarts / deployments, it's therefore not possible to make them type safe in my view, so they are both defined as string keys.

For this reason, it's possible to schedule a job for a worker or queue that doesn't actually exist in the current system – I suggest to use exported constants for job and queue names to avoid this.
