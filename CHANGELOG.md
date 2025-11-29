# Changelog

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

## [v0.1.0](https://github.com/rauann/ash_dynamo/compare/main...v0.1.0) (2025-11-29)

- Introduce the `AshDynamo.DataLayer` with a `dynamodb` DSL section for table, partition key, sort key, and index configuration.
- Add introspection helpers in `AshDynamo.DataLayer.Info` for accessing DynamoDB configuration on Ash resources.
- Provide a basic read implementation that scans the configured table via ExAws and decodes rows into Ash resources.
