#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST_DIR="${LIST_DIR:-$ROOT_DIR/lists}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/work}"
SOURCE_URL="${SOURCE_URL:-https://github.com/SagerNet/sing-geosite/tree/rule-set}"

ZIP_FILE="$WORK_DIR/rule-set.zip"
EXTRACT_DIR="$WORK_DIR/extract"
PARTS_DIR="$WORK_DIR/parts"
STATE_DIR="$WORK_DIR/state"

DIRECT_LIST="$LIST_DIR/direct.txt"
PROXY_LIST="$LIST_DIR/proxy.txt"

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

normalize_download_url() {
  local url="$1" rest owner repo branch
  case "$url" in
    https://github.com/*/tree/*)
      rest="${url#https://github.com/}"
      owner="${rest%%/*}"
      rest="${rest#*/}"
      repo="${rest%%/*}"
      branch="${rest#*/tree/}"
      printf 'https://github.com/%s/%s/archive/refs/heads/%s.zip\n' "$owner" "$repo" "$branch"
      ;;
    *)
      printf '%s\n' "$url"
      ;;
  esac
}

clean_line() {
  local line="$1"
  line="${line%%#*}"
  line="$(printf '%s' "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  case "$line" in
    ""|direct:|DIRECT:|proxy:|PROXY:) return 1 ;;
  esac
  printf '%s\n' "$line"
}

normalize_rule_name() {
  local rule="$1"
  rule="${rule##*/}"
  rule="${rule%.json}"
  case "$rule" in
    *.srs) printf '%s\n' "$rule" ;;
    geosite-*) printf '%s.srs\n' "${rule%.srs}" ;;
    *) printf 'geosite-%s.srs\n' "$rule" ;;
  esac
}

