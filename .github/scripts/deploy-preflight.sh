#!/usr/bin/env bash
# Fail before any network connection when deploy secrets or remote paths are
# missing or unsafe. Prints secret names only, never secret values.
set -euo pipefail

LC_ALL=C

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/log.sh"

host=${SFTP_HOST:-}
port_raw=${SFTP_PORT:-}
user=${SFTP_USER:-}
password=${SFTP_PASSWORD-}
key=${SFTP_KEY-}
theme_raw=${SFTP_REMOTE_THEME_PATH:-}
plugin_raw=${SFTP_REMOTE_PLUGIN_PATH:-}

trim() {
	local value="$1"
	value=$(printf '%s' "$value" | tr -d '\r')
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s' "$value"
}

host=$(trim "$host")
port_raw=$(trim "$port_raw")
user=$(trim "$user")
theme_raw=$(trim "$theme_raw")
plugin_raw=$(trim "$plugin_raw")
# Trim surrounding whitespace and a trailing newline from the secret UI.
# Internal newlines in a PEM key are preserved.
password=$(trim "$password")
key=$(trim "$key")

missing=()
[ -z "$host" ] && missing+=(SFTP_HOST)
[ -z "$user" ] && missing+=(SFTP_USER)
[ -z "$theme_raw" ] && missing+=(SFTP_REMOTE_THEME_PATH)
if [ -z "$key" ] && [ -z "$password" ]; then
	missing+=("SFTP_KEY or SFTP_PASSWORD")
fi

if [ "${#missing[@]}" -gt 0 ]; then
	say_error "Missing GitHub Actions secrets: ${missing[*]}" >&2
	echo "Add them as repository secrets: Settings → Secrets and variables → Actions." >&2
	echo "This workflow has no credentials of its own. Prefer SFTP_KEY (unencrypted private key). SFTP_PORT defaults to 22 when unset. SFTP_REMOTE_PLUGIN_PATH is optional." >&2
	exit 1
fi

if ! printf '%s' "$host" | grep -Eq '^[A-Za-z0-9.-]+$'; then
	say_error "SFTP_HOST must be a hostname or IP, without https://, a username, or a path." >&2
	exit 1
fi

if ! printf '%s' "$user" | grep -Eq '^[A-Za-z0-9._-]+$'; then
	say_error "SFTP_USER contains characters that are not allowed." >&2
	exit 1
fi

if [ -z "$port_raw" ]; then
	port=22
else
	if ! printf '%s' "$port_raw" | grep -Eq '^[0-9]+$'; then
		say_error "SFTP_PORT must be a TCP port from 1 to 65535." >&2
		exit 1
	fi
	port=$port_raw
	if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
		say_error "SFTP_PORT must be a TCP port from 1 to 65535." >&2
		exit 1
	fi
fi

auth=password
if [ -n "$key" ]; then
	auth=key
	case "$key" in
		*"PRIVATE KEY"*) ;;
		*)
			say_error "SFTP_KEY is set but does not look like a private key. Paste the full key, including the BEGIN and END lines, with no passphrase." >&2
			exit 1
			;;
	esac
	case "$key" in
		*ENCRYPTED*)
			say_error "SFTP_KEY looks encrypted. Generate a dedicated deploy key with an empty passphrase: ssh-keygen -m PEM -t rsa -b 4096 -N \"\" -C \"refungi-github-deploy\"" >&2
			exit 1
			;;
	esac

	keyfile=$(mktemp)
	chmod 600 "$keyfile"
	trap 'rm -f "$keyfile"' EXIT
	printf '%s\n' "$key" >"$keyfile"
	key_error=$(mktemp)
	if ! ssh-keygen -y -P "" -f "$keyfile" >/dev/null 2>"$key_error"; then
		say_error "SFTP_KEY was rejected by ssh-keygen. Use an unencrypted private key (no passphrase). Example: ssh-keygen -m PEM -t rsa -b 4096 -N \"\" -C \"refungi-github-deploy\"" >&2
		echo "Do not commit that private key. Store it only in the SFTP_KEY secret." >&2
		cat "$key_error" >&2
		rm -f "$key_error"
		exit 1
	fi
	rm -f "$key_error"
	if [ -n "$password" ]; then
		say_notice "Both SFTP_KEY and SFTP_PASSWORD are set. Using SFTP_KEY and ignoring the password." >&2
	fi
fi

theme_path=$(bash "$script_dir/validate-deploy-target.sh" theme "$theme_raw")

deploy_plugin=false
plugin_path=""
if [ -n "$plugin_raw" ]; then
	plugin_path=$(bash "$script_dir/validate-deploy-target.sh" plugin "$plugin_raw")
	deploy_plugin=true
else
	say_notice "SFTP_REMOTE_PLUGIN_PATH is not set. The child theme will deploy and the custom plugin step will be skipped." >&2
fi

echo "Deploy preflight ok. auth=${auth} host=${host} port=${port} user=${user} theme=${theme_path} plugin=${plugin_path:-skipped}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "auth=${auth}"
		echo "port=${port}"
		echo "theme_path=${theme_path}"
		echo "deploy_plugin=${deploy_plugin}"
		echo "plugin_path=${plugin_path}"
	} >>"$GITHUB_OUTPUT"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "### Deploy preflight"
		echo "- Auth: \`${auth}\`"
		echo "- Host: \`${host}\`"
		echo "- Port: \`${port}\`"
		echo "- User: \`${user}\`"
		echo "- Theme path: \`${theme_path}\`"
		if [ "$deploy_plugin" = "true" ]; then
			echo "- Plugin path: \`${plugin_path}\`"
		else
			echo "- Plugin path: skipped (SFTP_REMOTE_PLUGIN_PATH unset)"
		fi
	} >>"$GITHUB_STEP_SUMMARY"
fi
