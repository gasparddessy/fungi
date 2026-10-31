#!/usr/bin/env bash
# Plain FTP deploy for o2switch when SSH port 22 is blocked.
#
# Autorisation SSH drops GitHub-hosted runners on port 22. The same allowlist
# drops FTPS data connections after the directory listing, so explicit FTPS
# is not a working fallback. Port 21 plain FTP is open.
#
# lftp mirror --reverse --delete is limited to a directory that already
# passed validate-deploy-target.sh. The parent (wp-content/themes or
# wp-content/plugins) must already exist. Only the final directory is created.
# The password is passed through LFTP_PASSWORD (--env-password), not argv.
#
# o2switch chroots the FTP login to the account home. A path that starts
# with /home/<user>/ is the SSH filesystem path and is not visible here.
# This script drops that prefix and syncs the remainder (public_html/...).
# Port 22 does not use this script, so SSH still receives absolute paths.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/log.sh"

: "${SFTP_HOST:?}"
: "${SFTP_USER:?}"
: "${SFTP_PASSWORD:?}"
: "${THEME_PATH:?}"
port="${SFTP_PORT:-21}"
deploy_plugin="${DEPLOY_PLUGIN:-false}"
lftp_bin="${LFTP_BIN:-lftp}"

if ! printf '%s' "$SFTP_HOST" | grep -Eq '^[A-Za-z0-9.-]+$'; then
	say_error "SFTP_HOST must be a hostname or IP, without a scheme or path."
	exit 1
fi
if ! printf '%s' "$SFTP_USER" | grep -Eq '^[A-Za-z0-9._-]+$'; then
	say_error "SFTP_USER contains characters that are not allowed."
	exit 1
fi
if ! printf '%s' "$port" | grep -Eq '^[0-9]+$' || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
	say_error "SFTP_PORT must be a TCP port from 1 to 65535."
	exit 1
fi
# Production deploys are port 21 only. The integration test publishes a local
# server on a high port and sets REFUGI_FTP_TEST_PORT to that same port.
# The GitHub workflow does not set REFUGI_FTP_TEST_PORT.
if [ "$port" != "21" ] && [ "${REFUGI_FTP_TEST_PORT:-}" != "$port" ]; then
	say_error "ftp-password-deploy.sh only runs when SFTP_PORT is 21. Port ${port} stays on the SSH deploy path."
	exit 1
fi

if ! command -v "$lftp_bin" >/dev/null 2>&1; then
	sudo DEBIAN_FRONTEND=noninteractive apt-get update
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y lftp
	lftp_bin=lftp
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"
# These settings must be in the rc file. lftp applies -e commands only after
# it has already opened the control connection, which is too late to refuse TLS.
cat >"$work/.lftprc" <<'EOF'
set cmd:fail-exit yes
set cmd:trace no
set ftp:ssl-allow false
set ftp:ssl-force false
set ftp:passive-mode true
set ftp:prefer-epsv false
set net:timeout 30
set net:max-retries 2
set net:reconnect-interval-base 5
set xfer:clobber true
EOF

FTP_LAST_STDOUT=""
FTP_LAST_STDERR=""

print_scrubbed() {
	local text="$1"
	if [ -z "$text" ]; then
		return 0
	fi
	printf '%s\n' "$text" | grep -F -v -- "$SFTP_PASSWORD" || true
}

