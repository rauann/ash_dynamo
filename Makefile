ARGS ?= $(filter-out $@,$(MAKECMDGOALS))

.PHONY: test test.watch compose FORCE

test: compose
	@mix test $(ARGS)

test.watch: compose
	@mix test.watch $(ARGS)

compose:
	@docker compose -f test/support/docker-compose.yml up -d >/dev/null 2>&1 \
		|| (docker compose -f test/support/docker-compose.yml up -d; exit $$?)

# Allow patterns like `make test test/my_test.exs` without make treating the
# file as a real target.
%: FORCE
	@:

FORCE:
