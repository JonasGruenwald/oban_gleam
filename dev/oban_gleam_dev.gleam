import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/io
import gleam/otp/static_supervisor as supervisor
import logging
import oban_gleam.{type JobResult} as oban
import oban_gleam/ecto/repo

pub fn main() {
  let assert Ok(_) = start()
  let assert Ok(_) =
    oban.new_job("hello_worker")
    |> oban.arg("name", dynamic.string("Joe"))
    |> oban.schedule_in(seconds: 5)
    |> oban.insert()
  process.sleep_forever()
}

fn periodic_worker(_job) {
  io.println("I work every now and then :)")
  oban.Ok
}

fn hello_worker(job: oban.Job) -> JobResult {
  case decode.run(job.args, decode.at(["name"], decode.string)) {
    Ok(name) -> {
      io.println("Hello " <> name)
      oban.Ok
    }
    error -> oban.to_job_result(error)
  }
}

fn start() {
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
    |> oban.worker("periodic_worker", periodic_worker)
    |> oban.cron_jobs([
      oban.Cron(expression: "* * * * *", job: oban.new_job("periodic_worker")),
    ])
  let assert Ok(_) = oban.attach_default_logger(logging.Debug, False)

  // Start system
  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(repo.supervised())
  |> supervisor.add(oban.supervised(oban_config))
  |> supervisor.start
}

@external(erlang, "observer", "start")
pub fn start_observer() -> Nil
