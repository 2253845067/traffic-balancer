# 娴侀噺瀵圭瓑鑴氭湰锛坱raffic-balancer锛?
姣忓皬鏃剁粺璁℃湰鏈烘煇涓柟鍚戠殑鐪熷疄娴侀噺锛屾寜 `1/RATIO` 鎹㈢畻鍑洪渶瑕佽ˉ榻愮殑涓嬭浇閲忥紝鍐嶄粠鍙厤缃殑涓嬭浇婧愬垪琛ㄩ噷鎷夊彇鏁版嵁銆?*涓嬪畬绔嬪嵆鍒犻櫎**锛屼粠鑰屽湪璁¤垂鏂瑰悜涓婄ǔ瀹氬埗閫犲嚭鍥哄畾姣斾緥鐨勫弽鍚戞祦閲忋€?
浠撳簱鍦板潃锛?https://github.com/2253845067/traffic-balancer>

- 涓€鏉″懡浠ゅ畨瑁咃紝瑁呭畬鍗虫槸鍙敤鐘舵€侊紙鑷姩鍐?cron銆佸缓鍩虹嚎锛?- 涓嶇粦瀹氬叿浣撴枃浠讹細浠讳綍鑳界洿閾句笅杞界殑鍦板潃閮借锛堝畨瑁呭寘銆侀暅鍍?ISO銆佸ぇ鏂囦欢锛夛紝鍙湪閰嶇疆閲屽啓澶氫釜婧愭寜灏忔椂杞崲
- 绾?Bash锛屽彧渚濊禆 `curl` + `/proc/net/dev`锛屼笉闇€瑕?`vnstat`銆乣python3`銆乣jq`
- 鏂囦欢澶у皬鑷姩鎺㈡祴锛圚TTP HEAD + 鏈湴缂撳瓨锛夛紝鏃犻渶鎵嬪伐濉啓
- 鏀寔鎸夊瓧鑺傛埅鍙栵紙`Range`锛夛紝鍦ㄦ敮鎸佸垎娈典笅杞界殑婧愪笂鍙互**绮剧‘**鍑戝埌鐩爣閲忥紝鑰屼笉鏄暣鍖呯矑搴?- 纾佺洏鍗犵敤鏋佸皬锛氭枃浠惰竟涓嬭竟鍒狅紝涓存椂鐩綍甯告€佷负绌?- 闃茶嚜婵€锛氭湰娆′笅杞界殑娴侀噺涓嶄細璁″叆涓嬩竴灏忔椂鐨勭洰鏍?- 甯﹀苟鍙戦攣銆佺鐩樼┖闂存鏌ャ€佸崟娆℃祦閲忎笂闄愩€佹棩蹇楄嚜鍔ㄦ埅鏂?
## 涓€銆佷竴閿畨瑁?
**鏂瑰紡 A锛氳繙绋嬩竴閿紙鎺ㄨ崘锛?*

```bash
curl -fsSL https://raw.githubusercontent.com/2253845067/traffic-balancer/main/install.sh | bash
```

**鏂瑰紡 B锛氬厠闅嗗悗鏈湴瀹夎**

```bash
git clone https://github.com/2253845067/traffic-balancer.git
cd traffic-balancer
sudo bash install.sh
```

瀹夎鑴氭湰浼氳嚜鍔ㄥ畬鎴愶細

1. 妫€鏌ュ苟瀹夎缂哄け鐨勪緷璧栵紙`curl`銆乣util-linux`/`flock`銆乣cron`锛?2. 鎶?`traffic-balancer.sh` 瑁呭埌 `/usr/local/bin/`銆侀厤缃鍒?`/etc/traffic-balancer.conf`
3. 鍒涘缓鐘舵€佺洰褰?`/var/lib/traffic-balancer/`
4. 鍐欏叆 crontab锛堥粯璁ゆ瘡灏忔椂绗?17 鍒嗛挓锛夛紝骞剁‘淇?cron 鏈嶅姟鍦ㄨ繍琛?5. 璺戜竴娆?`dry-run` 寤虹珛鍩虹嚎锛堜笉浼氫笅杞斤級
6. 鎵撳嵃甯哥敤鍛戒护

瀹夎鑴氭湰鍙傛暟锛?
| 鍙傛暟 | 璇存槑 |
|---|---|
| `--force` | 鐢ㄤ粨搴撻噷鐨勬ā鏉胯鐩栧凡鏈夐厤缃紙榛樿淇濈暀浣犳敼杩囩殑閰嶇疆锛?|
| `--no-cron` | 鍙鏂囦欢锛屼笉鍐欏畾鏃朵换鍔?|
| `--min N` | 鎸囧畾瀹氭椂鐨勫垎閽熸暟锛岄粯璁?`17` |
| `--verify` | 瀹夎鍚庣湡瀹炰笅杞?30 MB 楠岃瘉閾捐矾 |
| `--uninstall` | 鍗歌浇锛堢Щ闄ゅ畾鏃朵换鍔°€佽剼鏈€侀厤缃級 |
| `--purge` | 涓?`--uninstall` 閰嶅悎锛屽悓鏃跺垹闄ょ姸鎬佺洰褰曚笌鏃ュ織 |

绀轰緥锛?
```bash
# 瀹夎骞堕『甯﹂獙璇佷笅杞介摼璺?curl -fsSL https://raw.githubusercontent.com/2253845067/traffic-balancer/main/install.sh | bash -s -- --verify

# 鎹㈠埌鍒殑鍒嗛挓鏁?curl -fsSL .../install.sh | bash -s -- --min 25

# 鍗歌浇浣嗕繚鐣欏巻鍙茶褰?curl -fsSL .../install.sh | bash -s -- --uninstall
```

> 杩滅▼妯″紡浼氫粠 `raw.githubusercontent.com` 鎷夊彇鏂囦欢锛涘浗鍐呯綉缁滆嫢鎷変笉鍔紝璇风敤鏂瑰紡 B锛坄git clone` 鍚庢湰鍦板畨瑁咃級锛屾垨鐢ㄧ幆澧冨彉閲忔崲婧愶細
> `RAW_BASE=https://浣犵殑闀滃儚/traffic-balancer bash install.sh`

## 浜屻€佸伐浣滃師鐞?
```
姣忓皬鏃剁殑 cron
   鈹?   鈹溾攢 璇?/proc/net/dev 鎷垮埌缃戝崱绱 RX/TX锛堝 ens5锛?   鈹溾攢 涓庝笂娆′繚瀛樼殑鍩虹嚎鐩稿噺 => 涓婁竴涓皬鏃剁殑鐪熷疄娴侀噺 D
   鈹溾攢 鐩爣涓嬭浇閲?T = D / RATIO             锛圧ATIO=3 鍗?1/3锛?   鈹溾攢 浠?DOWNLOAD_URLS 閲屾寜灏忔椂杞崲鍙栧湴鍧€锛屽垎 1~MAX_COUNT 娈典笅杞?   鈹?   鈹斺攢 TRIM_LAST=1 鏃舵渶鍚庝竴娈垫寜鈥滆繕宸灏戝瓧鑺傗€濈敤 Range 鎴彇
   鈹溾攢 姣忔涓嬪畬绔嬪嵆 rm锛岀鐩樹笉鍫嗙Н
   鈹斺攢 閲嶆柊璇诲彇璁℃暟鍣ㄥ啓鍥炲熀绾匡紙闃叉鏈涓嬭浇閲忔斁澶т笅涓€灏忔椂鐨勭洰鏍囷級
```

绀轰緥锛圧ATIO=3锛夛細

| 涓婂皬鏃舵祦閲?| 鐩爣閲?| 瀹為檯涓嬭浇 | 瀹為檯姣斾緥 |
|---|---|---|---|
| 1 GiB | 341 MB | 341 MB | 1/3 |
| 2 GiB | 683 MB | 683 MB | 1/3 |
| 5 GiB | 1707 MB | 1200 MB锛堝彈鍗曟涓婇檺绾︽潫锛?| 绾?1/4.3 |
| 100 MB | 33 MB | 33 MB | 1/3 |

> `TRIM_LAST=1`锛堥粯璁わ級浼氭寜鐩爣閲忔埅鍙栵紝姣斾緥鍙互鍋氬埌鎺ヨ繎绮剧‘锛涜 `TRIM_LAST=0` 鍒欏彧涓嬪畬鏁存枃浠讹紝绮掑害鍙樻垚"鏁翠釜鏂囦欢澶у皬"銆?
缁熻鏂瑰悜榛樿 `DIRECTION=tx`锛堝嚭缃?涓婅锛夛細闃块噷浜戣交閲忕瓑浜у搧鎸夊嚭缃戞祦閲忚璐癸紝鐢?tx 浣滀负鍩烘暟鍙互閬垮厤"鑷繁鍒堕€犵殑涓嬭娴侀噺鍙嶈繃鏉ユ姮鍗囦笅涓€灏忔椂鐩爣"鐨勬鍙嶉銆傝嫢浣犵殑濂楅鎸夊叆缃戣璐癸紝鎶?`DIRECTION` 鏀规垚 `rx`銆?
## 涓夈€佹枃浠惰鏄?
| 鏂囦欢 | 閮ㄧ讲浣嶇疆 | 璇存槑 |
|---|---|---|
| `traffic-balancer.sh` | `/usr/local/bin/traffic-balancer.sh` | 涓昏剼鏈紙755锛?|
| `traffic-balancer.conf` | `/etc/traffic-balancer.conf` | 閰嶇疆锛屾瘡娆¤繍琛岄噸鏂拌鍙栵紝鏀瑰畬鍗崇敓鏁?|
| `install.sh` | 涓嶅父椹伙紝瑁呭畬鍗冲彲鍒?| 涓€閿畨瑁?鍗歌浇 |
| 鍩虹嚎鐘舵€?| `/var/lib/traffic-balancer/state` | `鏃堕棿鎴?RX绱姞 TX绱姞 缃戝崱鍚峘 |
| 杩愯璁板綍 | `/var/lib/traffic-balancer/history.csv` | 姣忓皬鏃朵竴琛岋紝渚夸簬鏍稿 |
| 婧愬ぇ灏忕紦瀛?| `/var/lib/traffic-balancer/sizes.cache` | `url \t 瀛楄妭鏁?\t 鎺㈡祴鏃堕棿` |
| 涓存椂鐩綍 | `/var/lib/traffic-balancer/tmp/` | 浠呬笅杞戒腑瀛樺湪鍐呭 |
| 鏃ュ織 | `/var/log/traffic-balancer.log` | 瓒?2 MB 鑷姩鎴柇淇濈暀鏈€杩?2000 琛?|

`history.csv` 瀛楁锛歚鏃堕棿,缃戝崱,鏂瑰悜,姣斾緥,涓婂皬鏃禡B,鐩爣MB,娈垫暟,瀹為檯MB,璇存槑`
璇存槑鍒楀彇鍊硷細`done`銆乣dry_run`銆乣skip_below_threshold`銆乣no_disk_space`銆?
## 鍥涖€佹墜鍔ㄥ畨瑁咃紙涓嶆兂鐢ㄨ剼鏈椂锛?
```bash
install -m 755 traffic-balancer.sh   /usr/local/bin/traffic-balancer.sh
install -m 644 traffic-balancer.conf /etc/traffic-balancer.conf
( crontab -l 2>/dev/null | grep -v traffic-balancer.sh
  echo '17 * * * * /usr/local/bin/traffic-balancer.sh run >/dev/null 2>&1  # 娴侀噺瀵圭瓑' ) | crontab -
/usr/local/bin/traffic-balancer.sh dry-run        # 寤哄熀绾匡紝涓嶄笅杞?/usr/local/bin/traffic-balancer.sh verify 1 30    # 鍙€夛細楠岃瘉 30MB 涓嬭浇閾捐矾
```

鍗歌浇锛?
```bash
crontab -l | grep -v traffic-balancer.sh | crontab -
rm -f /usr/local/bin/traffic-balancer.sh /etc/traffic-balancer.conf
rm -rf /var/lib/traffic-balancer /var/log/traffic-balancer.log
```

## 浜斻€侀厤缃」

缂栬緫 `/etc/traffic-balancer.conf`锛屼繚瀛樺嵆鐢熸晥銆?
| 鍙橀噺 | 榛樿 | 璇存槑 |
|---|---|---|
| `IFACE` | `auto` | 缁熻缃戝崱锛宍auto` = 璺熼殢榛樿璺敱缃戝崱 |
| `DIRECTION` | `tx` | `tx` 鍑虹綉銆乣rx` 鍏ョ綉銆乣total` 鍙屽悜鍚堣 |
| `RATIO` | `3` | 鐩爣涓嬭浇閲?= 涓婂皬鏃舵祦閲?梅 RATIO |
| `MIN_COUNT` / `MAX_COUNT` | `1` / `2` | 姣忔涓嬭浇鐨勬鏁板尯闂?|
| `DOWNLOAD_URLS` | 寰俊鍖?+ 娓呭崕/鍗楀ぇ ISO | 绌烘牸鎴栨崲琛屽垎闅旂殑鐩撮摼鍒楄〃锛屾寜灏忔椂杞崲鍙栫敤 |
| `FALLBACK_PKG_SIZE` | `283125176` | 鎺㈡祴涓嶅埌 Content-Length 鏃剁殑鍏滃簳瀛楄妭鏁?|
| `TRIM_LAST` | `1` | `1` 鎸夊墿浣欓噺鎴彇锛堢簿纭級锛宍0` 鍙笅鏁存枃浠?|
| `SKIP_BELOW_MB` | `60` | 涓婂皬鏃舵祦閲忎綆浜庤鍊间笉涓嬭浇锛涜 `0` 鍏抽棴 |
| `MAX_PULL_MB_PER_RUN` | `1200` | 鍗曟杩愯鏈€澶氫笅杞界殑 MB |
| `LIMIT_RATE` | 绌?| 闄愰€燂紝`curl --limit-rate` 璇硶锛屽 `30m` |
| `CURL_MAX_TIME` | `1800` | 鍗曟涓嬭浇瓒呮椂锛堢锛?|
| `SIZE_CACHE_TTL_DAYS` | `7` | 婧愬ぇ灏忕紦瀛樻湁鏁堟湡锛堝ぉ锛?|

閫夋簮寤鸿锛氫紭鍏堟寫 **鏀寔 `Accept-Ranges: bytes`** 涓旂ǔ瀹氱殑鐩撮摼锛屾埅鍙栨墠绮剧‘锛涙崲婧愬悗鑴氭湰浼氳嚜鍔ㄦ帰娴嬪ぇ灏忥紝涓嶇敤鎵嬪～銆?
## 鍏€佸懡浠?
```bash
traffic-balancer.sh run              # 鎵ц涓€娆★紙cron 璋冪敤锛岄潤榛橈紝鍙啓鏃ュ織锛?traffic-balancer.sh dry-run          # 鍙绠楀苟鎵撳嵃璁″垝锛屼笉涓嬭浇锛屼笉鍔ㄥ熀绾?traffic-balancer.sh status           # 缃戝崱銆佸熀绾裤€佸悇婧愬ぇ灏忋€佹渶杩?10 鏉¤褰?traffic-balancer.sh verify [n] [mb]  # 鐪熷疄涓嬭浇骞跺垹闄わ紝鐢ㄤ簬楠岃瘉閾捐矾锛堜笉鍔ㄥ熀绾匡級
traffic-balancer.sh reset            # 娓呯┖鍩虹嚎锛屼笅娆¤繍琛岄噸鏂板缓绔?```

鏃ュ父鎺掓煡锛?
```bash
tail -f /var/log/traffic-balancer.log
column -s, -t /var/lib/traffic-balancer/history.csv | tail -20
```

