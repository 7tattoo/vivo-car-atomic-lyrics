# 收藏❤️ + 播放列表 browse 树适配（Sonify vivo15 实测）

> 适配原子随身听手机端卡片的收藏按钮与播放列表入口。三个问题（播放列表置灰、❤️ 无反应、JoviInCar 无 ❤️）的根因和修复都在这里。能力位细节另见 [protocols.md](protocols.md) §2.2，收藏协议字段见 §4。

## 问题一：原子随身听卡片「播放列表」灰色无法点击

### 根因：`support_event` 能力位没给对

原子随身听卡片上的五个功能按钮各自受一个能力位控制，反编译 17.0.8.3 组件源码得到的对应关系（此前版本误标，已纠正）：

| 位值 | 按钮 | 组件源码依据 |
|---|---|---|
| 64 | ❤️ 收藏 | `f21118s` |
| 128 | 循环模式 | `f21117r` |
| 256 | 播放列表 / 当前列表 | `f21120u`（`iv_list_current`） |
| 512 | 喜欢列表 | `f21121v`（`iv_list_favorite`） |
| 1024 | 本地 / 下载列表 | `f21122w`（`iv_list_local`） |

之前给的是 `223 = 1|2|4|8|16|32|64`，缺 128/256/512/1024，且误以为 128 是「播放列表」。结果「播放列表」「喜欢」「本地」三个列表按钮全部置灰。

### 关键坑：后三列按「包名白名单」读，不是直接读 support_event

后三列（256/512/1024）在组件里读的是 `e1.a(pkgName)` —— 按**包名白名单**查出来的能力值。对官方白名单包（QQ音乐/酷狗/本地音乐等）这个函数返回 4095；对非白名单包（如 Sonify 用 `com.apple.android.music` 这种克隆包）会**回退到 `support_event` 本身**。所以非白名单包也必须把 `support_event` 给满 4095，三个列表按钮才点亮。

### 修复

```java
builder.putLong("vivomusicmix.media.metadata.support_event", 4095L);
```

且必须**无条件随每次 metadata / extras 发布**（不依赖是否有歌词）。否则无歌词的歌曲会连带收藏❤️ 和播放列表一起置灰。

## 问题二：❤️ 收藏点了没反应、再点不取消

### 现象

点击收藏后 App 侧实际已收藏成功，但卡片 ❤️ 不变（空心→实心没发生），再点无法取消（App 收到的是反复的「收藏」而不是「取消」）。

### 根因：收藏状态回传用错字段

media3 有两个 rating 字段，映射到 framework 不同 key：

- `userRating` → `android.media.metadata.USER_RATING`
- `overallRating` → `android.media.metadata.RATING`

原子随身听（CooperateController）读的是 framework 的 `RATING`。如果只设 `userRating`，组件读到的 RATING 恒空 → `isFavor` 恒 false → 每次都发 `heart=true`，卡片不刷新、也无法取消。

### 修复

1. **收藏按钮**通过 `setCustomLayout` 暴露一个 `CommandButton`，`SessionCommand` 用 `COMMAND_CODE_SESSION_SET_RATING`：

```kotlin
val favoriteButton = CommandButton.Builder()
    .setIconResId(if (isFav) R.drawable.ic_nowplaying_favorited
                  else R.drawable.ic_nowplaying_favorite)
    .setDisplayName("favorite")
    .setSessionCommand(SessionCommand(SessionCommand.COMMAND_CODE_SESSION_SET_RATING))
    .build()
mediaSession?.setCustomLayout(ImmutableList.of(shuffle, repeat, favoriteButton))
```

2. App 在 `onSetRating()` 里把 `rating as? HeartRating` 解析出收藏状态，执行收藏/取消。

3. **收藏后立即回传 `overallRating`（不是 `userRating`）** 并重发当前 mediaItem：

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

这样卡片 ❤️ 才会从空心变实心，取消也才生效。

## 问题三：JoviInCar 车载投屏没有 ❤️ 按钮 —— 属正常，不可修

JoviInCar 投屏端（智能车载 APK）的音乐卡片**固有 UI 就不渲染收藏按钮**，它只消费播放状态 + ucar 歌词通道。收藏（SET_RATING）和列表入口（browse）都是**原子随身听手机端**卡片的能力，App 无法通过 MediaSession 协议把 ❤️ 加到投屏卡片上。

参考软件「荣耀定制音乐」同样是：JoviInCar 只投歌词，收藏只在手机端原子随身听卡片生效。所以这个问题不要再去改协议或发 SET_RATING，属预期行为。

## 附：播放列表 browse 树

点「播放列表 / 当前列表 / 喜欢列表」后，原子随身听/车机（CooperateController）会直接 `subscribe` 这些**固定 parentId**，App 的 `onGetChildren` 必须原样识别并返回：

| parentId | 语义 | 数据源 |
|---|---|---|
| `vivomusicmix_current_list` | 当前 / 播放列表 | 当前播放队列 |
| `vivomusicmix_favorite_list` | 喜欢列表 | 本地收藏 + 在线收藏 |
| `vivomusicmix_local_list` | 本地 / 下载列表 | 本地扫描音乐 |

### 在线收藏列表为空的坑

在线收藏源（如酷狗）若只存 `favoriteHashes`（仅 hash）而不存完整歌曲信息，`onGetChildren("vivomusicmix_favorite_list")` 只返回本地收藏，就看不到在线收藏的歌。修复：在线收藏 sync 时保留全量歌曲信息（歌名/歌手/封面），收藏列表 = 本地 + 在线 `distinctBy mediaId` 去重；`resolveSongByMediaId` 也要加在线收藏反查，否则列表点歌解析不到。

## 一句话总结

- 播放列表置灰 → `support_event` 给满 `4095`，无条件随每次 metadata 发布。
- ❤️ 无反应/不取消 → 回传用 `overallRating`（HeartRating），不是 `userRating`。
- JoviInCar 无 ❤️ → 固有 UI 不支持，正常，不可修。
