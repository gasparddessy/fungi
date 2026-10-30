#!/usr/bin/env bash
# Print a normalized remote path, or exit 1 if it is not one of the two
# directories this repo is allowed to sync.
#
# Usage: validate-deploy-target.sh theme|plugin REMOTE_PATH
set -euo pipefail

LC_ALL=C

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/log.sh"

if [ "$#" -ne 2 ]; then
	say_error "Usage: validate-deploy-target.sh theme|plugin REMOTE_PATH" >&2
	exit 1
fi

kind="$1"
raw="$2"

case "$kind" in
	theme) expected="wp-content/themes/refungi-child" ;;
	plugin) expected="wp-content/plugins/refungi-custom" ;;
	*)
		say_error "Deploy target kind must be theme or plugin." >&2
		exit 1
		;;
esac

# Trim CR, LF, and surrounding whitespace that GitHub's secret UI sometimes adds.
path=$(printf '%s' "$raw" | tr -d '\r')
path="${path#"${path%%[![:space:]]*}"}"
path="${path%"${path##*[![:space:]]}"}"

if [ -z "$path" ]; then
	say_error "Remote ${kind} path is empty." >&2
	exit 1
fi

if printf '%s' "$path" | grep -q '[[:space:]]'; then
	say_error "Remote ${kind} path must not contain spaces." >&2
	exit 1
fi

case "$path" in
	*..*)
		say_error "Remote ${kind} path must not contain '..'." >&2
		exit 1
		;;
	*//*)
		say_error "Remote ${kind} path must not contain '//'." >&2
		exit 1
		;;
esac

if ! printf '%s' "$path" | grep -Eq '^[A-Za-z0-9._/-]+$'; then
	say_error "Remote ${kind} path contains characters that are not allowed. Use only letters, numbers, and . _ / -" >&2
	exit 1
fi

while [ "${path#./}" != "$path" ]; do
	path="${path#./}"
done

while [ "${path%/}" != "$path" ]; do
	path="${path%/}"
done

case "$path" in
	"$expected" | */"$expected") ;;
	*)
		say_error "Remote ${kind} path must end with ${expected}. Refusing to sync anywhere else, so this job cannot wipe WordPress core, uploads, plugins, the parent theme, or the existing child theme." >&2
		exit 1
		;;
esac

printf '%s/\n' "$path"
