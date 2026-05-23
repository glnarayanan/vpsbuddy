.PHONY: lint test check

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck bin/vps-bootstrap lib/vps-bootstrap.sh tests/run.sh; \
	else \
		echo "shellcheck not found; running bash -n fallback"; \
		bash -n bin/vps-bootstrap lib/vps-bootstrap.sh tests/run.sh; \
	fi

test:
	bash tests/run.sh

check: lint test
