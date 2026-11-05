#!/usr/bin/env bash
#
# traffic-balancer.sh  流量对等脚本
#
# 思路：每小时统计本机某个方向的真实流量 D，按 1/RATIO 换算出需要补齐的下载量 T，
#       再从 DOWNLOAD_URLS 列表中轮换取地址、分 1~MAX_COUNT 段下载（每段下完立即删除），
#       从而在上行流量之外稳定制造出约 T 的下行流量，形成固定的上下行比例。
#
#   上小时 1 GB  ->  T = 341 MB  ->  下载约 341 MB
#   上小时 2 GB  ->  T = 682 MB  ->  下载约 682 MB
#
# 下载源不限定：任何能直链下载的地址都可以（安装包、镜像 ISO、大文件等）。
# 文件大小自动探测并缓存，不需要手动填。
#
# 用法：
#   traffic-balancer.sh run          执行一次（由 cron 每小时调用）
#   traffic-balancer.sh dry-run      只计算并打印计划，不真正下载
#   traffic-balancer.sh status       查看网卡、基线、源大小与最近记录
#   traffic-balancer.sh verify [n]   真实下载 n 次并删除，用于验证链路（不动基线）
#   traffic-balancer.sh reset        清空基线，下次运行重新建立

set -uo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 022

#---------------------------------------------------------- 路径 -------------
CONF_FILE="/etc/traffic-balancer.conf"

STATE_DIR="/var/lib/traffic-balancer"
STATE_FILE="$STATE_DIR/state"
HISTORY_FILE="$STATE_DIR/history.csv"
SIZE_CACHE="$STATE_DIR/sizes.cache"
WORK_DIR="$STATE_DIR/tmp"
LOG_FILE="/var/log/traffic-balancer.log"
LOG_MAX_BYTES=$((2 * 1024 * 1024))

#---------------------------------------------------------- 默认配置 ---------
IFACE=auto                                      # 统计网卡；auto = 默认路由网卡
DIRECTION=tx                                    # tx=上行/出网，rx=下行/入网，total=双向合计
RATIO=3                                         # 目标流量 = 上小时流量 / RATIO
MIN_COUNT=1                                     # 每次至少下载几段
MAX_COUNT=2                                     # 每次最多下载几段
DOWNLOAD_URLS=""                                # 空格分隔的下载直链列表，可写多个轮换
FALLBACK_PKG_SIZE=283125176                     # 探测不到文件大小时的兜底字节数
TRIM_LAST=1                                     # 1=最后一段按剩余量截取，1/3 更精确；0=只下整文件
SKIP_BELOW_MB=60                                # 上小时流量低于该值则本次不下载
MAX_PULL_MB_PER_RUN=1200                        # 单次运行最多下载的 MB
LIMIT_RATE=""                                   # 限速，如 "30m"；留空不限速
CURL_MAX_TIME=1800                              # 单次下载超时（秒）
SIZE_CACHE_TTL_DAYS=7                           # 文件大小缓存有效期（天）

[ -r "$CONF_FILE" ] && . "$CONF_FILE"

# 兼容旧版配置名（wechat-traffic-balancer 时期）
[ -n "${PKG_URL:-}" ] && [ -z "$DOWNLOAD_URLS" ] && DOWNLOAD_URLS="$PKG_URL"
[ -n "${PKG_SIZE:-}" ] && FALLBACK_PKG_SIZE="$PKG_SIZE"

#---------------------------------------------------------- 全局 -------------
STAMP=""
DOWNLOADED_BYTES=0
IFACE_R=""
QUIET=0
RUN_OFFSET=$(date +%H 2>/dev/null || echo 0)    # 每小时换一个起始源，天然轮换

log() {
    local msg="$*"
    printf '%s %s\n' "$(date '+%F %T')" "$msg" >>"$LOG_FILE" 2>/dev/null
    [ "$QUIET" = "1" ] || printf '%s %s\n' "$(date '+%F %T')" "$msg"
}

mb() { awk -v b="${1:-0}" 'BEGIN{printf "%.1f", b/1048576}'; }

err() { log "错误：$*"; return 1; }

rotate_log() {
    [ -f "$LOG_FILE" ] || return 0
    local size
    size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt "$LOG_MAX_BYTES" ]; then
        tail -n 2000 "$LOG_FILE" >"$LOG_FILE.tmp" 2>/dev/null && mv -f "$LOG_FILE.tmp" "$LOG_FILE"
    fi
}

#-------------------------------------------------------- 流量统计 -----------
detect_iface() {
    local ifc
    ifc=$(ip -o route show default 2>/dev/null | awk '{for(n=1;n<=NF;n++) if($n=="dev"){print $(n+1); exit}}')
    if [ -z "$ifc" ]; then
        ifc=$(awk -F: 'NR>2 {n=$1; gsub(/ /,"",n); if(n!="lo" && $0 ~ /[1-9]/){print n; exit}}' /proc/net/dev)
    fi
    printf '%s' "$ifc"
}

# 读取指定网卡的 RX/TX 累计字节，输出 "rx tx"
read_counters() {
    awk -v want="$1" 'NR>2 { n=$1; sub(/:$/,"",n); if (n==want) { print $2, $10; exit } }' /proc/net/dev
}

pick_delta() { # $1=rx增量 $2=tx增量
    case "$DIRECTION" in
        rx)    printf '%s' "$1" ;;
        total) printf '%s' $(( $1 + $2 )) ;;
        *)     printf '%s' "$2" ;;
    esac
}

save_state() { # now rx tx
    local tmp="$STATE_FILE.tmp"
    printf '%s %s %s %s\n' "$1" "$2" "$3" "$IFACE_R" >"$tmp" && mv -f "$tmp" "$STATE_FILE"
}

record_history() { # note prev_mb target_mb segments down_mb
    [ -s "$HISTORY_FILE" ] || printf '%s\n' '时间,网卡,方向,比例,上小时MB,目标MB,段数,实际MB,说明' >>"$HISTORY_FILE" 2>/dev/null
    printf '%s,%s,%s,%s,%.1f,%.1f,%s,%.1f,%s\n' \
        "$(date '+%F %T')" "$IFACE_R" "$DIRECTION" "$RATIO" \
        "$2" "$3" "$4" "$5" "$1" >>"$HISTORY_FILE" 2>/dev/null
}

#-------------------------------------------------------- 下载源 -------------
pick_url() { # $1=第几段；输出地址
    local n="$1" arr=() cnt off
    read -r -a arr <<<"$(printf '%s' "$DOWNLOAD_URLS" | tr '\n' ' ')"
    cnt=${#arr[@]}
    [ "$cnt" -gt 0 ] || return 1
    off=$(( RUN_OFFSET % cnt ))
    printf '%s' "${arr[$((( n - 1 + off ) % cnt ))]}"
}

# 探测文件字节数，结果缓存；探测失败用兜底值
size_of_url() {
    local url="$1" now size="" c_size="" c_epoch=""
    now=$(date +%s)

    if [ -s "$SIZE_CACHE" ]; then
        local cached
        cached=$(awk -F'\t' -v u="$url" '$1==u {s=$2; e=$3} END{print s"\t"e}' "$SIZE_CACHE" 2>/dev/null)
        c_size=$(printf '%s' "$cached" | cut -f1)
        c_epoch=$(printf '%s' "$cached" | cut -f2)
        if [ -n "$c_size" ] && [ "$c_size" -gt 0 ] 2>/dev/null && [ -n "$c_epoch" ] \
           && [ $(( now - c_epoch )) -lt $(( SIZE_CACHE_TTL_DAYS * 86400 )) ]; then
            printf '%s' "$c_size"
            return 0
        fi
    fi

    size=$(curl -sIL --max-time 20 "$url" 2>/dev/null | awk '
        { k = tolower($1); if (k == "content-length:") { v = $2 } }
        END { if (v != "") { gsub(/\r/, "", v) }; print v }')
    case "${size:-}" in ''|*[!0-9]*) size=0 ;; esac

    if [ "$size" -gt 0 ]; then
        { awk -F'\t' -v u="$url" '$1!=u' "$SIZE_CACHE" 2>/dev/null; \
          printf '%s\t%s\t%s\n' "$url" "$size" "$now"; } >"$SIZE_CACHE.tmp" 2>/dev/null \
            && mv -f "$SIZE_CACHE.tmp" "$SIZE_CACHE"
        printf '%s' "$size"
        return 0
    fi

    printf '%s' "$FALLBACK_PKG_SIZE"
}

need_space_mb() { # $1=预计字节数
    awk -v b="$1" 'BEGIN{printf "%d", (b/1048576)*1.2 + 16}'
}

download_once() { # $1=序号 $2=url $3=字节上限(0=整文件)；成功返回0，DOWNLOADED_BYTES=实际字节
    local n="$1" url="$2" limit="${3:-0}"
    local out rc res bytes code secs
    out="$WORK_DIR/dl.${STAMP}.${n}.part"
    local -a args=(-sS -L --retry 2 --retry-delay 3 --max-time "$CURL_MAX_TIME" -o "$out")
    [ -n "$LIMIT_RATE" ] && args+=(--limit-rate "$LIMIT_RATE")
    [ "$limit" -gt 0 ] && args+=(-r "0-$(( limit - 1 ))")

    res=$(curl "${args[@]}" -w '%{size_download} %{http_code} %{time_total}' "$url" 2>>"$LOG_FILE")
    rc=$?
    bytes=$(printf '%s' "$res" | awk '{print $1+0}')
    code=$(printf '%s' "$res" | awk '{print $2+0}')
    secs=$(printf '%s' "$res" | awk '{print $3+0}')
    rm -f "$out"
    DOWNLOADED_BYTES="${bytes:-0}"

    case "$code" in
        200|206) ;;
        *)
            log "第 $n 段失败：curl_rc=$rc http=$code 已下载=$(mb "${bytes:-0}")MB 来源 $url"
            return 1
            ;;
    esac

    log "第 $n 段完成：$(mb "$bytes")MB，耗时 ${secs}s，来源 $url（文件已删除）"
    return 0
}

