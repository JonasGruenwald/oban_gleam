import gleam
import gleam/dict
import gleam/dynamic
import gleam/erlang/atom.{type Atom}
import gleam/list
import gleam/option.{type Option, None}
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import gleam/string
import gleam/time/timestamp
import logging
import oban_gleam/internal/util

// -- CONFIGURATION

pub opaque type Config {
  Config(
    repo: Atom,
    engine: Atom,
    notifier: Atom,
    peer: Atom,
    queues: List(Queue),
    prune_interval: Option(Int),
    cron_jobs: List(Cron),
    workers: List(#(String, Worker)),
  )
}
 
pub type Queue =
  #(String, Int)

pub type Cron {
  Cron(expression: String, job: JobBuilder)
}

pub fn default_config() -> Config {
  Config(
    repo: atom.create("Elixir.ObanGleam.Internal.Repo"),
    engine: atom.create("Elixir.Oban.Engines.Basic"),
    notifier: atom.create("Elixir.Oban.Notifiers.PG"),
    peer: atom.create("Elixir.Oban.Peers.Global"),
    queues: [#("default", 10)],
    prune_interval: None,
    cron_jobs: [],
    workers: [],
  )
}

pub fn repo(config: Config, repo: Atom) -> Config {
  Config(..config, repo:)
}

pub fn queues(config: Config, queues: List(Queue)) -> Config {
  Config(..config, queues:)
}

pub fn engine(config: Config, engine: Atom) -> Config {
  Config(..config, engine:)
}

pub fn notifier(config: Config, notifier: Atom) -> Config {
  Config(..config, notifier:)
}

pub fn peer(config: Config, peer: Atom) -> Config {
  Config(..config, peer:)
}

pub fn prune_interval(config: Config, interval: Option(Int)) -> Config {
  Config(..config, prune_interval: interval)
}

pub fn cron_jobs(config: Config, jobs: List(Cron)) -> Config {
  Config(..config, cron_jobs: jobs)
}

pub fn worker(config: Config, key: String, worker: Worker) {
  Config(..config, workers: [#(key, worker), ..config.workers])
}

@external(erlang, "Elixir.ObanGleam", "transform_oban_config")
fn transform_oban_config(config: Config) -> List(util.ConfigOption)

@external(erlang, "Elixir.ObanGleam", "attach_default_logger")
pub fn attach_default_logger(
  log_level log_level: logging.LogLevel,
  encode_to_json encode_to_json: Bool,
) -> Result(Nil, Nil)

// -- STARTUP

fn build_supervisor(config: Config) {
  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(supervision.ChildSpecification(
    start: fn() { start_worker_registry(config.workers) },
    child_type: supervision.Supervisor,
    significant: False,
    restart: supervision.Permanent,
  ))
  |> supervisor.add(supervision.ChildSpecification(
    start: fn() {
      let config_options = transform_oban_config(config)
      util.start_elixir_module("Elixir.Oban", config_options)
    },
    child_type: supervision.Supervisor,
    significant: False,
    restart: supervision.Permanent,
  ))
}

pub fn start(
  config: Config,
) -> Result(actor.Started(supervisor.Supervisor), actor.StartError) {
  build_supervisor(config)
  |> supervisor.start()
}

pub fn supervised(config: Config) {
  build_supervisor(config)
  |> supervisor.supervised()
}

@external(erlang, "Elixir.ObanGleam.Internal.WorkerRegistry", "start_from_gleam")
fn start_worker_registry(
  workers: List(#(String, Worker)),
) -> Result(actor.Started(Nil), actor.StartError)

// -- API

pub type Worker =
  fn(Job) -> JobResult

/// Representation of: https://hexdocs.pm/oban/Oban.Job.html#t:t/0. 
/// Doesn't currently include all available fields of the Job struct
pub type Job {
  Job(
    args: dynamic.Dynamic,
    tags: List(String),
    attempt: Int,
    max_attempts: Int,
  )
}

pub type JobResult {
  /// The job is successful and marked as completed.
  Ok
  /// The job is marked as cancelled for the provided reason and no longer retried.
  Cancel(reason: String)
  /// The job is marked as retryable for the provided reason, or discarded if it has exhausted all attempts.
  Error(reason: String)
  /// Mark the job as scheduled to run again seconds in the future
  Snooze(seconds: Int)
}

/// Transform any Gleam result to an Oban Job result. 
/// 
/// `Ok` values will have their content discarded  
/// `Error` values will have their content stringified  
pub fn to_job_result(result: Result(a, b)) -> JobResult {
  case result {
    gleam.Ok(_) -> Ok
    gleam.Error(val) -> Error(string.inspect(val))
  }
}

pub opaque type JobBuilder {
  JobBuilder(
    worker: String,
    args: WorkerArgs,
    opts: List(#(Atom, dynamic.Dynamic)),
  )
}

type WorkerArgs =
  dict.Dict(String, dynamic.Dynamic)

pub type JobInsertError {
  InvalidWorkerName
  InsertFailure(String)
}

pub fn new_job(worker worker: String) -> JobBuilder {
  JobBuilder(worker: worker, args: dict.new(), opts: [])
}

pub fn set_args(builder: JobBuilder, args: WorkerArgs) {
  JobBuilder(..builder, args:)
}

pub fn arg(builder: JobBuilder, key: String, value: dynamic.Dynamic) {
  JobBuilder(..builder, args: dict.insert(builder.args, key, value))
}

pub fn max_attempts(builder: JobBuilder, attempts: Int) {
  JobBuilder(..builder, opts: [
    #(atom.create("max_attempts"), dynamic.int(attempts)),
    ..builder.opts
  ])
}

pub fn priority(builder: JobBuilder, priority: Int) {
  JobBuilder(..builder, opts: [
    #(atom.create("priority"), dynamic.int(priority)),
    ..builder.opts
  ])
}

pub fn queue(builder: JobBuilder, queue: String) {
  JobBuilder(..builder, opts: [
    #(atom.create("queue"), atom.to_dynamic(atom.create(queue))),
    ..builder.opts
  ])
}

pub fn schedule_in(builder: JobBuilder, seconds seconds: Int) {
  JobBuilder(..builder, opts: [
    #(atom.create("schedule_in"), dynamic.int(seconds)),
    ..builder.opts
  ])
}

pub fn schedule_at(builder: JobBuilder, timestamp: timestamp.Timestamp) {
  let #(seconds, nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp)
  JobBuilder(..builder, opts: [
    #(atom.create("schedule_at"), time_to_elixir_datetime(seconds, nanoseconds)),
    ..builder.opts
  ])
}

pub fn tags(builder: JobBuilder, tags: List(String)) {
  JobBuilder(..builder, opts: [
    #(atom.create("tags"), dynamic.list(list.map(tags, dynamic.string))),
    ..builder.opts
  ])
}

@external(erlang, "Elixir.ObanGleam", "insert")
pub fn insert(worker: JobBuilder) -> Result(dynamic.Dynamic, JobInsertError)

@external(erlang, "Elixir.ObanGleam", "time_to_datetime")
fn time_to_elixir_datetime(seconds: Int, nanoseconds: Int) -> dynamic.Dynamic
