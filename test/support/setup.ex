defmodule AshDynamo.Test.Setup do
  @moduledoc false

  def migrate!(_context) do
    AshDynamo.Test.Migrate.create!()

    ExUnit.Callbacks.on_exit(fn ->
      AshDynamo.Test.Migrate.drop!()
    end)
  end
end
