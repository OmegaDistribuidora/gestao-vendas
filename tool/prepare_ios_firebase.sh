#!/bin/sh
set -eu

project_dir="${CM_BUILD_DIR:-$(pwd)}"
target_file="$project_dir/ios/Runner/GoogleService-Info.plist"

if [ -f "$target_file" ]; then
  echo "GoogleService-Info.plist ja esta disponivel."
  exit 0
fi

if [ -z "${GOOGLE_SERVICE_INFO_PLIST_BASE64:-}" ]; then
  echo "Variavel GOOGLE_SERVICE_INFO_PLIST_BASE64 nao configurada." >&2
  exit 1
fi

printf '%s' "$GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 --decode > "$target_file"
echo "GoogleService-Info.plist preparado para o build iOS."
