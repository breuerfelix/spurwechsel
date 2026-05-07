#!/usr/bin/env bash
set -euo pipefail

print_usage() {
  cat <<'EOF'
Usage:
  spurwechsel [PATH]
  spur [PATH]

Examples:
  spurwechsel .
  spur .
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_usage
  exit 0
fi

if [[ "$#" -gt 1 ]]; then
  echo "spurwechsel: expected zero or one path argument" >&2
  print_usage >&2
  exit 2
fi

target_path="${1:-.}"
if ! target_dir="$(cd "$target_path" 2>/dev/null && pwd -P)"; then
  echo "spurwechsel: cannot access path: $target_path" >&2
  exit 2
fi

resolve_git_path() {
  local arg="$1"
  local out
  if ! out="$(git rev-parse --path-format=absolute "$arg" 2>/dev/null)"; then
    return 1
  fi
  out="${out%$'\n'}"
  printf '%s' "$out"
}

workspace_root=""
project_root=""
if workspace_root="$(cd "$target_dir" && resolve_git_path --show-toplevel)"; then
  git_common_dir=""
  if git_common_dir="$(cd "$target_dir" && resolve_git_path --git-common-dir)"; then
    if [[ "$git_common_dir" == */.git ]]; then
      project_root="$(cd "${git_common_dir%/.git}" && pwd -P)"
    else
      project_root="$workspace_root"
    fi
  else
    project_root="$workspace_root"
  fi
else
  workspace_root="$target_dir"
  project_root="$target_dir"
fi

base64url() {
  local value="$1"
  printf '%s' "$value" \
    | /usr/bin/base64 \
    | tr -d '\n' \
    | tr '+/' '-_' \
    | tr -d '='
}

workspace_b64="$(base64url "$workspace_root")"
project_b64="$(base64url "$project_root")"
deep_link="spurwechsel://open-workspace?workspace_b64=${workspace_b64}&project_b64=${project_b64}"

open "$deep_link"
open -b dev.breuer.spurwechsel
