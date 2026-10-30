#!/usr/bin/env bash
# Sourced by the deploy scripts. REFUGI_SUPPRESS_ANNOTATIONS=1 prints plain
# text so the unit tests do not create GitHub Actions error annotations.

say_error() {
	if [ "${GITHUB_ACTIONS:-}" = "true" ] && [ "${REFUGI_SUPPRESS_ANNOTATIONS:-}" != "1" ]; then
		echo "::error::$*" >&2
	else
		echo "error: $*" >&2
	fi
}

say_notice() {
	if [ "${REFUGI_SUPPRESS_ANNOTATIONS:-}" = "1" ]; then
		return 0
	fi
	if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
		echo "::notice::$*" >&2
	else
		echo "notice: $*" >&2
	fi
}