#------------------------------------------------------------ run ------------
cmd_run() {
    local dry="$1"
    mkdir -p "$STATE_DIR" "$WORK_DIR"
    chmod 700 "$STATE_DIR" 2>/dev/null
    rotate_log

    if [ -z "${DOWNLOAD_URLS// /}" ]; then
        err "未配置下载地址，请在 $CONF_FILE 里设置 DOWNLOAD_URLS"
        return 1
    fi

    exec 9>"$STATE_DIR/lock"
    if ! flock -n 9; then
        log "上一次任务仍在运行，本次跳过"
        return 0
    fi

    IFACE_R="$IFACE"
    [ "$IFACE_R" = "auto" ] && IFACE_R=$(detect_iface)
    [ -n "$IFACE_R" ] || { err "无法确定统计网卡，请检查网络或配置 IFACE"; return 1; }

    local now rx tx
    now=$(date +%s)
    read -r rx tx <<<"$(read_counters "$IFACE_R")"
    if [ -z "${rx:-}" ] || [ -z "${tx:-}" ]; then
        err "读取网卡 $IFACE_R 计数器失败"
        return 1
    fi

    if [ ! -s "$STATE_FILE" ]; then
        save_state "$now" "$rx" "$tx"
        log "首次运行：已建立基线（网卡 $IFACE_R，rx=$rx tx=$tx），本次不下载"
        return 0
    fi

    local last_epoch last_rx last_tx last_iface
    read -r last_epoch last_rx last_tx last_iface <"$STATE_FILE"

    if [ "$last_iface" != "$IFACE_R" ]; then
        log "网卡从 $last_iface 变为 $IFACE_R，重置基线，本次不下载"
        save_state "$now" "$rx" "$tx"
        return 0
    fi

    local d_rx=$(( rx - last_rx )) d_tx=$(( tx - last_tx ))
    if [ "$d_rx" -lt 0 ] || [ "$d_tx" -lt 0 ]; then
        log "检测到计数器重置（可能重启）：rx $last_rx→$rx tx $last_tx→$tx，重置基线，本次不下载"
        save_state "$now" "$rx" "$tx"
        return 0
    fi

    [ "${RATIO:-0}" -lt 1 ] 2>/dev/null && RATIO=1
    [ "${MIN_COUNT:-0}" -lt 0 ] 2>/dev/null && MIN_COUNT=0
    [ "${MAX_COUNT:-0}" -lt 1 ] 2>/dev/null && MAX_COUNT=1
    [ "$MAX_COUNT" -lt "$MIN_COUNT" ] && MAX_COUNT="$MIN_COUNT"
    [ "${MAX_PULL_MB_PER_RUN:-0}" -lt 1 ] 2>/dev/null && MAX_PULL_MB_PER_RUN=1

    local delta hours target prev_mb target_mb
    delta=$(pick_delta "$d_rx" "$d_tx")
    hours=$(awk -v a="$last_epoch" -v b="$now" 'BEGIN{printf "%.2f", (b-a)/3600}')
    target=$(( delta / RATIO ))
    prev_mb=$(mb "$delta")
    target_mb=$(mb "$target")

    log "统计周期 ${hours}h：$IFACE_R $DIRECTION 共 ${prev_mb}MB，目标下载量 ${target_mb}MB（1/$RATIO）"

    if awk -v p="$prev_mb" -v s="$SKIP_BELOW_MB" 'BEGIN{exit !(p < s)}'; then
        log "上小时流量 ${prev_mb}MB 低于阈值 ${SKIP_BELOW_MB}MB，本次不下载"
        if [ "$dry" = "0" ]; then
            read -r rx tx <<<"$(read_counters "$IFACE_R")"
            save_state "$(date +%s)" "$rx" "$tx"
        fi
        record_history "skip_below_threshold" "$prev_mb" "$target_mb" 0 0
        return 0
    fi

    STAMP=$(date '+%Y%m%d%H%M%S')
    local cap_bytes=$(( MAX_PULL_MB_PER_RUN * 1048576 ))
    local i=0 ok=0 total=0 url size limit remaining plan need avail

    while [ "$i" -lt "$MAX_COUNT" ]; do
        i=$(( i + 1 ))
        remaining=$(( target - total ))

        if [ "$ok" -ge "$MIN_COUNT" ] && [ "$remaining" -le 0 ]; then
            log "已满足目标（累计 $(mb "$total")MB / 目标 $(mb "$target")MB），不再追加"
            break
        fi
        if [ "$total" -ge "$cap_bytes" ]; then
            log "已达单次运行上限 ${MAX_PULL_MB_PER_RUN}MB，停止"
            break
        fi

        if ! url=$(pick_url "$i"); then
            err "DOWNLOAD_URLS 解析失败"
            break
        fi
        size=$(size_of_url "$url")
        if [ "${size:-0}" -le 0 ]; then
            log "第 $i 段跳过：无法确定 $url 的文件大小"
            continue
        fi

        local room
        room=$(( cap_bytes - total ))
        if [ "$room" -le 0 ]; then
            log "已达单次运行上限 ${MAX_PULL_MB_PER_RUN}MB，停止"
            break
        fi

        if [ "$TRIM_LAST" = "1" ]; then
            limit="$remaining"
            [ "$limit" -le 0 ] && limit="$size"      # 已达标但要凑最少段数时下整段
            [ "$limit" -gt "$size" ] && limit="$size"  # 不超过源文件大小
            [ "$limit" -gt "$room" ] && limit="$room"  # 不超过单次运行上限
            [ "$limit" -ge "$size" ] && limit=0        # 正好整文件则直接下完整
        else
            limit=0
            if [ "$size" -gt "$room" ]; then
                log "第 $i 段跳过：整文件 $(mb "$size")MB 超过单次运行剩余额度 $(mb "$room")MB"
                continue
            fi
        fi
        plan="$size"
        [ "$limit" -gt 0 ] && plan="$limit"

        if [ "$dry" = "1" ]; then
            if [ "$limit" -gt 0 ]; then
                log "dry-run 第 $i 段：计划截取 $(mb "$limit")MB（整文件 $(mb "$size")MB） 来源 $url"
            else
                log "dry-run 第 $i 段：计划下载整文件 $(mb "$size")MB 来源 $url"
            fi
            total=$(( total + plan ))
            ok=$(( ok + 1 ))
            continue
        fi

        need=$(need_space_mb "$plan")
        avail=$(df -Pm / | awk 'NR==2 {print $4}')
        if [ "${avail:-0}" -lt "$need" ]; then
            log "磁盘可用 ${avail}MB < 需要 ${need}MB，停止下载"
            record_history "no_disk_space" "$prev_mb" "$target_mb" "$ok" "$(mb "$total")"
            break
        fi

        if download_once "$i" "$url" "$limit"; then
            ok=$(( ok + 1 ))
            total=$(( total + DOWNLOADED_BYTES ))
        fi
    done

    if [ "$dry" = "1" ]; then
        log "dry-run 结束：预计下载 $(mb "$total")MB / 目标 $(mb "$target")MB，共 $ok 段；未下载，基线不变"
        record_history "dry_run" "$prev_mb" "$target_mb" "$ok" "$(mb "$total")"
        return 0
    fi

    log "本次结束：成功 $ok 段，累计下载 $(mb "$total")MB，临时文件已清理"

    # 重新取基线，避免本次下载量被算进下一小时的“自然流量”
    read -r rx tx <<<"$(read_counters "$IFACE_R")"
    save_state "$(date +%s)" "$rx" "$tx"
    record_history "done" "$prev_mb" "$target_mb" "$ok" "$(mb "$total")"

    [ "$ok" -gt 0 ] && return 0
    return 1
}

#---------------------------------------------------------- status -----------
cmd_status() {
    IFACE_R="$IFACE"
    [ "$IFACE_R" = "auto" ] && IFACE_R=$(detect_iface)
    echo "配置文件 : $CONF_FILE"
    echo "统计网卡 : $IFACE_R（DIRECTION=$DIRECTION，RATIO=1/$RATIO，段数 $MIN_COUNT~$MAX_COUNT，TRIM_LAST=$TRIM_LAST）"

    local u size
    echo "下载源   :"
    for u in $DOWNLOAD_URLS; do
        size=$(size_of_url "$u")
        echo "  - $(mb "$size")MB  $u"
    done

    local rx tx
    read -r rx tx <<<"$(read_counters "$IFACE_R")"
    echo "当前累计 : rx=$(mb "$rx")MB tx=$(mb "$tx")MB"
    if [ -s "$STATE_FILE" ]; then
        local last_epoch last_rx last_tx last_iface now d_rx d_tx delta t_cnt
        read -r last_epoch last_rx last_tx last_iface <"$STATE_FILE"
        now=$(date +%s)
        d_rx=$(( rx - last_rx )) d_tx=$(( tx - last_tx ))
        delta=$(pick_delta "$d_rx" "$d_tx")
        echo "基线时间 : $(date -d "@$last_epoch" '+%F %T')（网卡 $last_iface）"
        echo "基线累计 : rx=$last_rx tx=$last_tx"
        echo "基线以来 : rx=$(mb "$d_rx")MB tx=$(mb "$d_tx")MB，$DIRECTION 口径 $(mb "$delta")MB"
        echo "若现在执行：目标 $(mb $(( delta / RATIO )))MB"
    else
        echo "基线 : 尚未建立（下次 cron 运行时会自动建立）"
    fi
    echo "----- 最近 10 条记录（时间,网卡,方向,比例,上小时MB,目标MB,段数,实际MB,说明）-----"
    tail -n 10 "$HISTORY_FILE" 2>/dev/null || echo "(暂无)"
    echo "----- 日志尾部 -----"
    tail -n 4 "$LOG_FILE" 2>/dev/null || echo "(暂无)"
}

#---------------------------------------------------------- verify -----------
cmd_verify() { # $1=次数 $2=每段截取 MB（0=整文件）
    local n="${1:-1}" seg_mb="${2:-50}" limit
    case "$n" in ''|*[!0-9]*) n=1 ;; esac
    [ "$n" -lt 1 ] && n=1
    case "$seg_mb" in ''|*[!0-9]*) seg_mb=50 ;; esac
    limit=$(( seg_mb * 1048576 ))
    mkdir -p "$STATE_DIR" "$WORK_DIR"
    exec 9>"$STATE_DIR/lock"
    flock -n 9 || { echo "已有任务在运行，稍后再试"; return 1; }
    STAMP=$(date '+%Y%m%d%H%M%S')
    local total=0 i url
    if [ "$limit" -gt 0 ]; then
        log "verify：开始下载 $n 段，每段截取 ${seg_mb}MB 后删除"
    else
        log "verify：开始下载 $n 次完整文件并删除"
    fi
    for ((i = 1; i <= n; i++)); do
        url=$(pick_url "$i") || { log "verify：未配置 DOWNLOAD_URLS"; return 1; }
        download_once "$i" "$url" "$limit" && total=$((total + DOWNLOADED_BYTES))
    done
    log "verify：完成，累计 $(mb "$total")MB，临时目录 $WORK_DIR 有 $(ls -A "$WORK_DIR" 2>/dev/null | wc -l) 个文件"
    return 0
}

#----------------------------------------------------------- main ------------
case "${1:-run}" in
    run)     QUIET=1 cmd_run 0 ;;
    dry-run) cmd_run 1 ;;
    status)  cmd_status ;;
    verify)  shift; cmd_verify "${1:-1}" "${2:-50}" ;;
    reset)   rm -f "$STATE_FILE"; log "基线已清空，下次运行重新建立" ;;
    *)       echo "用法: $0 {run|dry-run|status|verify [n] [mb]|reset}"; exit 2 ;;
esac
