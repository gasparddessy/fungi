#!/usr/bin/env bash
# Flags shared by the password deploy path. The SSH key path passes the same
# flag string as ARGS in .github/workflows/deploy.yml. Tests compare the two.
# --delete mirrors only the destination directory rsync was given. Callers must
# pass a path that already passed validate-deploy-target.sh and remote-target-guard.sh.
# shellcheck disable=SC2034 # sourced by the password deploy and the tests
RSYNC_DELETE_FLAGS="-rlzvc --delete --no-owner --no-group --omit-dir-times --chmod=D755,F644"
