#!/usr/bin/env bash
# Runs `helm lint` on any chart that contains a changed file.
# Replicates gruntwork-io/pre-commit helmlint logic but adds /opt/homebrew/bin
# to PATH so it works on Apple Silicon Macs where Homebrew lives there.
set -e

export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH

readonly cwd_abspath="$(realpath "$PWD")"

contains_element() {
  local -r match="$1"; shift
  for e in "$@"; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

chart_path() {
  local -r f="$(realpath "$1")"
  local -r d="$(dirname "$f")"

  [[ "$f" == "$cwd_abspath" ]] && echo "" && return 0
  [[ "$(basename "$f")" == "Chart.yaml" ]] && echo "$d" && return 0
  [[ -f "$f/Chart.yaml" ]] && echo "$f" && return 0
  [[ -f "$d/Chart.yaml" ]] && echo "$d" && return 0

  chart_path "$d"
}

seen_chart_paths=()

for file in "$@"; do
  file_chart_path=$(chart_path "$file")
  [[ -z "$file_chart_path" ]] && continue
  contains_element "$file_chart_path" "${seen_chart_paths[@]}" && continue

  if [[ -f "$file_chart_path/linter_values.yaml" ]]; then
    helm lint -f "$file_chart_path/values.yaml" -f "$file_chart_path/linter_values.yaml" "$file_chart_path"
  else
    helm lint "$file_chart_path"
  fi
  seen_chart_paths+=("$file_chart_path")
done
