---
name: vivo-car-atomic-lyrics
description: 把任意 Android 音乐 / 音频 App 适配到 vivo 车机的两个歌词显示位：JoviInCar 车联投屏主页滚动歌词（ucar 通道）与原子随身听 / 原子通知歌词（vivomusicmix 通道）。沉淀 hachimi、TattooMusic、md3Music（Apple Music 包名）、NeriPlayer 四项目的实车适配方法。触发词：joviincar 车载歌词、joviincar 歌词适配、车机滚动歌词、车联投屏歌词、原子通知歌词、原子随身听歌词、车载歌词不滚动、切歌变单行、车机单行歌词、vivo 车机歌词、ucar 歌词、vivomusicmix、LYRICS_WHOLE、lrc_change、support_event、卡片封面纯色、原子通知没封面、车机卡片封面、artUri。当用户说「把 xxx 适配 joviincar 车载歌词」或「给 xxx 加原子通知歌词」时使用。⚠️ 强制前置：动手前必须先向用户确认目标包名（要原子通知歌词时只能在 Apple Music / Spotify 二选一），禁止自行指定包名、禁止先干活后补问。
version: 1.2.0
---
# vivo 车机滚动歌词 + 原子随身听适配 Skill

把任意 Android 音乐 App 适配到 vivo 车机的两个歌词显示位：

1. **车联投屏 / JoviInCar 车机主页滚动歌词**（ucar 通道）
2. **原子随身听 / 原子通知歌词**（vivomusicmix 通道）

来源：hachimi、TattooMusic、md3Music（Apple Music 包名）、NeriPlayer、kgka_Music_hl 五个项目的实车适配，汇总自 `VIVO_CAR_LYRICS_GUIDE.md` 与 `APK_UPDATE_GUIDE.zh-CN.md.txt`。文档里所有「绝不能做」都是踩过的坑。

## ⛔ 第 0 步：包名闸门（强制，先停下）

**这是唯一允许「先问再做」的地方，也是绝不能跳的一步。**

在动手改任何代码、反编译、建工程、跑脚本之前，**必须先向用户确认目标包名**，拿到用户明确回答后才能继续。

### 硬性规则

1. **禁止自行指定包名。** 不许因为「Spotify 支持两个通道」「Apple Music 文档写得最全」「看起来更通用」就替用户选。
   用户没说包名 = 你没有授权 = 不能开工。
2. **禁止先干活后补问。** 不许「我先把桥接写好在 Spotify 包名上，等下再问」。
   包名决定 `applicationId`、manifest、native `.so` 绑定、交付文件名，改一次等于返工一次。
3. **按需求分支提问，一次问清**：
   - 用户只要 **JoviInCar 车机主页滚动歌词** → 从 11 个实机验证包名里让他选一个。
   - 用户要 **原子通知 / 原子随身听歌词**（不论是否同时要 JoviInCar）→ **只能在 2 个里选**：
     `com.apple.android.music`（Apple Music）、`com.spotify.music`（Spotify）。
     此时把这两个选项摆出来让用户挑，**不要默认 Spotify**。
4. **用户答「随便 / 你定」也不行。** 这是需要用户拍板的决策（影响与其它 App 的包名冲突、是否覆盖已有安装）。
   把选项和各自代价（尤其 `com.spotify.music` 与 SamsungMusicRC 撞包名）说清楚，让他明确点一个。
5. **答案拿到后回读一遍**：「目标包名 `xxx`，用于 JoviInCar 滚动歌词 + 原子通知歌词，确认？」用户点头再动手。
6. 用户若要求白名单外的包名 → 说明未实机验证的风险，让他确认后再用。

### 交付自检

交付前检查：**成品 APK 的包名 == 用户确认的包名**。不一致就是本步失败，不要交付。

### 标准问法（照抄即可）

> 适配 vivo 车机歌词需要先确定目标包名，它会写进 `applicationId`，后续不好改：
>
> **你只要 JoviInCar 车机主页滚动歌词，还是同时要原子通知 / 原子随身听歌词？**
> - 只要 JoviInCar → 下面 11 个任选（推荐 …… 按你的机型/已有安装来）
> - 要原子通知 → 只能二选一：`com.apple.android.music`（Apple Music）/ `com.spotify.music`（Spotify）
>
> 注意 `com.spotify.music` 与 SamsungMusicRC 同包名，同机装不了两个。

完整包名清单与支持矩阵见 [references/whitelist-packages.md](references/whitelist-packages.md)。

---

## 包名确认之后：执行流程

拿到用户确认的包名，才进入下面这些步骤（顺序不要颠倒）：

1. 读 [references/projects.md](references/projects.md) 找同类项目的适配档案
2. 用 `scripts/find_metadata_exits.sh` 定位 metadata 汇聚点
3. 按 [references/bridge-template.java](references/bridge-template.java) 实现桥接类，接入 5 个 hook
4. 出包后用 `scripts/check_protocol_fields.sh` 做字段级验证
5. 交付前自检包名是否 == 用户确认的包名

## 一句话核心认知

网上搜「joviincar 歌词适配版」是单行方案。真正能出滚动多行的参照实现是 **酷我音乐 12.0.8.0**（不是车机版 7.6.6.21）。反编译它的 `ViVoCarLinkMediaSessionBridge`，写车载歌词只有一行有效代码：

```java
builder.putString("ucar.media.metadata.LYRICS_WHOLE", lrc);
```

车机自己按 `PlaybackState` 的进度滚动歌词。App 的职责只是把**整段 LRC** 交给车机，**不需要、也不应该**推送「当前是第几行」。两套协议完整字段表见 [references/protocols.md](references/protocols.md)。

## 四条工程要点（协议对了还不够）

字段写对只是第一步。导致「时好时坏」「只有第一次生效」的，全是这四个工程问题，缺任何一个都会概率性单行。

1. **在 metadata 的唯一出口注入**：播放器有多条 metadata 推送路径（通知刷新、播放状态、队列变化、切歌、独立播放器）。只 hook 切歌那条，后台通知栏刷新会推一份不含歌词的 metadata 覆盖车机已有的。要在 `MediaSessionCompat.setMetadata()` 的实现汇聚点注入。
2. **主动请求歌词加载**（最致命）：多数播放器歌词加载绑定 UI（只有打开全屏播放器才加载）。vivo 车机只发 `ucar.*` / `vivomusicmix.*`，从不发厂商私有请求。所以后台切歌时没有任何代码去加载歌词 → 单行。切歌时要自己调用歌词加载器。
3. **抓住 MediaSession 引用**：歌词异步到达后要补推 metadata，必须有 session 引用。只在某条推送路径赋值，后台切歌时会是 null。要在要点 1 那个统一出口抓引用。
4. **歌词异步到达后强推一次**：切歌那次 metadata 必定还没歌词。取 `controller.getMetadata()` 实时数据，注入后 `setMetadata()` 强推，不加多余条件。

## 热路径三条铁律

要点 1 的出口是超热路径（每次通知栏刷新都调用，且先于异步歌词加载完成）。曾付过「首曲无封面 + 破音」的代价。

1. **没有整段歌词 → 原样返回，绝不写负状态**。`LYRICS_STATUS = 1/2` 对车机语义是「本曲确认无歌词」。异步加载时通知栏刷新先于歌词就绪触发推送，此时写负状态车机开机就收到「无歌词」判定，永久退回单行。
2. **零 side effect**：不写全局 metadata 缓存（会让精简通知快照覆盖完整切歌快照 → 无封面）；不检查歌曲是否变化（songKey 抖动）；不写日志落盘（FileOutputStream/mkdirs 在首曲初始化跟音频输出抢主线程 → 破音）。
3. **无歌词窗口零开销**：无歌词时连 `new MediaMetadata.Builder(src)` 都别进（会拷贝封面 Bitmap）。已带相同歌词也跳过拷贝。

