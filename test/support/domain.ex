defmodule AshDynamo.Test.Domain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshDynamo.Test.User
  end
end
