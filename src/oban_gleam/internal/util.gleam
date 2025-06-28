import gleam/otp/actor

pub type ConfigOption

@external(erlang, "Elixir.ObanGleam", "start_elixir_module")
pub fn start_elixir_module(
  name: String,
  options: List(ConfigOption),
) -> Result(actor.Started(Nil), actor.StartError)
