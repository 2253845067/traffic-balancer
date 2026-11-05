# 流量对等脚本（traffic-balancer）

每小时统计本机某个方向的真实流量，按 `1/RATIO` 换算出需要补齐的下载量，再从可配置的下载源列表里拉取数据、**下完立即删除**，从而在计费方向上稳定制造出固定比例的反向流量。

仓库地址：<https://github.com/2253845067/traffic-balancer>

- 一条命令安装，装完即是可用状态（自动写 cron、建基线）
- 不绑定具体文件：任何能直链下载的地址都行（安装包、镜像 ISO、大文件），可在配置里写多个源按小时轮换
- 纯 Bash，只依赖 `curl` + `/proc/net/dev`，不需要 `vnstat`、`python3`、`jq`
- 文件大小自动探测（HTTP HEAD + 本地缓存），无需手工填写
- 支持按字节截取（`Range`），在支持分段下载的源上可以**精确**凑到目标量，而不是整包粒度
- 磁盘占用极小：文件边下边删，临时目录常态为空
- 防自激：本次下载的流量不会计入下一小时的目标
- 带并发锁、磁盘空间检查、单次流量上限、日志自动截断

## 一、一键安装

**方式 A：远程一键（国内推荐，gh-proxy 加速）**

```bash
curl -fsSL https://v4.gh-proxy.org/https://raw.githubusercontent.com/2253845067/traffic-balancer/main/install.sh | bash
```

**方式 B：远程一键（GitHub 直连）**

```bash
curl -fsSL https://raw.githubusercontent.com/2253845067/traffic-balancer/main/install.sh | bash
```

**方式 C：克隆后本地安装**

```bash
# 走加速
git clone https://v4.gh-proxy.org/https://github.com/2253845067/traffic-balancer.git
# 或直连
git clone https://github.com/2253845067/traffic-balancer.git

cd traffic-balancer
sudo bash install.sh
```

> 方式 A / B 拿到的 `install.sh` 在拉取主脚本时，默认也是**先走 `https://v4.gh-proxy.org` 加速、失败自动回退 GitHub 直连**，所以国内机器开箱可用。

安装脚本会自动完成：

1. 检查并安装缺失的依赖（`curl`、`util-linux`/`flock`、`cron`）
2. 把 `traffic-balancer.sh` 装到 `/usr/local/bin/`、配置装到 `/etc/traffic-balancer.conf`
3. 创建状态目录 `/var/lib/traffic-balancer/`
4. 写入 crontab（默认每小时第 17 分钟），并确保 cron 服务在运行
5. 跑一次 `dry-run` 建立基线（不会下载）
6. 打印常用命令

安装脚本参数：

| 参数 | 说明 |
|---|---|
| `--force` | 用仓库里的模板覆盖已有配置（默认保留你改过的配置） |
| `--no-cron` | 只装文件，不写定时任务 |
| `--min N` | 指定定时的分钟数，默认 `17` |
| `--verify` | 安装后真实下载 30 MB 验证链路 |
| `--uninstall` | 卸载（移除定时任务、脚本、配置） |
| `--purge` | 与 `--uninstall` 配合，同时删除状态目录与日志 |

示例：

```bash
# 安装并顺带验证下载链路
curl -fsSL https://v4.gh-proxy.org/https://raw.githubusercontent.com/2253845067/traffic-balancer/main/install.sh | bash -s -- --verify

# 换到别的分钟数
curl -fsSL https://v4.gh-proxy.org/https://raw.githubusercontent.com/2253845067/traffic-balancer/main/install.sh | bash -s -- --min 25

# 卸载但保留历史记录
curl -fsSL https://v4.gh-proxy.org/https://raw.githubusercontent.com/2253845067/traffic-balancer/main/install.sh | bash -s -- --uninstall
```

安装脚本支持的环境变量（一般不用改）：

| 变量 | 默认 | 说明 |
|---|---|---|
| `GH_PROXY` | `https://v4.gh-proxy.org` | GitHub 加速前缀；`GH_PROXY=` 置空则只走直连 |
| `REPO_SLUG` | `2253845067/traffic-balancer` | 换了 fork 或仓库名时覆盖 |
| `BRANCH` | 空（依次试 `main`、`master`） | 指定分支 |
| `RAW_BASE` | 空 | 直接指定下载前缀，优先级最高（可指向自建镜像） |
| `CRON_MINUTE` | `17` | 等价于 `--min` |

例如换用自己的加速站或镜像：

```bash
GH_PROXY=https://ghproxy.net bash install.sh
RAW_BASE=https://cdn.example.com/traffic-balancer bash install.sh
```

## 二、工作原理

```
每小时的 cron
   │
   ├─ 读 /proc/net/dev 拿到网卡累计 RX/TX（如 ens5）
   ├─ 与上次保存的基线相减 => 上一个小时的真实流量 D
   ├─ 目标下载量 T = D / RATIO             （RATIO=3 即 1/3）
   ├─ 从 DOWNLOAD_URLS 里按小时轮换取地址，分 1~MAX_COUNT 段下载
   │    └─ TRIM_LAST=1 时最后一段按“还差多少字节”用 Range 截取
   ├─ 每段下完立即 rm，磁盘不堆积
   └─ 重新读取计数器写回基线（防止本次下载量放大下一小时的目标）
```

示例（RATIO=3）：

| 上小时流量 | 目标量 | 实际下载 | 实际比例 |
|---|---|---|---|
| 1 GiB | 341 MB | 341 MB | 1/3 |
| 2 GiB | 683 MB | 683 MB | 1/3 |
| 5 GiB | 1707 MB | 1200 MB（受单次上限约束） | 约 1/4.3 |
| 100 MB | 33 MB | 33 MB | 1/3 |

> `TRIM_LAST=1`（默认）会按目标量截取，比例可以做到接近精确；设 `TRIM_LAST=0` 则只下完整文件，粒度变成"整个文件大小"。

统计方向默认 `DIRECTION=tx`（出网/上行）：阿里云轻量等产品按出网流量计费，用 tx 作为基数可以避免"自己制造的下行流量反过来抬升下一小时目标"的正反馈。若你的套餐按入网计费，把 `DIRECTION` 改成 `rx`。

## 三、文件说明

| 文件 | 部署位置 | 说明 |
|---|---|---|
| `traffic-balancer.sh` | `/usr/local/bin/traffic-balancer.sh` | 主脚本（755） |
| `traffic-balancer.conf` | `/etc/traffic-balancer.conf` | 配置，每次运行重新读取，改完即生效 |
| `install.sh` | 不常驻，装完即可删 | 一键安装/卸载 |
| 基线状态 | `/var/lib/traffic-balancer/state` | `时间戳 RX累加 TX累加 网卡名` |
| 运行记录 | `/var/lib/traffic-balancer/history.csv` | 每小时一行，便于核对 |
| 源大小缓存 | `/var/lib/traffic-balancer/sizes.cache` | `url \t 字节数 \t 探测时间` |
| 临时目录 | `/var/lib/traffic-balancer/tmp/` | 仅下载中存在内容 |
| 日志 | `/var/log/traffic-balancer.log` | 超 2 MB 自动截断保留最近 2000 行 |

`history.csv` 字段：`时间,网卡,方向,比例,上小时MB,目标MB,段数,实际MB,说明`
说明列取值：`done`、`dry_run`、`skip_below_threshold`、`no_disk_space`。

## 四、手动安装（不想用脚本时）

```bash
install -m 755 traffic-balancer.sh   /usr/local/bin/traffic-balancer.sh
install -m 644 traffic-balancer.conf /etc/traffic-balancer.conf
( crontab -l 2>/dev/null | grep -v traffic-balancer.sh
  echo '17 * * * * /usr/local/bin/traffic-balancer.sh run >/dev/null 2>&1  # 流量对等' ) | crontab -
/usr/local/bin/traffic-balancer.sh dry-run        # 建基线，不下载
/usr/local/bin/traffic-balancer.sh verify 1 30    # 可选：验证 30MB 下载链路
```

卸载：

```bash
crontab -l | grep -v traffic-balancer.sh | crontab -
rm -f /usr/local/bin/traffic-balancer.sh /etc/traffic-balancer.conf
rm -rf /var/lib/traffic-balancer /var/log/traffic-balancer.log
```

## 五、配置项

编辑 `/etc/traffic-balancer.conf`，保存即生效。

