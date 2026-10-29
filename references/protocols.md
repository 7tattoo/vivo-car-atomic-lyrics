# 协议字段表（跨版本稳定，必须原样保留）

## 1. 车联投屏（ucar / JoviInCar）

写入位置：`MediaMetadata`（即 `MediaSession.setMetadata()` 的内容）。

| 字段 | 类型 | 值 | 是否必须 |
|---|---|---|---|
| `ucar.media.metadata.LYRICS_WHOLE` | String | 完整 LRC 文本 | **必须** |
| `ucar.media.metadata.LYRICS_STATUS` | Long | `0` = 有歌词 | 建议写 |
| `ucar.media.metadata.UCAR_TITLE` | String | 歌名 | 可选 |
| `ucar.media.metadata.UCAR_ARTIST` | String | 艺术家 | 可选 |

`LYRICS_WHOLE` 格式就是标准 LRC，行级时间戳：

```
[00:12.34]第一行歌词
[00:18.90]第二行歌词
[00:25.10]第三行歌词
```

时间戳 `[mm:ss.SSS]` 或 `[mm:ss.SS]` 均可被车机解析。多行用 `\n` 分隔。

### 绝不能写的

- [禁] `ucar.media.metadata.LYRICS_LINE` ： 单行协议信号。车机收到就切单行卡片布局，并**忽略 `LYRICS_WHOLE`**。
- [禁] `music.media.extras.*` 通道（`LYRIC` / `LYRIC_IS_ALLOWED` / `NOTICE_CAR`）： 单行通道。用 500ms 定时器推 extras 会把车机卡片**压回单行**。
- [禁] `LYRICS_STATUS = 1/2` ： 语义是"本曲确认无歌词"，不是"加载中"。歌词异步加载，连车后通知栏刷新**先于**歌词就绪；此时写负状态，车机**永久退回单行**。

## 2. 原子随身听（vivomusicmix）

### 2.1 AndroidManifest 声明（**必须**）

在 `MediaBrowserService` 的 intent-filter 里加 vivo action，否则原子随身听不识别你的 App：

```xml
<service
    android:name=".YourMediaBrowserService"
    android:exported="true">
    <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
        <action android:name="com.vivo.musicwidgetmix.support.service" />
    </intent-filter>
</service>
```

`apply.sh` 会自动插入并校验它在整个 manifest 里只出现一次。这个 action 让原子随身听选择**合作控制器**；歌词事件只有合作控制器才处理，所以 **action 必须加，不能撤**。

### 2.2 能力位 support_event（写在 MediaMetadata 里）

```java
builder.putLong("vivomusicmix.media.metadata.support_event", 31L);
```

推荐直接给全量 `4095`（bit0~11 全开，对齐官方 QQ音乐/酷狗/本地音乐白名单），而不是自己拼位。经验证的最小可点播值见下表：

```java
builder.putLong("vivomusicmix.media.metadata.support_event", 4095L);
```

`4095 = 1|2|4|8|16|32|64|128|256|512|1024`：

| 位值 | 含义 | 原子源码依据（反编译 17.0.8.3，含误判纠正） |
|---|---|---|
| 1 / 2 / 4 | 基础播控（原子对未知应用默认 7） | `getSupportEvent()` 默认值 |
| 7 | 播放/暂停/上下曲 | |
| 8 | **歌词** | `f5/n.java`、`f5/b.java`：`b1.c(P0(), 8)` |
| 16 | 进度条 / seek / 时间显示 | `t4/d0.java`：`duration > 0 && b1.c(P0(), 16)` |
| 32 | 自定义颜色 / 互传 | `SettingsMainView`、锁屏组件 |
| 64 | **❤️ 收藏按钮** enable | `f21118s`（之前误标为「列表入口」） |
| 128 | **循环模式按钮** enable | `f21117r`（之前误标为「未确认/播放列表」） |
| 256 | **播放列表/当前列表** enable | `f21120u`（`iv_list_current`） |
| 512 | **喜欢列表** enable | `f21121v`（`iv_list_favorite`） |
| 1024 | **本地/下载列表** enable | `f21122w`（`iv_list_local`） |

**关键坑（Sonify vivo15 实测）**：

- 后三列（256/512/1024）在组件里读的是 `e1.a(pkgName)` 按**包名白名单**的能力值；对非白名单包（如 Sonify 用 `com.apple.android.music`）回退到 `support_event` 本身。官方白名单返回 4095，所以非白名单包也要给 4095 才能点亮全部列表按钮。
- 之前误把 128 当「播放列表」、且只给 223（缺 256/512/1024）→ **三个列表按钮（播放列表/喜欢/本地）全部置灰无法点击**。
- `support_event` 必须**无条件随每次 metadata/extras 发布**（不依赖歌词），否则无歌词的歌曲会连带收藏❤️ 与「播放列表」一起置灰。

**合作控制器 `c0.k0()` 原样读取这个值，不会自己补位**；通用控制器 `y2` 才会根据 `ACTION_SEEK_TO` 自行算出 23。所以走合作路径时缺 16 位就永远 `--:--`。

能力位判定来自原子随身听反编译源码：`utils/b1.c(a, m) == ((a & m) == m)`。

### 2.3 lrc_change 事件（通过 setExtras 发送）

```java
Bundle b = new Bundle();
b.putString("vivomusicmix.meida.extra.key.action",
            "vivomusicmix.extra.lrc_change");
b.putString("vivomusicmix.extra.key.lyric", wholeLrc);     // 整段 LRC
b.putString("vivomusicmix.extra.key.meidia_id", mediaId);  // 当前曲目 ID
session.setExtras(b);
```

> [注意] **vivo 官方拼写错误必须照抄**：
> - `meida.extra.key.action`（不是 `media`）
> - `extra.key.meidia_id`（不是 `media_id`）
>
> 写成正确拼写反而收不到。

### 2.4 发送时机与频率控制

`lrc_change` 是**事件**，不需要高频推送。推荐策略：

- 切歌时（歌词就绪后）发一次
- 之后每 25 秒左右重发一次，兜底覆盖"车机在播放开始后才连上"的情况

**没有 `lrc_change` 要发时，不要调用 `setExtras(空Bundle)`** ： 那会把车机/组件已收到的 extras 清空。

```java
private static boolean shouldResendLrc() {
    if (sWholeLrc == null || sWholeLrc.isEmpty()) return false;
    return System.currentTimeMillis() - sLastLrcSentAt >= 25_000L;
}
```

**踩过的坑**：这个判断最初写反了（`elapsed < 25s` 才发），等价于永远不发，导致车机在播放开始后才连上时首曲永远没歌词，必须切歌才恢复。

### 2.5 关键认知：lrc_change 是两个显示位的共同来源

反编译车联 6.0.8.3 确认：车联**并不读取** `music.media.extras.*` 那三个 key，车机和仪表的歌词实际来自原子随身听 `lrc_change` 整首 LRC 事件：车联在 `eg/l.java onExtrasChanged()` 里消费同一个事件并自己按时间切行。所以 **`lrc_change` 事件是车机歌词的真正来源，不能删也不能改拼写**；`music.media.extras.*` 三个 key 保留是为了兼容其它车联版本。

## 3. 封面（artUri）投递规则

封面走的是**独立链路**，和歌词互不依赖，字段很简单但工程坑最多（见 [card-cover.md](card-cover.md)）。

| 项 | 规则 |
|---|---|
| 载体 | `MediaMetadata.artUri`（framework）/ `MediaItem.artUri`（audio_service / media3） |
| 协议 | **只投 `http(s)`**：`content://`、`file://` 卡片侧拉不到 |
| 尺寸 | 480px 级小图；原图 1~2MB 会下载超时 → 纯色 |
| 归一化 | https + 替换 `{size}` 占位符 + `Uri.parse` 转义，统一一个出口函数 |
| 空串语义 | **不是清空**：非空才覆盖，换曲才清 |
| 能力位 | `support_event = 4095` 要随**首个** MediaItem / extras 一起发布 |
| 整份替换 | `audio_service` 每次 `mediaItem.add()` 都整份 `setMetadata()`，协议字段必须放进 `extras` 才会被写回 |

