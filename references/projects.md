# 五个历史项目的适配档案

> 先看同类项目怎么做的，再动手。每个项目代表一种目标 App 类型。

## 1. hachimi（TattooMusic 上游）

- **引擎/语言**：Kotlin + Jetpack Media3，源码级适配（有完整源码）。
- **做法**：
  - 新建 `VivoCarLyricsBridge` 类：ucar `LYRICS_WHOLE` + `LYRICS_STATUS=0` + vivomusicmix `lrc_change`（25s 重发，官方拼写 meida/meidia 照抄）。
  - manifest 给 `MediaBrowserService` 加 `com.vivo.musicwidgetmix.support.service` action。
  - `applicationId` 克隆到目标包名（`LyricInfoBuilder` 的 provider/source 同步改）。
- **注意**：`applicationId` 克隆后 Oboe/AudioSink 等 native `.so` 的 JNI 绑定只依赖 Kotlin 类全限定名，与 applicationId 无关，**无需重建 .so**（改 Kotlin 包名才需要）。
- 与 SamsungMusicRC 同包名会撞（signature 不同装不上第二个）。

## 2. TattooMusic

- 同 hachimi 引擎，包名按 flavor 分流，固定用 spotify flavor（`com.spotify.music`）。
- 构建命令：
  `./gradlew :app:assembleSpotifyRelease --no-daemon --no-configuration-cache -x lint`

## 3. md3Music（Apple Music 包名 `com.apple.android.music`）

- **引擎/语言**：Flutter + Rust。
- **做法**（源码级，Java 层 hook）：
  1. 包名 `com.md3music.md3music` → `com.apple.android.music`（全局 sed + Kotlin 目录 git mv）。
  2. **车联投屏**：`AudioPlayer.java doApplySessionTitleArtistAndLyricInfo` 的 extras 注入 `LYRICS_WHOLE` + `LYRICS_STATUS=0` + `support_event=31`。lyricInfo JSON 的 lyric 字段去 ELRC 词级标签 `<mm:ss.xxx>` 转纯 LRC；无歌词时 remove，避免负状态永久单行。
  3. **关键**：`MediaSessionCompat` 内部实现 `MediaSessionImplApi21.setMetadata`（legacy/MediaSessionCompat.java 4055 行）hook ： 读 `metadata.getBundle().getString(UCAR_LYRICS_WHOLE)`，**提升到 framework `MediaMetadata` 顶层**（putString LYRICS_WHOLE + putLong LYRICS_STATUS=0 + support_event=31）+ 歌词就绪时发 framework `setExtras` lrc_change（25s 节流）。
  4. **manifest**：`MD3MusicMediaSessionService` 加 `com.vivo.musicwidgetmix.support.service`，`exported=true`（原为 false，外部绑不上 → 原子随身听拿不到任何信息）。
  5. **坑**：media3 legacy `MediaMetadataCompat` **没有 `getExtras()`**（是 `getBundle()`）→ 编译错误改 `getBundle`。
- 用户实测反馈：原子通知通了（封面/歌曲信息），但进度条跟歌词没有 → 根因是 `lyric_push_protocol` 默认 `'none'`（歌词推送协议默认关闭，extras 无 LYRICS_WHOLE → hook 不写能力位 → support_event 缺 8/16 位）。**注意检查目标 App 的歌词推送开关**。

## 4. NeriPlayer（NeriPlayer 包名）

- **引擎/语言**：Flutter。
- **关键认知**：`lrc_change` 事件是**车机 + 仪表两个显示位的共同来源**（`onExtrasChanged()` → `WholeLyricManager` 自己按进度切行）。所以 `lrc_change` **不能删也不能改拼写**。
- **坑**：`artUri` 用 `http://`（某些车机/原子组件不消费 `https://` 封面 URI；kugou API 原生就是 http，原子 networkSecurityConfig 允许明文）。反向替换 `https://` → `http://`。
  > [注意] 这条结论**会随组件版本反转**：kgka_Music_hl 在 2026-10 的 vivo 组件上实测 http 被拦、必须 https。做新项目时两种都试一遍再定论，别照抄。见 [card-cover.md](card-cover.md) 第 3 条。
- **另一坑**：metadata 不再携带整段歌词（UCAR_LYRICS_WHOLE/LYRICS_STATUS 停用），歌词照走 `lrc_change` extras 事件。
- **能力位**：`support_event=31` 全更新；manifest 加 `com.vivo.musicwidgetmix.support.service` action。
- 仪表长句截断与逐句封面重载属**车联侧固定逻辑**（`HudManager`），已决定不处理，不要再提出绕过方案。

## 5. kgka_Music_hl（Flutter + audio_service，酷狗 / 网易云双源）

- **引擎/语言**：Flutter + `audio_service` 0.18.x + 原生 Kotlin 桥（`VivoCarLyrics.kt`）；包名由 flavor 提供（`com.apple.android.music` / `com.spotify.music`，沿用白名单策略）。
- **通道**：歌词 + 能力位 + 封面**全部经 `MediaItem.extras` 发布**，让 audio_service 自己写回 metadata —— 它每次 `mediaItem.add()` 都整份 `setMetadata()`（实测 `AudioService.java:786-804`）。只走原生通道注入的字段，任何一次逐行歌词更新都会被抹掉。
- **关键**：`support_event=31` 放进**初始** extras（组件绑定时只读一次）；整段 LRC 走 `lrc_change`（25s 兜底重发）；逐行歌词更新时也要把协议 extras 一起带上。
- **封面 8 条坑全踩过**：`{size}` 占位符 404、http 被拦、原图过大超时、酷狗搜索接口不给 `imgurl`、永久负缓存、空串清空已投递封面、`artUri` 读原始字段而不是异步补取结果。完整复盘见 [card-cover.md](card-cover.md)。
- **UI 侧同时踩到**：升级安装后首启，播放页在「没有当前歌曲」时返回空 `Scaffold` → 整屏纯黑、没有返回入口；冷启动首帧 `MediaQuery.size = 0×0` 又被误判成极小窗口 → 进纯黑兜底页。两处都要换成可见、可退的兜底。
- **教训**：用户报「封面纯色」时，先分层（原始地址 / 归一后地址 / 卡片侧拉图），别一上来改协议 —— 这次真正的根因里没有一条是协议字段写错。

## 通用经验（跨项目）

- **先确认数据源有没有数据，再调协议细节**。最典型的一串迭代（SamsungMusicPort v1.1.7→1.1.10）都在改"怎么推歌词字段"，但真正的瓶颈是**后台根本没有歌词可推**。
- **包名克隆**：`applicationId` 改后，注意 `LyricInfoBuilder` / provider / source 等字符串同步；Flutter 项目注意 `android/app/build.gradle` 的 `applicationId`。
- **Flutter 项目**：歌词推送协议开关（如 `lyric_push_protocol`）默认关闭会直接导致无歌词，先查设置项。
- **`com.vivo.musicwidgetmix.support.service` action**：整个 manifest 里必须**只出现一次**。