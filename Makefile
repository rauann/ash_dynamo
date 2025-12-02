ARGS ?= $(filter-out $@,$(MAKECMDGOALS))
COMPOSE_FILE ?= docker-compose.test.yml
COMPOSE_SERVICE ?= ash-dynamo-test-container

.PHONY: test test.watch compose FORCE

test: compose
	@mix test $(ARGS)

test.watch: compose
	@mix test.watch $(ARGS)

compose:
	@docker compose -f $(COMPOSE_FILE) up -d $(COMPOSE_SERVICE) >/dev/null 2>&1

# Allow patterns like `make test test/my_test.exs` without make treating the
# file as a real target.
%: FORCE
	@:

FORCE:
