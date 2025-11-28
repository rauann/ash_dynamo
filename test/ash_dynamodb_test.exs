defmodule AshDynamodbTest do
  use ExUnit.Case
  doctest AshDynamodb

  test "greets the world" do
    assert AshDynamodb.hello() == :world
  end
end
