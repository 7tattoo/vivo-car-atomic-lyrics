# 如何定位 Hook 点（摸清目标 App 的 metadata 出口与歌词加载器）

> 拿到一个陌生 App，第一步不是写注入代码，而是把它的 metadata 出口和歌词加载路径摸清。

## Step 1　确认参照物

拿 **酷我音乐 12.0.8.0** 当基准（车机多行正常）。
不要拿"joviincar 适配版"当参照 ： 那些是单行方案。

关键类路径（酷我 12.0.8.0）：
```
classes6.dex  cn/kuwo/mod/playcontrol/session/vivo/carlink/ViVoCarLinkMediaSessionBridge  ← 车机
              cn/kuwo/mod/playcontrol/session/vivo/ViVoMediaSessionBridge                  ← 原子随身听
classes4.dex  cn/kuwo/mod/playcontrol/session/vivo/carlink/CarLinkMediaMetadata            ← 协议常量表
```

## Step 2　摸清 metadata 出口

```bash
# 找所有 setMetadata 调用
grep -rn "MediaSession;->setMetadata\|MediaSessionCompat;->setMetadata" smali*/
# 找 MediaSessionCompat 内部实现的汇聚点
grep -rn "Landroid/media/session/MediaSession;->setMetadata" smali/android/support/v4/media/session/
```

把所有路径列出来，找出**唯一汇聚点**。几乎所有播放器都有多条 metadata 推送路径（通知刷新、播放状态、队列变化、切歌、独立播放器等）。只 hook 切歌那条，通知刷新会推一份不含歌词的 metadata **覆盖**车机上已有的。

## Step 3　摸清歌词加载路径

```bash
# 先找歌词加载器入口（类名各 App 不同，从歌词界面反查）
grep -rn "lyrics" smali*/ --include=*.smali -l | head -20
# 找到加载方法后，列出所有调用点，逐个判断是否绑 UI
grep -rn "LyricsLoader;->requestLyric" smali*/
```

**如果所有调用点都在 UI 里，你必须自己加一条后台请求路径**（否则车机后台切歌时没有任何代码去加载歌词）。

典型的"全绑 UI"表现：Samsung Music 全 APK 只有 5 处触发歌词加载，其中 4 处是 UI（全屏播放器分页适配器会**预取相邻曲目**）、1 处是 Bixby 语音、1 处是服务端只认三星私有 `REQUEST_LYRIC`。vivo 车机只发 `ucar.*`/`vivomusicmix.*`，永远不会发厂商私有 `REQUEST_LYRIC`。

## Step 4　写注入代码

按 `protocols.md` 字段表写，严守热路径三条铁律。

## Step 5　挂 hook

- metadata 注入 → 统一出口（要点一）
- session 引用抓取 → 同一个出口（要点三）
- 歌词请求 → 切歌回调（要点二）
- 补推 → 歌词加载回调（要点四）

## Step 6　字段级验证（**必做**）

改完**一定要解包成品包再 grep 一遍**。曾跳过这步漏掉第二条独立注入路径（那个 App 除主桥接类外还有个 `UcarLyrics` 辅助类同样在写 `LYRICS_LINE`），白发一个版本。

```bash
for apk in 能用的.apk 不能用的.apk 自己的.apk; do
  echo "=== $apk ==="
  unzip -p "$apk" 'classes*.dex' > /tmp/all.dex 2>/dev/null
  for k in ucar.media.metadata.LYRICS_WHOLE \
           ucar.media.metadata.LYRICS_LINE \
           music.media.extras.NOTICE_CAR; do
    printf "  %-40s %s\n" "$k" \
      "$(strings /tmp/all.dex | grep -qF "$k" && echo 存在 || echo 无)"
  done
done
```

期望结果：`LYRICS_WHOLE` 存在，`LYRICS_LINE` 与 `music.media.extras.*` 全部为"无"。