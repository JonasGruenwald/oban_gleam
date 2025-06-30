import gleam/option.{type Option, None}
import gleam/otp/actor
import gleam/otp/supervision
import oban_gleam/internal/util

const default_port = 5432

pub opaque type Config {
  Config(
    username: String,
    password: option.Option(String),
    database: String,
    hostname: String,
    port: Int,
    pool_size: Int,
  )
}

pub fn default_config() {
  Config(
    username: "postgres",
    password: None,
    database: "postgres",
    hostname: "127.0.0.1",
    port: default_port,
    pool_size: 10,
  )
}

// -- CONFIGURATION

/// Password for the user.
pub fn password(config: Config, password: Option(String)) -> Config {
  Config(..config, password: password)
}

/// Username for the database connection.
pub fn username(config: Config, username: String) -> Config {
  Config(..config, username: username)
}

/// Database name to connect to.
pub fn database(config: Config, database: String) -> Config {
  Config(..config, database: database)
}

/// Hostname of the database server.
pub fn hostname(config: Config, hostname: String) -> Config {
  Config(..config, hostname: hostname)
}

/// Port number for the database connection.
pub fn port(config: Config, port: Int) -> Config {
  Config(..config, port: port)
}

/// Pool size for connection pooling.
pub fn pool_size(config: Config, pool_size: Int) -> Config {
  Config(..config, pool_size: pool_size)
}

pub fn apply_config(config: Config) -> Nil {
  configure_repo(
    config.username,
    config.database,
    config.hostname,
    config.port,
    config.pool_size,
    config.password,
  )
}

@external(erlang, "Elixir.ObanGleam.Internal.Repo", "configure")
fn configure_repo(
  username: String,
  database: String,
  hostname: String,
  port: Int,
  pool_size: Int,
  password: Option(String),
) -> Nil

// -- STARTUP

pub fn start() -> Result(actor.Started(Nil), actor.StartError) {
  util.start_elixir_module("Elixir.ObanGleam.Internal.Repo", [])
}

pub fn supervised() -> supervision.ChildSpecification(Nil) {
  supervision.ChildSpecification(
    start: start,
    child_type: supervision.Supervisor,
    significant: False,
    restart: supervision.Permanent,
  )
}
