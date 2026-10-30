#!/usr/bin/env bash
# Run this on the server before rsync. It creates only the final directory
# (refungi-child or refungi-custom) and refuses symlinks or a resolved path
# that escaped that folder.
#
# Usage: remote-target-guard.sh REMOTE_PATH
# Also accepts the path as $1 when invoked with: bash -s -- REMOTE_PATH
set -euo pipefail

target="${1:-}"
target="${target%/}"

if [ -z "$target" ]; then
	echo "Refusing to deploy: remote path is empty." >&2
	exit 1
fi

case "$target" in
	*..* | *//* | *[[:space:]]*)
		echo "Refusing to deploy: remote path is not safe." >&2
		exit 1
		;;
esac

case "$target" in
	*[!A-Za-z0-9._/-]*)
		echo "Refusing to deploy: remote path contains characters that are not allowed." >&2
		exit 1
		;;
esac

case "$target" in
	wp-content/themes/refungi-child | */wp-content/themes/refungi-child)
		suffix="/wp-content/themes/refungi-child"
		;;
	wp-content/plugins/refungi-custom | */wp-content/plugins/refungi-custom)
		suffix="/wp-content/plugins/refungi-custom"
		;;
	*)
		echo "Refusing to deploy outside wp-content/themes/refungi-child or wp-content/plugins/refungi-custom." >&2
		exit 1
		;;
esac

parent=$(dirname "$target")
if [ -z "$parent" ] || [ "$parent" = "." ]; then
	echo "Refusing to deploy: remote path has no parent directory." >&2
	exit 1
fi

if [ ! -d "$parent" ]; then
	echo "Parent directory does not exist on the server: ${parent}" >&2
	echo "WordPress must already be installed so that directory exists. This job will not create wp-content, themes, or plugins." >&2
	exit 1
fi

if [ -L "$target" ]; then
	echo "Refusing to deploy: ${target} is a symlink." >&2
	exit 1
fi

if [ -e "$target" ] && [ ! -d "$target" ]; then
	echo "Refusing to deploy: ${target} exists and is not a directory." >&2
	exit 1
fi

if [ ! -d "$target" ]; then
	mkdir "$target"
fi

if [ -L "$target" ] || [ ! -d "$target" ]; then
	echo "Refusing to deploy: ${target} is not a real directory after creation." >&2
	exit 1
fi

if ! command -v readlink >/dev/null 2>&1 || ! readlink -f / >/dev/null 2>&1; then
	echo "readlink -f is required on the server to confirm the deploy directory." >&2
	exit 1
fi

resolved=$(readlink -f "$target")
case "$resolved" in
	*"$suffix") ;;
	*)
		echo "Refusing to deploy: resolved path does not end with ${suffix} (got ${resolved})." >&2
		exit 1
		;;
esac

echo "Remote target ok: ${resolved}"