## 标准 5 个 Hook

- A. `MediaSessionCompat.setMetadata` 汇聚点 → 包一层 `setMetadata(CarLyricsBridge.applyRaw(raw, session))`
- B. 切歌回调 → `CarLyricsBridge.onTrackChanged(...)`（清旧歌词 + 主动请求）
- C. 歌词加载回调 → `CarLyricsBridge.seedLrc(audioId, lrc)` + `onLrcReady()`
- D. `Application.onCreate` → `CarLyricsBridge.init(getApplicationContext())`
- E. manifest：`MediaBrowserService` 的 intent-filter 追加 `com.vivo.musicwidgetmix.support.service`（仅原子随身听需要）

完整最小实现类见 [references/bridge-template.java](references/bridge-template.java)。

## 绝不能做的四件事

- **写 `ucar.media.metadata.LYRICS_LINE`**：单行协议信号，车机收到就切单行卡片并忽略 `LYRICS_WHOLE`。
- **用 `music.media.extras.*` 通道**（LYRIC / LYRIC_IS_ALLOWED / NOTICE_CAR）：单行通道，500ms 定时器推 extras 每次都会把车机卡片压回单行，表现为「切歌瞬间多行，十几秒变回单行」。
- **没有歌词时写负状态**（`LYRICS_WHOLE=""` + `LYRICS_STATUS=1/2`）：永久退回单行。
- **推空 Bundle 的 `setExtras()`**：会清空车机已收到的 extras，已显示的歌词突然消失。

## 封面也是协议的一部分（纯色封面）

歌词通了不等于封面通了：封面是**另一条链**（卡片进程按 URL 自己下图片），任何一环坏了都表现为**纯色封面**。完整 8 条坑、归一化函数、诊断日志分层见 [references/card-cover.md](references/card-cover.md)，最小清单：

1. **只投 http(s)**：`content://` / `file://` 卡片侧拉不到，宁可返回 null。
2. **替换字面量占位符**：酷狗 `stdmusic/{size}/...` 原样请求 404，而这个 404 **不出现在我们 App 的日志里**（是卡片进程在拉）。
3. **默认 https，但要按实测验**：NeriPlayer 上只吃 http，kgka 上 http 被拦必须 https —— 随组件版本变，两边都试过再定论。
4. **投小图**：480px 级别；1~2MB 原图会让卡片下载超时 → 纯色（「部分歌曲纯色」最常见成因）。
5. **封面可能来自异步补取**：酷狗搜索接口不给 `imgurl`，要按专辑接口补；投递必须用补取结果，不能直接读原始字段。
6. **负缓存要有 TTL**：永久不重试 = 一次网络抖动毁掉整场会话的封面。
7. **空串 ≠ 清空**：歌词刷新时非空才覆盖，真正的清空只发生在换曲。
8. **协议字段放进 `MediaItem.extras`**：`audio_service` 每次更新整份替换 metadata；`support_event = 31` 要从**首个** MediaItem 就带上。

## 字段级验证（必做）

改完一定要解包成品包再 grep 一遍。曾因跳过这步漏掉第二条独立注入路径（那个 App 除主桥接类外还有个辅助类同样在写 `LYRICS_LINE`），白发一个版本。

```bash
unzip -p "$apk" 'classes*.dex' > /tmp/all.dex
for k in ucar.media.metadata.LYRICS_WHOLE ucar.media.metadata.LYRICS_LINE \
         music.media.extras.NOTICE_CAR com.vivo.musicwidgetmix.support.service; do
  printf "%-45s %s\n" "$k" "$(strings /tmp/all.dex | grep -qF "$k" && echo 存在 || echo 无)"
done
```

三个坑：dex 是二进制 grep 要加 `-a`；**`LYRICS_LINE` 出现在 dex ≠ 被使用**（酷我 12.0.8.0 定义了但从不 putString，属合法例外，要用 jadx 确认没有 `putString(...LYRICS_LINE...)`）；manifest 里的 action 必须用 `aapt2 dump xmltree` 解析（二进制 XML，strings 读不到），且整份 manifest 只能出现一次。

直接跑现成脚本：`bash .../scripts/check_protocol_fields.sh <apk>`

## 关键坑（跨项目血泪）

- 「间歇性/莫名不通」不等于鉴权问题。先看日志：报错 5ms 内本地抛、message 为 null → 主线程网络或本地异常。
- **vivo 官方拼写错误必须照抄**：`vivomusicmix.meida.extra.key.action`（不是 media）、`extra.key.meidia_id`（不是 media_id）。写成正确拼写反而收不到。
- **能力位 `support_event`**：`31 = 7|8|16`（7 基础播控、8 歌词、16 进度条/seek）。缺 `8` 位组件不显示歌词区。合作控制器原样读取不自己补位，缺 `16` 位就永远 `--:--`。
- **`lrc_change` 是事件**：切歌发一次 + 每 25s 重发一次兜底，不需要高频推。判断写成 `elapsed < 25s 才发` 等于永远不发。
- **Flutter 播放页空态**：没有当前歌曲时不要返回 `Scaffold(body: SizedBox.shrink())` —— 深色主题下就是整屏纯黑、没有返回入口，只能杀进程。升级安装后数据目录为空（队列\/prefs 全空）最容易踩到。空态必须可见、可退。
- **`MediaQuery.size` 为 0×0 ≠ 极小窗口**：冷启动首帧 metrics 还没上报，此时 size 是 0×0（`dpr=1.00` 就是线索），布局约束其实已经是真实窗口——不要因此进「极小窗兜底页」；而兜底页本身也必须能看见、能退出。
- **smali 戒律**：`static` 方法别用 `p0`（VerifyError）；同一寄存器别先 `const-string` 后 `const-wide`；`static final` 字段多线程读写要改 `static volatile`。详见 [references/smali-rules.md](references/smali-rules.md)。

## 症状速查

常见症状与根因的对照表、以及四个历史项目（hachimi / TattooMusic / md3Music / NeriPlayer）的适配档案，见 [references/troubleshooting.md](references/troubleshooting.md) 和 [references/projects.md](references/projects.md)。

## 打包与签名

```bash
./gradlew :app:assembleRelease --no-daemon --no-configuration-cache -x lint
```

先 commit 再构建（若 versionCode 取 `git rev-list --count HEAD`，未提交的改动不计入）。流程：`zipalign -p -f 4 in.apk out.apk` → `apksigner sign --ks <your.jks> out.apk` → `apksigner verify --print-certs out.apk`。`apksigner` / `zipalign` 在 `$ANDROID_HOME/build-tools/<版本>/` 下。

> 用你自己的 keystore 签名，不要把 keystore 和口令写进仓库。

## 参考文件

- [references/protocols.md](references/protocols.md) 两套协议字段表、能力位、manifest 声明、发送时机
- [references/troubleshooting.md](references/troubleshooting.md) 症状→根因速查表
- [references/card-cover.md](references/card-cover.md) 卡片封面（纯色）8 条坑 + 归一化函数 + 诊断分层
- [references/projects.md](references/projects.md) 五个项目的适配档案
- [references/whitelist-packages.md](references/whitelist-packages.md) 11 个包名白名单 + 支持矩阵
- [references/find-hook-points.md](references/find-hook-points.md) 如何定位 metadata 汇聚点 / 歌词加载器
- [references/smali-rules.md](references/smali-rules.md) smali 层适配戒律与验证链
- [references/bridge-template.java](references/bridge-template.java) 最小可用实现类
- [scripts/](scripts/) 三个验证/定位脚本