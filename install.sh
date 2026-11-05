#!/usr/bin/env bash
#
# install.sh  流量对等脚本一键安装
#
# 本地仓库模式（在 clone 下来的目录里）：
#   bash install.sh
#
# 远程一键模式：
#   curl -fsSL https://raw.githubusercontent.com/2253845067/traffic-balancer/main/install.sh | bash
#
# 选项：
#   --force        用仓库里的模板覆盖 /etc/traffic-balancer.conf（默认保留已有配置）
#   --no-cron      只安装文件，不写定时任务
#   --min N        定时任务的分钟数，默认 17（即每小时第 17 分钟）
#   --verify       安装后真实下载 30MB 验证一次链路（会产生少量下行流量）
#   --uninstall    卸载（移除定时任务与脚本、配置）
#   --purge        与 --uninstall 一起用，同时删除状态目录与日志
#   -h, --help     显示帮助
#
# 可用环境变量覆盖：REPO_SLUG、BRANCH、RAW_BASE（决定远程模式下从哪下载）、CRON_MINUTE

set -uo pipefail

REPO_SLUG="${REPO_SLUG:-2253845067/traffic-balancer}"
RAW_BASE="${RAW_BASE:-}"
BRANCH="${BRANCH:-}"
BIN_PATH="/usr/local/bin/traffic-balancer.sh"
CONF_PATH="/etc/traffic-balancer.conf"
STATE_DIR="/var/lib/traffic-balancer"
LOG_PATH="/var/log/traffic-balancer.log"
CRON_MINUTE="${CRON_MINUTE:-17}"

FORCE=0
NO_CRON=0
DO_VERIFY=0
PURGE=0
ACTION="install"
SRC_DIR=""
STAGE=""

if [ -t 1 ]; then
    c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_off=$'\033[0m'
else
    c_red=""; c_grn=""; c_yel=""; c_off=""
fi

info() { printf '%s[信息]%s %s\n' "$c_grn" "$c_off" "$*"; }
warn() { printf '%s[注意]%s %s\n' "$c_yel" "$c_off" "$*"; }
die()  { printf '%s[错误]%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() { sed -n '3,22p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
    case "$1" in
        --force)     FORCE=1 ;;
        --no-cron)   NO_CRON=1 ;;
        --verify)    DO_VERIFY=1 ;;
        --uninstall) ACTION="uninstall" ;;
        --purge)     PURGE=1 ;;
        --min)       shift; [ -n "${1:-}" ] || die "--min 需要一个数字"; CRON_MINUTE="$1" ;;
        -h|--help)   usage ;;
        *)           die "未知参数：$1（用 --help 查看用法）" ;;
    esac
    shift
done

case "$CRON_MINUTE" in ''|*[!0-9]*) die "--min 必须是 0-59 的数字" ;; esac
[ "$CRON_MINUTE" -ge 0 ] && [ "$CRON_MINUTE" -le 59 ] || die "--min 必须是 0-59 的数字"

[ "$(id -u)" -eq 0 ] || die "请用 root 运行（sudo bash install.sh）"

#---------------------------------------------------------- 依赖 ------------
install_pkgs() {
    [ $# -gt 0 ] || return 0
    if have apt-get; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null 2>&1
    elif have dnf; then
        dnf install -y -q "$@" >/dev/null 2>&1
    elif have yum; then
        yum install -y -q "$@" >/dev/null 2>&1
    elif have apk; then
        apk add --no-cache "$@" >/dev/null 2>&1
    else
        return 1
    fi
}

ensure_deps() {
    local pkgs=""
    have curl || pkgs="$pkgs curl"
    have flock || pkgs="$pkgs util-linux"
    if ! have crontab && [ "$NO_CRON" -eq 0 ]; then
        if have apt-get; then pkgs="$pkgs cron"; else pkgs="$pkgs cronie"; fi
    fi
    if [ -n "$pkgs" ]; then
        info "安装依赖：$pkgs"
        install_pkgs $pkgs || die "依赖安装失败，请手动安装：$pkgs"
    fi
    have curl || die "缺少 curl，无法继续"
}

#---------------------------------------------------------- 取文件 ----------
resolve_source() {
    local self="${BASH_SOURCE[0]:-}"
    if [ -n "$self" ] && [ -f "$self" ]; then
        SRC_DIR=$(cd "$(dirname "$self")" >/dev/null 2>&1 && pwd) || SRC_DIR=""
    fi

    if [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/traffic-balancer.sh" ] && [ -f "$SRC_DIR/traffic-balancer.conf" ]; then
        info "使用本地文件：$SRC_DIR"
        bash -n "$SRC_DIR/traffic-balancer.sh" || die "本地脚本语法校验失败"
        return 0
    fi

    local bases="$RAW_BASE"
    if [ -z "$bases" ]; then
        if [ -n "$BRANCH" ]; then
            bases="https://raw.githubusercontent.com/$REPO_SLUG/$BRANCH"
        else
            bases="https://raw.githubusercontent.com/$REPO_SLUG/main https://raw.githubusercontent.com/$REPO_SLUG/master"
        fi
    fi

    info "从 GitHub 下载安装文件…"
    STAGE=$(mktemp -d) || die "无法创建临时目录"
    trap 'rm -rf "$STAGE"' EXIT

    local f url ok
    for f in traffic-balancer.sh traffic-balancer.conf; do
        ok=0
        for url in $bases; do
            if curl -fsSL --retry 2 --connect-timeout 10 --max-time 120 "$url/$f" -o "$STAGE/$f" 2>/dev/null; then
                ok=1
                break
            fi
        done
        [ "$ok" -eq 1 ] || die "下载 $f 失败。请确认仓库已推送且文件名正确，或改用本地模式：bash install.sh（下载源：$bases）"
    done
    bash -n "$STAGE/traffic-balancer.sh" || die "下载的脚本语法校验失败"
    SRC_DIR="$STAGE"
}

#---------------------------------------------------------- 安装 ------------
install_files() {
    install -m 755 "$SRC_DIR/traffic-balancer.sh" "$BIN_PATH" || die "写入 $BIN_PATH 失败"
    info "已安装脚本：$BIN_PATH"

    if [ -f "$CONF_PATH" ] && [ "$FORCE" -eq 0 ]; then
        warn "已存在配置 $CONF_PATH，保留现有设置（想用模板覆盖请加 --force）"
    else
        if [ -f "$CONF_PATH" ]; then
            local bak="$CONF_PATH.bak.$(date +%Y%m%d%H%M%S)"
            cp -f "$CONF_PATH" "$bak" && warn "旧配置已备份到 $bak"
        fi
        install -m 644 "$SRC_DIR/traffic-balancer.conf" "$CONF_PATH" || die "写入 $CONF_PATH 失败"
        info "已写入配置：$CONF_PATH"
    fi

    mkdir -p "$STATE_DIR/tmp" || die "创建 $STATE_DIR 失败"
    chmod 700 "$STATE_DIR"
}

setup_cron() {
    if [ "$NO_CRON" -eq 1 ]; then
        warn "已跳过定时任务（--no-cron），请自行安排每小时调用：$BIN_PATH run"
        return 0
    fi
    if ! have crontab; then
        warn "未找到 crontab，跳过定时任务；请用 cron/systemd timer 每小时执行：$BIN_PATH run"
        return 0
    fi

    local tmp entry
    tmp=$(mktemp) || die "无法创建临时文件"
    crontab -l 2>/dev/null | grep -v 'traffic-balancer' >"$tmp"
    entry="$CRON_MINUTE * * * * $BIN_PATH run >/dev/null 2>&1  # 流量对等(每小时)"
    printf '%s\n' "$entry" >>"$tmp"
    crontab "$tmp" || { rm -f "$tmp"; die "写入 crontab 失败"; }
    rm -f "$tmp"
    info "已写入定时任务：每小时第 $CRON_MINUTE 分钟执行"

    local svc
    for svc in cron crond; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
            systemctl is-active --quiet "$svc" || systemctl enable --now "$svc" >/dev/null 2>&1
            systemctl is-active --quiet "$svc" && info "cron 服务运行中：$svc" || warn "cron 服务未运行（$svc），定时任务不会触发"
            return 0
        fi
    done
    if have pgrep && ! pgrep -x 'cron|crond' >/dev/null 2>&1; then
        warn "未检测到运行中的 cron 进程，请确认定时服务已启动"
    fi
}

#---------------------------------------------------------- 卸载 ------------
do_uninstall() {
    if have crontab && crontab -l 2>/dev/null | grep -q 'traffic-balancer'; then
        local tmp
        tmp=$(mktemp) || die "无法创建临时文件"
        crontab -l 2>/dev/null | grep -v 'traffic-balancer' >"$tmp"
        crontab "$tmp" && rm -f "$tmp"
        info "已移除定时任务"
    else
        warn "没有找到相关定时任务"
    fi

    [ -f "$BIN_PATH" ] && { rm -f "$BIN_PATH"; info "已删除 $BIN_PATH"; }
    [ -f "$CONF_PATH" ] && { rm -f "$CONF_PATH"; info "已删除 $CONF_PATH"; }

    if [ "$PURGE" -eq 1 ]; then
        rm -rf "$STATE_DIR" "$LOG_PATH"
        info "已删除状态目录与日志"
    else
        warn "保留了 $STATE_DIR 与 $LOG_PATH（加 --purge 一并删除）"
    fi
    info "卸载完成"
}

#---------------------------------------------------------- 主流程 ----------
if [ "$ACTION" = "uninstall" ]; then
    do_uninstall
    exit 0
fi

info "流量对等脚本安装程序"
ensure_deps
resolve_source
install_files
setup_cron

info "首次运行检查（无基线时会自动建立基线，不会下载）"
"$BIN_PATH" dry-run || warn "dry-run 返回非 0，请查看 $LOG_PATH"

if [ "$DO_VERIFY" -eq 1 ]; then
    info "验证下载链路（30MB）…"
    "$BIN_PATH" verify 1 30 || warn "验证失败，请查看 $LOG_PATH"
fi

echo
info "安装完成。常用命令："
cat <<EOF
  $BIN_PATH status           # 查看基线、下载源大小、最近记录
  $BIN_PATH dry-run          # 只计算计划，不下载
  $BIN_PATH run              # 立即执行一次
  $BIN_PATH verify 1 30      # 真实下载 30MB 验证链路
  $BIN_PATH reset            # 重置基线
  配置文件：$CONF_PATH
  运行日志：$LOG_PATH
EOF