list_rules() {
  local list_file="$1" line clean
  [ -f "$list_file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    clean="$(clean_line "$line")" || continue
    normalize_rule_name "$clean"
  done < "$list_file" | sort -u
}

strip_geosite_name() {
  local file="$1"
  file="${file##*/}"
  file="${file%.srs}"
  file="${file#geosite-}"
  printf '%s\n' "$file"
}

find_rule_file() {
  local file="$1"
  find "$EXTRACT_DIR" -type f -name "$file" | sort | sed -n '1p'
}

download_source() {
  local url
  url="$(normalize_download_url "$SOURCE_URL")"
  mkdir -p "$WORK_DIR"
  rm -f "$ZIP_FILE.tmp"
  log "download source: $url"
  curl -fL --retry 3 --retry-delay 2 -o "$ZIP_FILE.tmp" "$url"
  [ -s "$ZIP_FILE.tmp" ] || die "downloaded zip is empty"
  mv -f "$ZIP_FILE.tmp" "$ZIP_FILE"
}

prepare_workdir() {
  rm -rf "$EXTRACT_DIR" "$PARTS_DIR" "$STATE_DIR"
  mkdir -p "$EXTRACT_DIR" "$PARTS_DIR" "$STATE_DIR" "$DIST_DIR"
  rm -f "$DIST_DIR"/* "$DIST_DIR"/.[!.]*
  unzip -q "$ZIP_FILE" -d "$EXTRACT_DIR"
}

scan_rules() {
  local rule src
  find "$EXTRACT_DIR" -type f -name 'geosite-*.srs' -exec basename {} \; | sort -u > "$STATE_DIR/available.txt"
  list_rules "$DIRECT_LIST" > "$STATE_DIR/direct.selected"
  list_rules "$PROXY_LIST" > "$STATE_DIR/proxy.selected"

  if [ -s "$STATE_DIR/direct.selected" ] && [ -s "$STATE_DIR/proxy.selected" ]; then
    grep -xF -f "$STATE_DIR/direct.selected" "$STATE_DIR/proxy.selected" | sort -u > "$STATE_DIR/conflict.txt" || true
  else
    : > "$STATE_DIR/conflict.txt"
  fi

  : > "$STATE_DIR/found.txt"
  : > "$STATE_DIR/missing.txt"
  for rule in $(cat "$STATE_DIR/direct.selected" "$STATE_DIR/proxy.selected" | sort -u); do
    src="$(grep -x "$rule" "$STATE_DIR/available.txt" || true)"
    if [ -n "$src" ]; then
      printf '%s\n' "$rule" >> "$STATE_DIR/found.txt"
    else
      printf '%s\n' "$rule" >> "$STATE_DIR/missing.txt"
    fi
  done

  {
    printf 'Found rules:\n'
    sed 's/^/  /' "$STATE_DIR/found.txt"
    printf '\nMissing rules:\n'
    sed 's/^/  /' "$STATE_DIR/missing.txt"
    printf '\nConflict rules:\n'
    sed 's/^/  /' "$STATE_DIR/conflict.txt"
  } > "$STATE_DIR/scan-preview.txt"
}

decompile_group() {
  local group="$1" list_file="$2" out_dir="$PARTS_DIR/$group"
  local count=0 rule src dst safe
  mkdir -p "$out_dir"
  while IFS= read -r rule || [ -n "$rule" ]; do
    [ -n "$rule" ] || continue
    src="$(find_rule_file "$rule")"
    if [ -z "$src" ]; then
      log "missing $group rule: $(strip_geosite_name "$rule")"
      continue
    fi
    safe="$(printf '%s' "$rule" | sed 's/[^A-Za-z0-9_.-]/_/g')"
    dst="$out_dir/$(printf '%04d' "$count")-${safe%.srs}.json"
    log "decompile $group: $(strip_geosite_name "$rule")"
    sing-box rule-set decompile -o "$dst" "$src" >/dev/null
    [ -s "$dst" ] || die "empty decompiled json: $dst"
    count=$((count + 1))
  done < "$list_file"
  printf '%s\n' "$count"
}

write_empty_source_json() {
  local path="$1"
  printf '{\n  "version": 1,\n  "rules": []\n}\n' > "$path"
}

json_to_mosdns_txt() {
  local json="$1" txt="$2"
  jq -r '
    .rules[]? |
    (.domain[]? | "full:" + .),
    (.domain_suffix[]? | "domain:" + .),
    (.domain_keyword[]? | "keyword:" + .),
    (.domain_regex[]? | "regexp:" + .)
  ' "$json" | sed '/^$/d' | sort -u > "$txt"
}

build_group() {
  local group="$1"
  local selected="$STATE_DIR/$group.selected" source_list="$WORK_DIR/$group.list"
  local part_dir="$PARTS_DIR/$group" merged="$WORK_DIR/$group-geosite.source.json"
  local srs="$DIST_DIR/$group-geosite.srs" json="$DIST_DIR/$group-geosite.json"
  local txt="$DIST_DIR/$group-geosite.txt" count

  cp "$selected" "$source_list"
  if [ "$group" = "proxy" ] && [ -s "$STATE_DIR/conflict.txt" ]; then
    grep -vxF -f "$STATE_DIR/conflict.txt" "$source_list" > "$source_list.filtered" || true
    mv -f "$source_list.filtered" "$source_list"
  fi

  count="$(decompile_group "$group" "$source_list")"
  if [ "$count" -gt 0 ]; then
    log "merge $group rule-sets"
    sing-box rule-set merge -C "$part_dir" "$merged" >/dev/null
  else
    log "no $group rules selected; write empty source json"
    write_empty_source_json "$merged"
  fi
  [ -s "$merged" ] || die "empty merged json: $merged"

  log "compile $group-geosite.srs"
  rm -f "$srs"
  sing-box rule-set compile -o "$srs" "$merged" >/dev/null
  [ -s "$srs" ] || die "empty compiled srs: $srs"

  log "decompile compiled $group-geosite.srs"
  rm -f "$json"
  sing-box rule-set decompile -o "$json" "$srs" >/dev/null
  [ -s "$json" ] || die "empty final json: $json"
  json_to_mosdns_txt "$json" "$txt"
}

main() {
  need_cmd curl
  need_cmd unzip
  need_cmd jq
  need_cmd sing-box

  [ -s "$DIRECT_LIST" ] || die "direct list not found: $DIRECT_LIST"
  [ -s "$PROXY_LIST" ] || die "proxy list not found: $PROXY_LIST"

  download_source
  prepare_workdir
  scan_rules
  build_group direct
  build_group proxy
  log "build completed: $DIST_DIR"
}

main "$@"
