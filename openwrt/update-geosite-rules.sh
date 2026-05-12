#!/bin/sh

set -u

NAME="update-geosite-rules"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/leosysd/ruleset/main/dist}"

SINGBOX_DIR="/etc/sing-box/rule-set"
MOSDNS_DIR="/etc/mosdns/rule"
WORK_DIR="/etc/sing-box/rule-set/github-ruleset-updater"
TMP_DIR="$WORK_DIR/tmp"
LOCK_FILE="$WORK_DIR/update.lock"
LOG_FILE="/tmp/update-geosite-rules.log"
CRON_FILE="/etc/crontabs/root"
CRON_MARK="# update-geosite-rules"

SINGBOX_RESTART="${SINGBOX_RESTART:-0}"
MOSDNS_RESTART="${MOSDNS_RESTART:-0}"

log() {
	local line
	line="$(date '+%Y-%m-%d %H:%M:%S') [$NAME] $*"
	mkdir -p "$(dirname "$LOG_FILE")"
	printf '%s\n' "$line" >> "$LOG_FILE"
	printf '%s\n' "$line" >&2
}

die() {
	log "ERROR: $*"
	exit 1
}

usage() {
	cat <<EOF
Usage: /usr/bin/update-geosite-rules <command>

Commands:
  update        Download and atomically install generated rule files
  status        Show generated rule file status
  install-cron  Install daily cron job at 07:45
  remove-cron   Remove installed cron job
  clear-log     Clear log file

Environment:
  REPO_RAW=https://raw.githubusercontent.com/leosysd/ruleset/main/dist
  SINGBOX_RESTART=0|1
  MOSDNS_RESTART=0|1
EOF
}

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

ensure_dirs() {
	mkdir -p "$SINGBOX_DIR" "$MOSDNS_DIR" "$WORK_DIR" "$TMP_DIR"
}

fetch_file() {
	local name="$1"
	local tmp="$TMP_DIR/$name.tmp"
	local url="$REPO_RAW/$name"
	rm -f "$tmp"
	log "download $url"
	if command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -O "$tmp" "$url" >/dev/null 2>&1 && [ -s "$tmp" ] && return 0
	fi
	rm -f "$tmp"
	if command -v wget >/dev/null 2>&1; then
		wget -O "$tmp" "$url" >/dev/null 2>&1 && [ -s "$tmp" ] && return 0
	fi
	rm -f "$tmp"
	if command -v curl >/dev/null 2>&1; then
		curl -fL -o "$tmp" "$url" >/dev/null 2>&1 && [ -s "$tmp" ] && return 0
	fi
	return 1
}

install_file() {
	local tmp="$1"
	local final="$2"
	local bak="$final.bak"
	[ -s "$tmp" ] || die "downloaded file is empty: $tmp"
	if [ -e "$final" ]; then
		cp -f "$final" "$bak" || die "failed to backup $final"
	fi
	mv -f "$tmp" "$final" || die "failed to replace $final"
	log "installed $final"
}

update_rules_locked() {
	ensure_dirs

	fetch_file direct-geosite.srs || die "failed to download direct-geosite.srs"
	fetch_file proxy-geosite.srs || die "failed to download proxy-geosite.srs"
	fetch_file direct-geosite.json || die "failed to download direct-geosite.json"
	fetch_file proxy-geosite.json || die "failed to download proxy-geosite.json"
	fetch_file direct-geosite.txt || die "failed to download direct-geosite.txt"
	fetch_file proxy-geosite.txt || die "failed to download proxy-geosite.txt"

	install_file "$TMP_DIR/direct-geosite.srs.tmp" "$SINGBOX_DIR/direct-geosite.srs"
	install_file "$TMP_DIR/proxy-geosite.srs.tmp" "$SINGBOX_DIR/proxy-geosite.srs"
	install_file "$TMP_DIR/direct-geosite.json.tmp" "$SINGBOX_DIR/direct-geosite.json"
	install_file "$TMP_DIR/proxy-geosite.json.tmp" "$SINGBOX_DIR/proxy-geosite.json"
	install_file "$TMP_DIR/direct-geosite.txt.tmp" "$MOSDNS_DIR/direct-geosite.txt"
	install_file "$TMP_DIR/proxy-geosite.txt.tmp" "$MOSDNS_DIR/proxy-geosite.txt"

	if [ "$SINGBOX_RESTART" = "1" ] && [ -x /etc/init.d/sing-box ]; then
		log "restart sing-box"
		/etc/init.d/sing-box restart >> "$LOG_FILE" 2>&1 || die "failed to restart sing-box"
	fi
	if [ "$MOSDNS_RESTART" = "1" ] && [ -x /etc/init.d/mosdns ]; then
		log "restart mosdns"
		/etc/init.d/mosdns restart >> "$LOG_FILE" 2>&1 || die "failed to restart mosdns"
	fi

	rm -rf "$TMP_DIR"
	log "update completed"
}

update_rules() {
	ensure_dirs
	need_cmd flock
	(
		flock -n 9 || die "another update is already running"
		update_rules_locked
	) 9>"$LOCK_FILE"
}

status_file() {
	local label="$1"
	local path="$2"
	if [ -s "$path" ]; then
		printf '%s=yes %s bytes %s\n' "$label" "$(wc -c < "$path" | tr -d ' ')" "$path"
	else
		printf '%s=no %s\n' "$label" "$path"
	fi
}

status_rules() {
	status_file direct_srs "$SINGBOX_DIR/direct-geosite.srs"
	status_file proxy_srs "$SINGBOX_DIR/proxy-geosite.srs"
	status_file direct_json "$SINGBOX_DIR/direct-geosite.json"
	status_file proxy_json "$SINGBOX_DIR/proxy-geosite.json"
	status_file direct_txt "$MOSDNS_DIR/direct-geosite.txt"
	status_file proxy_txt "$MOSDNS_DIR/proxy-geosite.txt"
	printf 'log_file=%s\n' "$LOG_FILE"
}

install_cron() {
	local tmp
	mkdir -p /etc/crontabs
	touch "$CRON_FILE"
	tmp="$CRON_FILE.tmp.$$"
	grep -v "$CRON_MARK" "$CRON_FILE" > "$tmp" || true
	printf '45 7 * * * /usr/bin/update-geosite-rules update %s\n' "$CRON_MARK" >> "$tmp"
	mv -f "$tmp" "$CRON_FILE"
	/etc/init.d/cron restart >/dev/null 2>&1 || true
	log "installed cron: 07:45 daily"
}

remove_cron() {
	local tmp
	[ -f "$CRON_FILE" ] || return 0
	tmp="$CRON_FILE.tmp.$$"
	grep -v "$CRON_MARK" "$CRON_FILE" > "$tmp" || true
	mv -f "$tmp" "$CRON_FILE"
	/etc/init.d/cron restart >/dev/null 2>&1 || true
	log "removed cron"
}

clear_log() {
	mkdir -p "$(dirname "$LOG_FILE")"
	: > "$LOG_FILE"
	log "log cleared"
}

case "${1:-}" in
	update) update_rules ;;
	status) status_rules ;;
	install-cron) install_cron ;;
	remove-cron) remove_cron ;;
	clear-log) clear_log ;;
	-h|--help|help|"") usage ;;
	*) usage; exit 1 ;;
esac
