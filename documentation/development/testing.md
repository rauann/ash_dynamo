# Testing

## Prerequisites

**Docker** is required to run the test suite. The tests use [DynamoDB Local](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DynamoDBLocal.html) running in a Docker container.

## Make Commands

The Makefile provides convenient commands that automatically start DynamoDB Local before running tests:

| Command           | Description                                                                |
| ----------------- | -------------------------------------------------------------------------- |
| `make test`       | Start DynamoDB Local (if not running) and run the test suite               |
| `make test.watch` | Start DynamoDB Local and run tests in watch mode (re-runs on file changes) |
| `make compose`    | Start only the DynamoDB Local container                                    |

### Running Specific Tests

You can pass arguments to filter which tests to run:

```bash
# Run a specific test file
make test test/read_test.exs
```

## Docker Compose

The `docker-compose.test.yml` file defines the DynamoDB Local service:

- **Image:** `amazon/dynamodb-local:latest`
- **Port:** `8099` (mapped to container's `8000`)
- **Mode:** In-memory with shared database (`-sharedDb -inMemory`)

The container is started automatically by the Make commands, but you can also manage it manually:

```bash
# Start the container
docker compose -f docker-compose.test.yml up -d

# Stop the container
docker compose -f docker-compose.test.yml down
```
