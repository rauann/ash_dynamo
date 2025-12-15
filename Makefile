ARGS ?= $(filter-out $@,$(MAKECMDGOALS))
COMPOSE_FILE ?= docker-compose.test.yml
COMPOSE_SERVICE ?= ash-dynamo-test-container

.PHONY: test test.watch compose check quality coverage format credo hex-outdated hex-audit unused-deps FORCE

test: compose
	@mix test $(ARGS)

test.watch: compose
	@mix test.watch $(ARGS)

compose:
	@docker compose -f $(COMPOSE_FILE) up -d $(COMPOSE_SERVICE) >/dev/null 2>&1 || true

check: quality coverage ## Runs quality and coverage checks.

quality: format credo hex-outdated hex-audit unused-deps ## Runs quality checks.

coverage: compose ## Runs ExUnit with coverage and trace.
	@mix test --cover --trace

format: ## Checks code formatting.
	@mix format --check-formatted

credo: ## Runs Credo static analysis.
	@mix credo --strict

hex-outdated: ## Checks for outdated dependencies.
	@mix hex.outdated

hex-audit: ## Audits dependencies for security vulnerabilities.
	@mix hex.audit

unused-deps: ## Checks for unused dependencies.
	@mix deps.unlock --check-unused

# Allow patterns like `make test test/my_test.exs` without make treating the
# file as a real target.
%: FORCE
	@:

FORCE:
