#!/bin/sh

set -u

UPDATER_URL="${UPDATER_URL:-https://raw.githubusercontent.com/leosysd/ruleset/main/openwrt/update-geosite-rules.sh}"
UPDATER="/usr/bin/update-geosite-rules"

log() {
	printf '%s\n' "$*"
}

die() {
	printf '错误：%s\n' "$*" >&2
	exit 1
}

need_root() {
	[ "$(id -u)" = "0" ] || die "请使用 root 用户运行"
}

download_updater() {
	rm -f "$UPDATER.tmp"
	if command -v curl >/dev/null 2>&1; then
		curl -fL -o "$UPDATER.tmp" "$UPDATER_URL" || die "使用 curl 下载更新脚本失败"
	elif command -v wget >/dev/null 2>&1; then
		wget -O "$UPDATER.tmp" "$UPDATER_URL" || die "使用 wget 下载更新脚本失败"
	elif command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -O "$UPDATER.tmp" "$UPDATER_URL" || die "使用 uclient-fetch 下载更新脚本失败"
	else
		die "缺少下载工具：curl、wget 或 uclient-fetch"
	fi
	[ -s "$UPDATER.tmp" ] || die "下载到的更新脚本为空"
	sh -n "$UPDATER.tmp" || die "下载到的更新脚本存在 shell 语法错误"
	mv -f "$UPDATER.tmp" "$UPDATER" || die "安装 $UPDATER 失败"
	chmod +x "$UPDATER"
}

main() {
	need_root
	log "正在安装规则更新脚本..."
	download_updater
	log "正在更新规则文件..."
	"$UPDATER" update
	log "正在写入每周自动更新定时任务..."
	"$UPDATER" install-cron
	log "当前规则状态："
	"$UPDATER" status
	log "完成。"
}

main "$@"
