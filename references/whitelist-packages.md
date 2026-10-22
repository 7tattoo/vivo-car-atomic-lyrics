# 实机验证过的包名白名单

> 以下 11 个包名是**实机测试支持 JoviInCar 主页滚动歌词（且不套用车载音乐皮肤）**的第三方应用。
> 适配时把目标 App 的 `applicationId`（包名克隆）改成下面选定的一个。

| 包名 | 应用 | 备注 |
|---|---|---|
| `com.tencent.wecarflow` | Tx 爱趣听 | 车机主页滚动歌词 |
| `com.tencent.ibg.joox` | Joox 音乐 | 车机主页滚动歌词 |
| `com.spotify.music` | Spotify（声破天） | 车机主页滚动歌词 + **支持原子通知歌词** |
| `com.apple.android.music` | Apple Music | 车机主页滚动歌词 + **支持原子通知歌词** |
| `com.luna.music.car` | 汽水音乐车机版 | 车机主页滚动歌词 |
| `com.kugou.android.auto` | 酷狗音乐车载版 | 车机主页滚动歌词 |
| `cn.kuwo.kwmusiccar` | 酷我音乐车机版 | 车机主页滚动歌词 |
| `com.qidian.QDReader` | 起点读书 | 车机主页滚动歌词 |
| `com.tencent.weread` | 微信读书 | 车机主页滚动歌词 |
| `cn.aqzscn.stream_music` | 音流 | 车机主页滚动歌词 |
| `com.netease.cloudmusic.iot` | 网易云音乐车载版 | 车机主页滚动歌词 |

## 决策规则（强制闸门，见 SKILL.md「第 0 步：包名闸门」）

- **只要求 JoviInCar 车载歌词（单相要求）** → 询问用户从**上面 11 个包名中选一个**。
- **要求包含原子通知 / 原子随身听歌词** → 询问用户从 **`com.apple.android.music`（Apple Music）/ `com.spotify.music`（Spotify）两个包名中选一个**。

> ⛔ **禁止模型自行指定包名**。不许因为「Spotify 两个通道都支持」「Apple Music 文档最全」就替用户拍板；
> 用户答「随便/你定」也要把选项和代价（撞包名、覆盖已有安装）讲清楚，让他明确点一个。
> 没拿到用户明确回答 → 不进入反编译/改代码/构建任何一步。交付前自检：成品包名 == 用户确认的包名。

## 支持矩阵

| 能力 | 涉及的包名 |
|---|---|
| JoviInCar 主页滚动歌词 | 全部 11 个 |
| 原子通知歌词 | 仅 Apple Music、Spotify |

> [注意] 白名单之外的包名未经实机验证，**不要擅自选用**；用户若要求白名单外的包名，需先向用户说明未验证风险。

## 已知冲突

- `com.spotify.music` 与 SamsungMusicRC 同包名，同机装会撞（signature 不同装不上第二个）。