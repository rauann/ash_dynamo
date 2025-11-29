defmodule AshDynamoTest do
  use ExUnit.Case
  doctest AshDynamo

  test "greets the world" do
    assert AshDynamo.hello() == :world
  end
end
