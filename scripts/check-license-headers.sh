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

EXPECTED_FILE_HEADER_TEMPLATE="@@===----------------------------------------------------------------------===@@
@@
@@ This source file is part of the OracleNIO open source project
@@
@@ Copyright (c) YEARS Timo Zacherl and the OracleNIO project authors
@@ Licensed under Apache License v2.0
@@
@@ See LICENSE for license information
@@ See CONTRIBUTORS.md for the list of OracleNIO project authors
@@
@@ SPDX-License-Identifier: Apache-2.0
@@
@@===----------------------------------------------------------------------===@@"

PATHS_WITH_MISSING_LICENSE=( )

read -ra PATHS_TO_CHECK_FOR_LICENSE <<< "$( \
  git -C "${REPO_ROOT}" ls-files -z \
  ":(exclude).gitignore" \
  ":(exclude).spi.yml" \
  ":(exclude).swift-format" \
  ":(exclude).mailmap" \
  ":(exclude).github/*" \
  ":(exclude)CODE_OF_CONDUCT.md" \
  ":(exclude)CONTRIBUTING.md" \
  ":(exclude)CONTRIBUTORS.md" \
  ":(exclude)LICENSE" \
  ":(exclude)NOTICE.txt" \
  ":(exclude)Package.swift" \
  ":(exclude)Package.resolved" \
  ":(exclude)README.md" \
  ":(exclude)SECURITY.md" \
  ":(exclude)scripts/unacceptable-language.txt" \
  ":(exclude)docker/*" \
  ":(exclude)Makefile" \
  ":(exclude)docker-compose.yaml" \
  ":(exclude)CODEOWNERS" \
  ":(exclude)codecov.yml" \
  ":(exclude)**/*.docc/*" \
  ":(exclude)**/.gitignore" \
  ":(exclude)**/Package.swift" \
  ":(exclude)**/Package.resolved" \
  ":(exclude)**/README.md" \
  ":(exclude)**/docker-compose.yaml" \
  ":(exclude)**/docker/*" \
  ":(exclude)**/.dockerignore" \
  ":(exclude)**/Makefile" \
  ":(exclude)**/*.pb.swift" \
  ":(exclude)**/*.proto" \
  ":(exclude)Tests/IntegrationTests/Data/*" \
  ":(exclude)Sources/VendoredConnectionPoolModule/*" \
  | xargs -0 \
)"

for FILE_PATH in "${PATHS_TO_CHECK_FOR_LICENSE[@]}"; do
  FILE_BASENAME=$(basename -- "${FILE_PATH}")
  FILE_EXTENSION="${FILE_BASENAME##*.}"

  case "${FILE_EXTENSION}" in
    swift) EXPECTED_FILE_HEADER=$(sed -e 's|@@|//|g' <<<"${EXPECTED_FILE_HEADER_TEMPLATE}") ;;
    yml) EXPECTED_FILE_HEADER=$(sed -e 's|@@|##|g' <<<"${EXPECTED_FILE_HEADER_TEMPLATE}") ;;
    sh) EXPECTED_FILE_HEADER=$(cat <(echo '#!/usr/bin/env bash') <(sed -e 's|@@|##|g' <<<"${EXPECTED_FILE_HEADER_TEMPLATE}")) ;;
    *) fatal "Unsupported file extension for file (exclude or update this script): ${FILE_PATH}" ;;
  esac
  EXPECTED_FILE_HEADER_LINECOUNT=$(wc -l <<<"${EXPECTED_FILE_HEADER}")

  FILE_HEADER=$(head -n "${EXPECTED_FILE_HEADER_LINECOUNT}" "${FILE_PATH}")
  NORMALIZED_FILE_HEADER=$(
    echo "${FILE_HEADER}" \
    | sed -e 's/202[345]-202[345]/YEARS/' -e 's/202[345]/YEARS/' \
  )

  if ! diff -u \
    --label "Expected header" <(echo "${EXPECTED_FILE_HEADER}") \
    --label "${FILE_PATH}" <(echo "${NORMALIZED_FILE_HEADER}")
  then
    PATHS_WITH_MISSING_LICENSE+=("${FILE_PATH} ")
  fi
done

if [ "${#PATHS_WITH_MISSING_LICENSE[@]}" -gt 0 ]; then
  fatal "❌ Found missing license header in files: ${PATHS_WITH_MISSING_LICENSE[*]}."
fi

log "✅ Found no files with missing license header."