| 变量 | 默认 | 说明 |
|---|---|---|
| `IFACE` | `auto` | 统计网卡，`auto` = 跟随默认路由网卡 |
| `DIRECTION` | `tx` | `tx` 出网、`rx` 入网、`total` 双向合计 |
| `RATIO` | `3` | 目标下载量 = 上小时流量 ÷ RATIO |
| `MIN_COUNT` / `MAX_COUNT` | `1` / `2` | 每次下载的段数区间 |
| `DOWNLOAD_URLS` | 微信包 + 清华/南大 ISO | 空格或换行分隔的直链列表，按小时轮换取用 |
| `FALLBACK_PKG_SIZE` | `283125176` | 探测不到 Content-Length 时的兜底字节数 |
| `TRIM_LAST` | `1` | `1` 按剩余量截取（精确），`0` 只下整文件 |
| `SKIP_BELOW_MB` | `60` | 上小时流量低于该值不下载；设 `0` 关闭 |
| `MAX_PULL_MB_PER_RUN` | `1200` | 单次运行最多下载的 MB |
| `LIMIT_RATE` | 空 | 限速，`curl --limit-rate` 语法，如 `30m` |
| `CURL_MAX_TIME` | `1800` | 单次下载超时（秒） |
| `SIZE_CACHE_TTL_DAYS` | `7` | 源大小缓存有效期（天） |

选源建议：优先挑 **支持 `Accept-Ranges: bytes`** 且稳定的直链，截取才精确；换源后脚本会自动探测大小，不用手填。

## 六、命令

```bash
traffic-balancer.sh run              # 执行一次（cron 调用，静默，只写日志）
traffic-balancer.sh dry-run          # 只计算并打印计划，不下载，不动基线
traffic-balancer.sh status           # 网卡、基线、各源大小、最近 10 条记录
traffic-balancer.sh verify [n] [mb]  # 真实下载并删除，用于验证链路（不动基线）
traffic-balancer.sh reset            # 清空基线，下次运行重新建立
```

日常排查：

```bash
tail -f /var/log/traffic-balancer.log
column -s, -t /var/lib/traffic-balancer/history.csv | tail -20
```

## 七、内置保护

| 场景 | 处理 |
|---|---|
| 上一次任务还没跑完 | `flock` 抢不到锁 → 本次跳过 |
| 机器重启导致计数器归零 | 检测到负增量 → 重置基线，本次跳过 |
| 网卡名变化 | 重置基线，本次跳过 |
| 磁盘不够 | 需要空间 = 计划字节 × 1.2 + 16 MB，不足则跳过并记 `no_disk_space` |
| 目标量过大 | 受 `MAX_COUNT` 与 `MAX_PULL_MB_PER_RUN` 双重封顶 |
| 某个源 404 / 超时 | 该段失败自动换下一个源，失败也会删临时文件 |
| 日志膨胀 | 超 2 MB 截断保留最近 2000 行 |

## 八、实测参考（Debian 13 / 阿里云上海轻量 / ens5）

- 微信 Windows 安装包：`283,125,176` 字节（约 270 MiB）
- 清华 / 南大 Ubuntu ISO：`3,303,444,480` 字节（约 3150 MiB），均支持 Range
- 分段下载 30 MB：0.48 s（约 62 MB/s），临时目录文件数归零
- 决策自测：上小时 1 GiB → 计划 341.3 MB；2 GiB → 682.7 MB；5 GiB → 1200 MB（触发单次上限）
- 安装脚本自测：重复安装不产生重复 cron 项；`--force` 会备份旧配置；`--uninstall` 能完整回滚；管道模式（`curl | bash`）能正确走远程下载而非误判本地
- gh-proxy 加速：`https://v4.gh-proxy.org/https://raw.githubusercontent.com/...` 返回 200，内容与直连同源一致

## 九、注意事项

- **合规**：请仅用于自有服务器或已获授权的环境做流量/计费口径测试，并遵守云服务商的用户协议与当地法规。刻意改变计费流量可能违反服务条款。
- **计费口径**：不同厂商/套餐统计方向不同（有的只算出网，有的双向），上线前用 `DIRECTION` 与实际账单核对一次。
- **内网流量**：`/proc/net/dev` 统计的是网卡全部流量，内网互通也会计入；有大量内网通信时建议用 `tx` 口径。
- **空闲机器**：默认 `SKIP_BELOW_MB=60`，流量很低的时段不会触发下载；若希望任何时段都按比例产生流量，把它设为 `0`。
- **与其他监控共存**：本机会持续产生下行流量，若另有流量监控/告警脚本，注意可能被误判。

## License

MIT，见 [LICENSE](LICENSE)。