# Turn an SSH-style absolute path into a path relative to the FTP login root.
# Relative paths are unchanged. The result is validated again, so bridge and
# bridge-child are still refused.
ftp_login_path() {
	local kind="$1"
	local raw="$2"
	local path home_prefix
	# Command substitution does not abort the script on failure. Check it.
	if ! path=$(bash "$script_dir/validate-deploy-target.sh" "$kind" "$raw"); then
		exit 1
	fi
	path="${path%/}"
	home_prefix="/home/${SFTP_USER}/"
	case "$path" in
		"$home_prefix"*)
			path="${path#"$home_prefix"}"
			say_notice "FTP is chrooted to the account home. Using ${path} instead of ${home_prefix}${path}."
			;;
		/home/*)
			say_error "SFTP_PORT 21 paths are relative to the FTP login root. ${path} is not under /home/${SFTP_USER}. Example: public_html/wp-content/themes/refungi-child."
			exit 1
			;;
		/*)
			path="${path#/}"
			;;
	esac
	if ! path=$(bash "$script_dir/validate-deploy-target.sh" "$kind" "$path"); then
		exit 1
	fi
	printf '%s' "${path%/}"
}

# Run the lftp commands on stdin. The password stays in the environment.
ftp_exec() {
	local stdout_file stderr_file cmd_file status
	stdout_file=$(mktemp)
	stderr_file=$(mktemp)
	cmd_file=$(mktemp)
	cat >"$cmd_file"
	set +e
	LFTP_PASSWORD="$SFTP_PASSWORD" \
		HOME="$work" \
		"$lftp_bin" --env-password -u "$SFTP_USER" -p "$port" \
		-e "source ${cmd_file}" \
		"ftp://${SFTP_HOST}" >"$stdout_file" 2>"$stderr_file"
	status=$?
	FTP_LAST_STDOUT=$(tr -d '\r' <"$stdout_file")
	FTP_LAST_STDERR=$(tr -d '\r' <"$stderr_file")
	rm -f "$stdout_file" "$stderr_file" "$cmd_file"
	# return 1 under set -e would exit the whole deploy, not just this call.
	FTP_LAST_STATUS=$status
	set -e
	return 0
}

sync_one() {
	local kind="$1"
	local local_dir="$2"
	local remote_raw="$3"
	local remote parent base listing status

	if ! remote=$(ftp_login_path "$kind" "$remote_raw"); then
		exit 1
	fi
	if [ -z "$remote" ]; then
		say_error "Remote ${kind} path is empty."
		exit 1
	fi
	parent=$(dirname "$remote")
	base=$(basename "$remote")
	local_dir="${local_dir%/}"

	if [ ! -d "$local_dir" ]; then
		say_error "Local ${kind} directory is missing: ${local_dir}"
		exit 1
	fi
	case "$local_dir" in
		*'"'* | *'!'* | *'$'* | *'`'*)
			say_error "Local ${kind} path contains a character the FTP script cannot quote safely."
			exit 1
			;;
	esac

	ftp_exec <<EOF
cd "${parent}" || exit 1
shell "echo PARENT_OK"
set cmd:fail-exit no
cls -ld "${base}"
bye
EOF
	status=$FTP_LAST_STATUS

	if ! printf '%s\n' "$FTP_LAST_STDOUT" | grep -q '^PARENT_OK$'; then
		if printf '%s\n' "$FTP_LAST_STDERR" | grep -q 'Login failed'; then
			say_error "FTP login failed for ${SFTP_USER}@${SFTP_HOST} port 21. Check SFTP_USER and SFTP_PASSWORD."
		else
			say_error "Parent directory does not exist on the FTP server: ${parent}"
			echo "WordPress must already be installed so that directory exists. This job will not create wp-content, themes, or plugins." >&2
		fi
		print_scrubbed "$FTP_LAST_STDERR" >&2
		exit 1
	fi

	listing=$(printf '%s\n' "$FTP_LAST_STDOUT" | grep -v '^PARENT_OK$' | grep -v '^total ' | head -n 1 || true)
	case "$listing" in
		"")
			if [ "$status" -eq 0 ]; then
				say_error "FTP listing for ${remote} was empty. Refusing to create or sync it."
				exit 1
			fi
			echo "Creating ${remote}"
			ftp_exec <<EOF
cd "${parent}" || exit 1
mkdir "${base}"
bye
EOF
			status=$FTP_LAST_STATUS
			if [ "$status" -ne 0 ]; then
				say_error "Could not create ${remote}"
				print_scrubbed "$FTP_LAST_STDERR" >&2
				exit 1
			fi
			;;
		l*)
			say_error "Refusing to deploy: ${remote} is a symlink."
			exit 1
			;;
		d*)
			echo "Remote directory ok: ${remote}"
			;;
		*)
			say_error "Refusing to deploy: ${remote} exists and is not a directory."
			exit 1
			;;
	esac

	echo "Syncing ${kind} to ${remote}"
	ftp_exec <<EOF
mirror --reverse --delete --verbose --no-perms \
  --exclude-glob node_modules/** \
  --exclude-glob .git/** \
  --exclude-glob .github/** \
  "${local_dir}/" \
  "${remote}/"
bye
EOF
	status=$FTP_LAST_STATUS
	if [ "$status" -ne 0 ]; then
		say_error "FTP sync failed for ${remote}"
		print_scrubbed "$FTP_LAST_STDERR" >&2
		exit 1
	fi
	print_scrubbed "$FTP_LAST_STDOUT"
}

repo_root=$(cd "$script_dir/../.." && pwd)
sync_one theme "$repo_root/themes/refungi-child" "$THEME_PATH"

if [ "$deploy_plugin" = "true" ]; then
	sync_one plugin "$repo_root/plugins/refungi-custom" "${PLUGIN_PATH:-}"
else
	echo "SFTP_REMOTE_PLUGIN_PATH is unset. Custom plugin was not synced."
fi

unset LFTP_PASSWORD
