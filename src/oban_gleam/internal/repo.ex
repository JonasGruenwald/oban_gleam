defmodule ObanGleam.Internal.Repo do
  @migration_version 20_080_906_120_000

  use Ecto.Repo,
    otp_app: :oban_gleam,
    adapter: Ecto.Adapters.Postgres

  def configure(
        username,
        database,
        hostname,
        port,
        pool_size,
        password
      ) do
    config_values = [
      username: username,
      database: database,
      hostname: hostname,
      port: port,
      pool_size: pool_size
    ]

    config_values =
      case password do
        {:some, password_value} -> Keyword.put(config_values, :password, password_value)
        _ -> config_values
      end

    Application.put_env(:oban_gleam, __MODULE__, config_values)
    # Use the built-in JSON library instead of Jason for Postgrex
    Application.put_env(:postgrex, :json_library, JSON)
  end

  def migrate do
    Application.load(:oban_gleam)
    {:ok, _pid} = __MODULE__.start_link()
    Ecto.Migrator.up(__MODULE__, @migration_version, ObanGleam.Internal.Migration)
  end

  def rollback do
    Application.load(:oban_gleam)
    {:ok, _pid} = __MODULE__.start_link()
    Ecto.Migrator.down(__MODULE__, @migration_version, ObanGleam.Internal.Migration)
  end
end
