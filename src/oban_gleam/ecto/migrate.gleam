import envoy
import gleam/int
import oban_gleam/ecto/repo

/// Run the Oban Ecto migrations
/// Config is set using the standard Postgres config env variables
pub fn main() {
  parse_config_from_env()
  |> repo.apply_config()
  migrate()
}

/// Parse PostgreSQL configuration from standard environment variables
fn parse_config_from_env() -> repo.Config {
  let base_config = repo.default_config()

  base_config
  |> apply_env_username()
  |> apply_env_password()
  |> apply_env_database()
  |> apply_env_hostname()
  |> apply_env_port()
  |> apply_env_pool_size()
}

fn apply_env_username(config: repo.Config) -> repo.Config {
  case envoy.get("PGUSER") {
    Ok(username) -> repo.username(config, username)
    Error(_) -> config
  }
}

fn apply_env_password(config: repo.Config) -> repo.Config {
  case envoy.get("PGPASSWORD") {
    Ok(password) -> repo.password(config, password)
    Error(_) -> config
  }
}

fn apply_env_database(config: repo.Config) -> repo.Config {
  case envoy.get("PGDATABASE") {
    Ok(database) -> repo.database(config, database)
    Error(_) -> config
  }
}

fn apply_env_hostname(config: repo.Config) -> repo.Config {
  case envoy.get("PGHOST") {
    Ok(hostname) -> repo.hostname(config, hostname)
    Error(_) -> config
  }
}

fn apply_env_port(config: repo.Config) -> repo.Config {
  case envoy.get("PGPORT") {
    Ok(port_str) -> {
      case int.parse(port_str) {
        Ok(port) -> repo.port(config, port)
        Error(_) -> config
      }
    }
    Error(_) -> config
  }
}

fn apply_env_pool_size(config: repo.Config) -> repo.Config {
  case envoy.get("PGPOOL_SIZE") {
    Ok(pool_size_str) -> {
      case int.parse(pool_size_str) {
        Ok(pool_size) -> repo.pool_size(config, pool_size)
        Error(_) -> config
      }
    }
    Error(_) -> config
  }
}

@external(erlang, "Elixir.ObanGleam.Internal.Repo", "migrate")
pub fn migrate() -> Nil
