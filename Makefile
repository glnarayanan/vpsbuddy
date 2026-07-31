.PHONY: lint fmt test check

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x install.sh bin/vpsbuddy lib/vpsbuddy.sh lib/templates/vpsbuddy-audit-prelude.sh lib/templates/vpsbuddy-auth.sh tests/run.sh; \
	else \
		echo "shellcheck not found; running bash -n fallback"; \
		bash -n install.sh bin/vpsbuddy lib/vpsbuddy.sh lib/templates/vpsbuddy-audit-prelude.sh lib/templates/vpsbuddy-auth.sh tests/run.sh; \
	fi

fmt:
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -d -i 2 -ci -sr install.sh bin/vpsbuddy lib/vpsbuddy.sh lib/templates/vpsbuddy-audit-prelude.sh lib/templates/vpsbuddy-auth.sh tests/run.sh; \
	else \
		echo "shfmt not found; skipping format check"; \
	fi

test:
	bash tests/run.sh

check: lint fmt test
