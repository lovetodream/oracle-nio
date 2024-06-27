#!/usr/bin/env bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the OracleNIO open source project
##
## Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
## Licensed under Apache License v2.0
##
## See LICENSE for license information
## See CONTRIBUTORS.md for the list of OracleNIO project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

set -euo pipefail

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

CURRENT_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(git -C "${CURRENT_SCRIPT_DIR}" rev-parse --show-toplevel)"
UNACCEPTABLE_LANGUAGE_PATTERNS_PATH="${CURRENT_SCRIPT_DIR}/unacceptable-language.txt"

log "Checking for unacceptable language..."
PATHS_WITH_UNACCEPTABLE_LANGUAGE=$(git -C "${REPO_ROOT}" grep \
  -l -F -w \
  -f "${UNACCEPTABLE_LANGUAGE_PATTERNS_PATH}" \
  -- \
  ":(exclude)${UNACCEPTABLE_LANGUAGE_PATTERNS_PATH}" \
) || true | /usr/bin/paste -s -d " " -

if [ -n "${PATHS_WITH_UNACCEPTABLE_LANGUAGE}" ]; then
  fatal "❌ Found unacceptable language in files: ${PATHS_WITH_UNACCEPTABLE_LANGUAGE}."
fi

log "✅ Found no unacceptable language."
