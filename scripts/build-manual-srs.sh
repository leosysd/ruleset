#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANUAL_DIR="${MANUAL_DIR:-$ROOT_DIR/manual}"

log() {
  printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

compile_json() {
  local json="$1" srs
  case "$json" in
    *.json) ;;
    *) die "not a JSON rule-set: $json" ;;
  esac

  [ -s "$json" ] || die "JSON rule-set not found or empty: $json"
  srs="${json%.json}.srs"

  log "compile $(realpath --relative-to="$ROOT_DIR" "$json") -> $(realpath --relative-to="$ROOT_DIR" "$srs")"
  rm -f "$srs"
  sing-box rule-set compile -o "$srs" "$json" >/dev/null
  [ -s "$srs" ] || die "empty compiled srs: $srs"
}

main() {
  local json found=0
  need_cmd sing-box

  if [ "$#" -gt 0 ]; then
    for json in "$@"; do
      compile_json "$json"
      found=1
    done
  elif [ -d "$MANUAL_DIR" ]; then
    while IFS= read -r json; do
      compile_json "$json"
      found=1
    done < <(find "$MANUAL_DIR" -maxdepth 1 -type f -name '*.json' | sort)
  fi

  [ "$found" -eq 1 ] || log "no manual JSON rule-set found"
}

main "$@"
