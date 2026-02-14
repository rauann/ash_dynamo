# Changelog

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

## [v0.4.1](https://github.com/rauann/ash_dynamo/compare/v0.4.0...v0.4.1) (2026-02-14)

### Documentation

- Add `global_secondary_index` DSL reference to documentation
- Add GSI example to getting started guide
- Add `@type t` to `SecondaryIndex` to fix `mix docs` warnings
- Remove misleading projection comment from `SecondaryIndex` moduledoc

### Chores

- Upgrade ash dependency

## [v0.4.0](https://github.com/rauann/ash_dynamo/compare/v0.3.0...v0.4.0) (2026-02-14)

### Features

- Add GSI DSL entity with `global_secondary_index` declaration in `dynamodb` section
- Implement automatic GSI index selection for query routing (table PK > GSI PK > Scan)
- Add opt-in scan operation warning via `config :ash_dynamo, warn_on_scan?: true`

### Chores

- Add telemetry-based request body capture helper for test assertions
- Bump dependencies

## [v0.3.0](https://github.com/rauann/ash_dynamo/compare/v0.2.1...v0.3.0) (2026-01-15)

### Features

- Implement `:sort` capability for sort key ordering via `ScanIndexForward`
- Add runtime sort fallback using `Ash.Actions.Sort.runtime_sort` for:
  - Scan mode (no partition key filter)
  - Non-sort-key fields in Query mode
  - Multiple sort fields

## [v0.2.1](https://github.com/rauann/ash_dynamo/compare/v0.2.0...v0.2.1) (2025-12-11)

### Chores

- Add test setup with DynamoDB Local
- Improve documentation
- Add credo
- Add CI workflow
- Prepare to publish release

## [v0.2.0](https://github.com/rauann/ash_dynamo/compare/v0.1.0...v0.2.0) (2025-12-10)

### Features

- Implement `:create` action with `PutItem` and uniqueness check (no upsert)
- Implement `:update` action with `UpdateItem` and existence check
- Implement `:destroy` action with `DeleteItem` and existence check
- Add `:select` support via `ProjectionExpression`
- Implement `KeyConditionExpression` for partition key and sort key operators (`=`, `<`, `<=`, `>`, `>=`)
- Implement `FilterExpression` for non-key attribute filtering (`=`, `<>`, `<`, `<=`, `>`, `>=`, `contains`)
- Add runtime filter fallback for `or` conditions

### Documentation

- Add supported features roadmap to README
- Add note about pagination limitation (1MB per request)

## [v0.1.0](https://github.com/rauann/ash_dynamo/compare/main...v0.1.0) (2025-11-29)

### Features

- Introduce the `AshDynamo.DataLayer` with a `dynamodb` DSL section for table, partition key, sort key, and index configuration.
- Add introspection helpers in `AshDynamo.DataLayer.Info` for accessing DynamoDB configuration on Ash resources.
- Provide a basic read implementation that scans the configured table via ExAws and decodes rows into Ash resources.
