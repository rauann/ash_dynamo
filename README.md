[![AshDynamo CI](https://github.com/rauann/ash_dynamo/actions/workflows/ash_dynamo_ci.yml/badge.svg)](https://github.com/rauann/ash_dynamo/actions/workflows/ash_dynamo_ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/ash_dynamo.svg)](https://hex.pm/packages/ash_dynamo)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# AshDynamo

Ash data layer for DynamoDB backed by [ExAws.Dynamo](https://github.com/ex-aws/ex_aws_dynamo). It provides a `dynamodb` DSL section so an Ash resource can declare its table, partition/sort keys, and actions, and then persist records to Dynamo.

## Installation

If [available in Hex](https://hex.pm/docs/publish), add `ash_dynamo` to `mix.exs`:

```elixir
def deps do
  [
    {:ash_dynamo, "~> 0.2.1"}
  ]
end
```

## Tutorials

- [Get Started](documentation/tutorials/getting-started-with-ash-dynamo.md)

## Topics

- [Supported Ash Features](documentation/topics/ash-features.md)

## Development

- [Testing](documentation/development/testing.md)

## References

- [AshDynamo.DataLayer DSL](documentation/dsls/DSL-AshDynamo.DataLayer.md)
