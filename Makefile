.PHONY: lint test check

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x install.sh bin/vpsbuddy lib/vpsbuddy.sh lib/templates/vpsbuddy-audit-prelude.sh lib/templates/vpsbuddy-auth.sh tests/run.sh; \
	else \
		echo "shellcheck not found; running bash -n fallback"; \
		bash -n install.sh bin/vpsbuddy lib/vpsbuddy.sh lib/templates/vpsbuddy-audit-prelude.sh lib/templates/vpsbuddy-auth.sh tests/run.sh; \
	fi

test:
	bash tests/run.sh

check: lint test
