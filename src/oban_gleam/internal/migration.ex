defmodule ObanGleam.Internal.Migration do
  use Ecto.Migration
  def up, do: Oban.Migration.up()
  def down, do: Oban.Migration.down(version: 1)
end