诊断日志要分四层：`songId / 原始地址 / 归一后地址 / 是否为空`。原始有、归一后空 = 地址不合法；归一后有、卡片仍纯色 = 卡片侧拉图被拦或超时；原始就空 = 数据源没给。

## 4. 收藏（❤️）与列表入口（Sonify vivo15 实测补充）

### 4.1 收藏按钮怎么来的

收藏按钮通过 `MediaSession.setCustomLayout()` 暴露一个 `CommandButton`，其
`SessionCommand` 用 `COMMAND_CODE_SESSION_SET_RATING`：

```kotlin
val favoriteButton = CommandButton.Builder()
    .setIconResId(if (isFav) R.drawable.ic_nowplaying_favorited
                  else R.drawable.ic_nowplaying_favorite)
    .setDisplayName("favorite")
    .setSessionCommand(SessionCommand(SessionCommand.COMMAND_CODE_SESSION_SET_RATING))
    .build()
mediaSession?.setCustomLayout(ImmutableList.of(shuffle, repeat, favoriteButton))
```

App 侧在 `onSetRating()` 里把 `rating as? HeartRating` 解析出收藏状态，执行收藏/取消。

### 4.2 收藏状态回传（解决「点了没反应、再点不取消」）

**根因**：media3 的 `userRating → USER_RATING`、`overallRating → RATING`，而
原子随身听（CooperateController）读的是 framework 的 `android.media.metadata.RATING`。
**必须设 `overallRating`（不是 `userRating`）**，否则组件读到的 RATING 恒空、
`isFavor` 恒 false → 反复发 `heart=true`、卡片 ❤️ 不刷新、也无法取消。

```kotlin
private fun refreshCurrentRating(isFavorite: Boolean) {
    val c = mediaControl ?: return
    val index = c.currentMediaItemIndex
    if (index == C.INDEX_UNSET) return
    val item = c.getMediaItemAt(index)
    val metadata = item.mediaMetadata.buildUpon()
        .setOverallRating(HeartRating(isFavorite))
        .build()
    c.replaceMediaItem(index, item.buildUpon().setMediaMetadata(metadata).build())
}
```

收藏后立即回传 `overallRating` 并重发当前 mediaItem，卡片 ❤️ 才会从空心变实心。

### 4.3 播放列表 browse 树（解决「播放列表置灰/点了没内容」）

原子随身听/车机（CooperateController）点「播放列表 / 当前列表 / 喜欢列表」后会
直接 `subscribe` 这些**固定 parentId**，App 的 `onGetChildren` 必须原样识别并返回：

| parentId | 语义 | 数据源 |
|---|---|---|
| `vivomusicmix_current_list` | 当前/播放列表 | 当前播放队列 |
| `vivomusicmix_favorite_list` | 喜欢列表 | 本地收藏 + 在线收藏（酷狗「我喜欢」） |
| `vivomusicmix_local_list` | 本地/下载列表 | 本地扫描音乐 `MusicLibrary.songs` |

**在线收藏列表为空的坑**：在线收藏源（如酷狗）若只存 `favoriteHashes`（仅 hash）
而不存完整歌曲信息，`onGetChildren("vivomusicmix_favorite_list")` 只返回本地收藏
就看不到在线收藏的歌。修复：在线收藏 sync 时保留 `List<YosMediaItem>` 全量（歌名/
歌手/封面），收藏列表 = 本地 + 在线 `distinctBy mediaId` 去重；`resolveSongByMediaId`
也要加在线收藏反查，否则列表点歌解析不到。

### 4.4 JoviInCar（车载投屏）没有收藏按钮 —— 属正常，不可修

JoviInCar 投屏端（智能车载 APK）的音乐卡片**固有 UI 就不渲染 ❤️ 收藏按钮**，它只
消费播放状态 + ucar 歌词通道。收藏（SET_RATING）和列表入口（browse）是**原子随身听
手机端**卡片的能力，App 无法通过 MediaSession 协议把 ❤️ 加到投屏卡片上。参考软件
「荣耀定制音乐」同样是：JoviInCar 只投歌词，收藏只在手机端原子随身听卡片生效。