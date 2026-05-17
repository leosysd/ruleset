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
CRON_MARK="# 每周自动更新 ruleset 规则集"
OLD_CRON_MARK="# update-geosite-rules"

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
	log "错误：$*"
	exit 1
}

usage() {
	cat <<EOF
用法：/usr/bin/update-geosite-rules <命令>

命令：
  update        下载并原子替换生成好的规则文件
  status        查看规则文件状态
  install-cron  写入每周二 07:45 自动更新定时任务
  remove-cron   删除自动更新定时任务
  clear-log     清理更新日志

环境变量：
  REPO_RAW=https://raw.githubusercontent.com/leosysd/ruleset/main/dist
  SINGBOX_RESTART=0|1  更新成功后是否重启 sing-box
  MOSDNS_RESTART=0|1   更新成功后是否重启 MosDNS
EOF
}

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

ensure_dirs() {
	mkdir -p "$SINGBOX_DIR" "$MOSDNS_DIR" "$WORK_DIR" "$TMP_DIR"
}

fetch_file() {
	local name="$1"
	local tmp="$TMP_DIR/$name.tmp"
	local url="$REPO_RAW/$name"
	rm -f "$tmp"
	log "下载 $url"
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
	[ -s "$tmp" ] || die "下载到的文件为空：$tmp"
	if [ -e "$final" ]; then
		cp -f "$final" "$bak" || die "备份 $final 失败"
	fi
	mv -f "$tmp" "$final" || die "替换 $final 失败"
	log "已安装 $final"
}

update_rules_locked() {
	ensure_dirs

	fetch_file direct-geosite.srs || die "下载 direct-geosite.srs 失败"
	fetch_file proxy-geosite.srs || die "下载 proxy-geosite.srs 失败"
	fetch_file direct-geosite.json || die "下载 direct-geosite.json 失败"
	fetch_file proxy-geosite.json || die "下载 proxy-geosite.json 失败"
	fetch_file direct-geosite.txt || die "下载 direct-geosite.txt 失败"
	fetch_file proxy-geosite.txt || die "下载 proxy-geosite.txt 失败"

	install_file "$TMP_DIR/direct-geosite.srs.tmp" "$SINGBOX_DIR/direct-geosite.srs"
	install_file "$TMP_DIR/proxy-geosite.srs.tmp" "$SINGBOX_DIR/proxy-geosite.srs"
	install_file "$TMP_DIR/direct-geosite.json.tmp" "$SINGBOX_DIR/direct-geosite.json"
	install_file "$TMP_DIR/proxy-geosite.json.tmp" "$SINGBOX_DIR/proxy-geosite.json"
	install_file "$TMP_DIR/direct-geosite.txt.tmp" "$MOSDNS_DIR/direct-geosite.txt"
	install_file "$TMP_DIR/proxy-geosite.txt.tmp" "$MOSDNS_DIR/proxy-geosite.txt"

	if [ "$SINGBOX_RESTART" = "1" ] || [ "$MOSDNS_RESTART" = "1" ]; then
		log "规则文件已替换，等待 10 秒后重启相关服务"
		sleep 10
	fi

	if [ "$SINGBOX_RESTART" = "1" ] && [ -x /etc/init.d/sing-box ]; then
		log "重启 sing-box"
		/etc/init.d/sing-box restart >> "$LOG_FILE" 2>&1 || die "重启 sing-box 失败"
	fi
	if [ "$MOSDNS_RESTART" = "1" ] && [ -x /etc/init.d/mosdns ]; then
		log "重启 MosDNS"
		/etc/init.d/mosdns restart >> "$LOG_FILE" 2>&1 || die "重启 MosDNS 失败"
	fi

	rm -rf "$TMP_DIR"
	log "规则更新完成"
}

update_rules() {
	ensure_dirs
	need_cmd flock
	(
		flock -n 9 || die "已有另一个规则更新任务正在运行"
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
	grep -F -v "$CRON_MARK" "$CRON_FILE" | grep -F -v "$OLD_CRON_MARK" > "$tmp" || true
	printf '45 7 * * 2 SINGBOX_RESTART=1 MOSDNS_RESTART=1 /usr/bin/update-geosite-rules update %s\n' "$CRON_MARK" >> "$tmp"
	mv -f "$tmp" "$CRON_FILE"
	/etc/init.d/cron restart >/dev/null 2>&1 || true
	log "已写入定时任务：每周二 07:45 更新规则集并重启 sing-box 和 MosDNS"
}

remove_cron() {
	local tmp
	[ -f "$CRON_FILE" ] || return 0
	tmp="$CRON_FILE.tmp.$$"
	grep -F -v "$CRON_MARK" "$CRON_FILE" | grep -F -v "$OLD_CRON_MARK" > "$tmp" || true
	mv -f "$tmp" "$CRON_FILE"
	/etc/init.d/cron restart >/dev/null 2>&1 || true
	log "已删除自动更新定时任务"
}

clear_log() {
	mkdir -p "$(dirname "$LOG_FILE")"
	: > "$LOG_FILE"
	log "更新日志已清理"
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
