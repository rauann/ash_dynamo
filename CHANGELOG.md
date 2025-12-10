# Changelog

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

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