## 涓冦€佸唴缃繚鎶?
| 鍦烘櫙 | 澶勭悊 |
|---|---|
| 涓婁竴娆′换鍔¤繕娌¤窇瀹?| `flock` 鎶笉鍒伴攣 鈫?鏈璺宠繃 |
| 鏈哄櫒閲嶅惎瀵艰嚧璁℃暟鍣ㄥ綊闆?| 妫€娴嬪埌璐熷閲?鈫?閲嶇疆鍩虹嚎锛屾湰娆¤烦杩?|
| 缃戝崱鍚嶅彉鍖?| 閲嶇疆鍩虹嚎锛屾湰娆¤烦杩?|
| 纾佺洏涓嶅 | 闇€瑕佺┖闂?= 璁″垝瀛楄妭 脳 1.2 + 16 MB锛屼笉瓒冲垯璺宠繃骞惰 `no_disk_space` |
| 鐩爣閲忚繃澶?| 鍙?`MAX_COUNT` 涓?`MAX_PULL_MB_PER_RUN` 鍙岄噸灏侀《 |
| 鏌愪釜婧?404 / 瓒呮椂 | 璇ユ澶辫触鑷姩鎹笅涓€涓簮锛屽け璐ヤ篃浼氬垹涓存椂鏂囦欢 |
| 鏃ュ織鑶ㄨ儉 | 瓒?2 MB 鎴柇淇濈暀鏈€杩?2000 琛?|

## 鍏€佸疄娴嬪弬鑰冿紙Debian 13 / 闃块噷浜戜笂娴疯交閲?/ ens5锛?
- 寰俊 Windows 瀹夎鍖咃細`283,125,176` 瀛楄妭锛堢害 270 MiB锛?- 娓呭崕 / 鍗楀ぇ Ubuntu ISO锛歚3,303,444,480` 瀛楄妭锛堢害 3150 MiB锛夛紝鍧囨敮鎸?Range
- 鍒嗘涓嬭浇 30 MB锛?.48 s锛堢害 62 MB/s锛夛紝涓存椂鐩綍鏂囦欢鏁板綊闆?- 鍐崇瓥鑷祴锛氫笂灏忔椂 1 GiB 鈫?璁″垝 341.3 MB锛? GiB 鈫?682.7 MB锛? GiB 鈫?1200 MB锛堣Е鍙戝崟娆′笂闄愶級
- 瀹夎鑴氭湰鑷祴锛氶噸澶嶅畨瑁呬笉浜х敓閲嶅 cron 椤癸紱`--force` 浼氬浠芥棫閰嶇疆锛沗--uninstall` 鑳藉畬鏁村洖婊?
## 涔濄€佹敞鎰忎簨椤?
- **鍚堣**锛氳浠呯敤浜庤嚜鏈夋湇鍔″櫒鎴栧凡鑾锋巿鏉冪殑鐜鍋氭祦閲?璁¤垂鍙ｅ緞娴嬭瘯锛屽苟閬靛畧浜戞湇鍔″晢鐨勭敤鎴峰崗璁笌褰撳湴娉曡銆傚埢鎰忔敼鍙樿璐规祦閲忓彲鑳借繚鍙嶆湇鍔℃潯娆俱€?- **璁¤垂鍙ｅ緞**锛氫笉鍚屽巶鍟?濂楅缁熻鏂瑰悜涓嶅悓锛堟湁鐨勫彧绠楀嚭缃戯紝鏈夌殑鍙屽悜锛夛紝涓婄嚎鍓嶇敤 `DIRECTION` 涓庡疄闄呰处鍗曟牳瀵逛竴娆°€?- **鍐呯綉娴侀噺**锛歚/proc/net/dev` 缁熻鐨勬槸缃戝崱鍏ㄩ儴娴侀噺锛屽唴缃戜簰閫氫篃浼氳鍏ワ紱鏈夊ぇ閲忓唴缃戦€氫俊鏃跺缓璁敤 `tx` 鍙ｅ緞銆?- **绌洪棽鏈哄櫒**锛氶粯璁?`SKIP_BELOW_MB=60`锛屾祦閲忓緢浣庣殑鏃舵涓嶄細瑙﹀彂涓嬭浇锛涜嫢甯屾湜浠讳綍鏃舵閮芥寜姣斾緥浜х敓娴侀噺锛屾妸瀹冭涓?`0`銆?- **涓庡叾浠栫洃鎺у叡瀛?*锛氭湰鏈轰細鎸佺画浜х敓涓嬭娴侀噺锛岃嫢鍙︽湁娴侀噺鐩戞帶/鍛婅鑴氭湰锛屾敞鎰忓彲鑳借璇垽銆?
## License

MIT锛岃 [LICENSE](LICENSE)銆?