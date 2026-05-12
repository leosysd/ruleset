#!/bin/sh

set -u

UPDATER_URL="${UPDATER_URL:-https://raw.githubusercontent.com/leosysd/ruleset/main/openwrt/update-geosite-rules.sh}"
UPDATER="/usr/bin/update-geosite-rules"

log() {
	printf '%s\n' "$*"
}

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

need_root() {
	[ "$(id -u)" = "0" ] || die "please run as root"
}

download_updater() {
	rm -f "$UPDATER.tmp"
	if command -v curl >/dev/null 2>&1; then
		curl -fL -o "$UPDATER.tmp" "$UPDATER_URL" || die "failed to download updater with curl"
	elif command -v wget >/dev/null 2>&1; then
		wget -O "$UPDATER.tmp" "$UPDATER_URL" || die "failed to download updater with wget"
	elif command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -O "$UPDATER.tmp" "$UPDATER_URL" || die "failed to download updater with uclient-fetch"
	else
		die "missing downloader: curl, wget, or uclient-fetch"
	fi
	[ -s "$UPDATER.tmp" ] || die "downloaded updater is empty"
	sh -n "$UPDATER.tmp" || die "downloaded updater has shell syntax errors"
	mv -f "$UPDATER.tmp" "$UPDATER" || die "failed to install $UPDATER"
	chmod +x "$UPDATER"
}

main() {
	need_root
	log "Installing update-geosite-rules..."
	download_updater
	log "Updating generated rule files..."
	"$UPDATER" update
	log "Installing daily cron..."
	"$UPDATER" install-cron
	log "Current status:"
	"$UPDATER" status
	log "Done."
}

main "$@"
