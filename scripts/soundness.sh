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
NUM_CHECKS_FAILED=0

FIX_FORMAT=""
for arg in "$@"; do
  if [ "$arg" == "--fix" ]; then
    FIX_FORMAT="--fix"
  fi
done

SCRIPT_PATHS=(
  "${CURRENT_SCRIPT_DIR}/check-for-broken-symlinks.sh"
  "${CURRENT_SCRIPT_DIR}/check-for-unacceptable-language.sh"
  "${CURRENT_SCRIPT_DIR}/check-license-headers.sh"
)

for SCRIPT_PATH in "${SCRIPT_PATHS[@]}"; do
  log "Running ${SCRIPT_PATH}..."
  if ! bash "${SCRIPT_PATH}"; then
    ((NUM_CHECKS_FAILED+=1))
  fi
done

log "Running swift-format..."
bash "${CURRENT_SCRIPT_DIR}"/run-swift-format.sh $FIX_FORMAT > /dev/null
FORMAT_EXIT_CODE=$?
if [ $FORMAT_EXIT_CODE -ne 0 ]; then
  ((NUM_CHECKS_FAILED+=1))
fi

if [ "${NUM_CHECKS_FAILED}" -gt 0 ]; then
  fatal "❌ ${NUM_CHECKS_FAILED} soundness check(s) failed."
fi

log "✅ All soundness check(s) passed."
