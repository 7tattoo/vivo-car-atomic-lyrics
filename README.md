# vivo 车机滚动歌词 + 原子随身听适配

把任意 Android 音乐 / 音频 App 适配到 vivo 车机的两个歌词显示位：

| 显示位 | 通道 | 关键字段 |
| --- | --- | --- |
| 车联投屏 / JoviInCar 车机主页滚动歌词 | `ucar` | `ucar.media.metadata.LYRICS_WHOLE` |
| 原子随身听 / 原子通知歌词 | `vivomusicmix` | `vivomusicmix.extra.key.lyric` + `lrc_change` 事件 |

这份文档来自 **hachimi / TattooMusic / md3Music（Apple Music 包名）/ NeriPlayer** 四个项目的实车适配，
外加对 **酷我音乐 12.0.8.0** 的逆向对照。文中每一条「绝不能做」都是踩过的坑。

## 一句话核心认知

网上流传的「joviincar 歌词适配版」基本都是**单行方案**。真正能出滚动多行的参照实现是酷我音乐 **12.0.8.0**
（不是车机版 7.6.6.21）。反编译它的 `ViVoCarLinkMediaSessionBridge`，写车载歌词只有一行有效代码：

```java
builder.putString("ucar.media.metadata.LYRICS_WHOLE", lrc);
```

车机自己按 `PlaybackState` 的进度滚动歌词。App 的职责只是把**整段 LRC** 交给车机，
**不需要、也不应该**推送「当前是第几行」。

## 为什么「字段写对了还是只有一行」

字段正确只是第一步。真正决定成败的是四个工程问题，缺任何一个都会概率性退回单行：

1. **在 metadata 的唯一出口注入** —— 播放器有多条推送路径（通知刷新、播放状态、队列变化、切歌、独立播放器）。
   只 hook 切歌那条，后台通知栏刷新会推一份不含歌词的 metadata 覆盖车机已有的。
2. **主动请求歌词加载**（最致命）—— 多数播放器把歌词加载绑在 UI 上（只有打开全屏播放器才加载）。
   vivo 车机只发 `ucar.*` / `vivomusicmix.*`，从不发厂商私有请求，所以后台切歌时没有任何代码去加载歌词。
3. **抓住 MediaSession 引用** —— 歌词异步到达后要补推 metadata，必须有 session 引用；
   只在某条推送路径赋值，后台切歌时会是 null。
4. **歌词异步到达后强推一次** —— 切歌那次 metadata 必定还没歌词，取 `controller.getMetadata()` 实时数据，
   注入后 `setMetadata()` 强推。

细节见 [SKILL.md](SKILL.md) 的「四条工程要点」与 [references/bridge-template.java](references/bridge-template.java)。

## 目录

```
SKILL.md                        完整方法论（决策流、5 个 hook、热路径铁律、验证步骤）
references/
  protocols.md                  两套协议字段表、能力位、manifest 声明、发送时机
  troubleshooting.md            症状 → 根因速查表
  projects.md                   四个历史项目的适配档案
  whitelist-packages.md         10 个实机验证过的包名 + 支持矩阵
  find-hook-points.md           如何定位 metadata 汇聚点 / 歌词加载器
  smali-rules.md                smali 层适配戒律与验证链
  bridge-template.java          最小可用实现类（可直接拷进工程）
scripts/
  check_protocol_fields.sh      字段级验证（改完必跑）
  find_metadata_exits.sh        扫出所有 setMetadata 调用点
  locate_lyrics_loader.sh       定位歌词加载器，判断是否全绑 UI
```

## 快速上手

```bash
git clone https://github.com/7tattoo/vivo-car-atomic-lyrics.git
cd vivo-car-atomic-lyrics

# 1. 先读 SKILL.md 的决策流，确定目标包名
# 2. 用 find_metadata_exits.sh 找出你的 metadata 汇聚点
bash scripts/find_metadata_exits.sh your-app.apk

# 3. 按 bridge-template.java 实现桥接类，接入 5 个 hook
# 4. 出包后做字段级验证（这一步别跳）
bash scripts/check_protocol_fields.sh your-signed.apk
```

脚本依赖：`unzip`、`strings`、`aapt2`（Android SDK build-tools）、`apktool`。
`aapt2` 用 `AAPT2=/path/to/aapt2` 指定，`apktool` 用 `APKTOOL_JAR=/path/to/apktool.jar` 指定，默认取 PATH / `~/.local/share/apktool/apktool.jar`。

## 作为 Claude Skill 使用

本仓库同时是一个 skill 包。把整个目录放进 skills 目录即可被 Agent 自动加载：

```bash
cp -r vivo-car-atomic-lyrics ~/.claude/skills/     # 或你的 skill 目录
```

`SKILL.md` 的 frontmatter（`name` / `description` / `version`）会被识别，触发词包括
「joviincar 车载歌词」「车联投屏歌词」「原子通知歌词」「ucar 歌词」「vivomusicmix」等。

## 免责声明

本项目只包含协议研究与适配方法，**不包含任何 App 的二进制、反编译产物或厂商私有资源**。
字段名、事件名均来自公开可观测的运行时行为。请自行承担修改第三方 App 的合规风险，
遵守相关软件许可协议与当地法律法规。

## License

MIT — 见 [LICENSE](LICENSE)。
