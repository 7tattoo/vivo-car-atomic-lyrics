# 症状速查与协议总览（vivo 车载歌词）

## 两套协议总览

- **车联投屏（ucar / JoviInCar）**：显示在车机中控屏音乐卡片；载体 `MediaMetadata`；歌词为整段 LRC；滚动由车机按 `PlaybackState` 自行驱动；不需要 manifest 声明；关键字段 `ucar.media.metadata.LYRICS_WHOLE`。
- **原子随身听（vivomusicmix）**：显示在手机/车机音乐小组件（原子通知歌词）；载体 `MediaSession.setExtras()`；歌词为整段 LRC；组件按进度自行滚动；**需要 manifest 声明**；关键字段 `vivomusicmix.extra.key.lyric`。

两个显示位同时适配、互不干扰。完整字段表见 [protocols.md](protocols.md)。

## 症状 → 根因速查

- **卡片永远单行**：写了 `LYRICS_LINE` 或 `music.media.extras.*`。
- **连车后立刻单行，后面怎么推都没用**：歌词未就绪时写了 `LYRICS_STATUS=1/2` 负状态。
- **切歌瞬间多行，播十几秒变单行**：500ms 定时器在推单行 extras 通道。
- **前台正常，切后台变单行**：只 hook 了切歌路径，通知刷新覆盖 metadata。
- **进过播放页后切「下一首」多行，再往下切单行**：歌词加载全绑 UI，后台无人加载。
- **第一遍约 1/6 概率多行，第二遍稳定**：session 引用为 null，补推被跳过。
- **歌词加载完车机还不显示**：切歌时那次没歌词，之后没补推。
- **首曲卡片无封面 / 标题不全**：热路径写了全局 metadata 缓存。
- **首曲破音 / 音频卡顿**：热路径做了文件 IO（日志落盘、mkdirs）。
- **原子随身听不显示歌词区**：manifest 缺 action，或 `support_event` 没带 `8` 位。
- **原子随身听收不到歌词**：`meida` / `meidia` 拼写被「纠正」。
- **车机播放开始后才连上，首曲无歌词**：`lrc_change` 重发判断写反。
- **已显示的歌词突然消失**：推了空 Bundle 的 `setExtras()`。