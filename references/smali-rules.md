# smali 层适配：验证链与戒律

> 用于无源码移植（直接改反编译后的 smali）。源码级项目（Kotlin/Java/Flutter 上层）不需要。

## 1. 三层验证链

### 第一层：汇编是否通过

```bash
rm -rf build
java -jar apktool.jar b . -o out.apk
ls -la build/apk/classes*.dex     # 只要 dex 生成了，语法和寄存器分配就没问题
```

> 在受限环境（如 PRoot 沙箱）里资源打包会失败（aapt2 报 exit 132），**不影响判断** ： 看 dex 有没有生成就够了。

### 第二层：语义是否正确（**关键**）

**apktool 和 d8 都不做 verifier 检查。** 故意写寄存器类型冲突的 smali，两者都能正常产出 dex，装到机器上才闪退。

真正能查出问题的是 **jadx 反编译读语义**：

```bash
jadx -d out --no-res --no-imports -j 2 build/apk/classes.dex 2>&1 | grep -c "^ERROR"
grep -n "JADX ERROR\|Type inference failed\|Multi-variable" out/sources/你的类.java
```

然后**人工读一遍反编译出来的 Java**，确认逻辑符合预期。

### 第三层：hook 是否真的插进去了

**陷阱**：jadx 对大方法会输出 `Method dump skipped, instructions count: 233`，这时 grep 反编译产物**找不到你的 hook**，很容易误判成没插入。正确做法是把编译产物 dex 套一个最小 APK，反汇编回 smali 核对：

```bash
cp build/apk/classes2.dex classes.dex
printf '<?xml version="1.0" encoding="utf-8"?>\n<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="t.t"><application/></manifest>\n' > AndroidManifest.xml
zip -q min.apk classes.dex AndroidManifest.xml
java -jar apktool.jar d min.apk -o out --no-res
grep -n -A6 "你的方法名" out/smali/目标类路径.smali
```

## 2. smali 写法戒律

这些是实际造成过闪退的：

| 错误 | 后果 |
|---|---|
| `static` 无参方法用了 `p0` | `p0` 不存在 → VerifyError → 启动闪退 |
| 同一寄存器先 `const-string` 后 `const-wide` | 类型冲突 → VerifyError |
| `<clinit>` 里 String 常量和 wide 常量共用寄存器 | 同上 |
| `static final` 字段被多线程读写 | 优化后读到旧值 → 改 `static volatile` |
| `invoke-virtual/range` 参数寄存器不连续 | 汇编报错或传参错乱 |

寄存器规划建议：**每个寄存器在一个方法内只承担一种类型**，并在方法头用注释写明分配表：

```smali
# 寄存器: v0=sLrc(String) v1=int scratch v2=String scratch
#         v3=Builder v4=key(String) v5-v6=long  p0=v7 p1=v8
.method public static applyRaw(Landroid/media/MediaMetadata;Landroid/media/session/MediaSession;)Landroid/media/MediaMetadata;
    .registers 9
```

## 3. 其他 smali 项目踩坑（来自小浣熊/AI 项目，可复用）

- **Log.e 要加在"吞异常的 catch"里**：光加在外层 catch 没用（内层先吞）。
- **catchall 包装异常时一定保留原始异常**：否则永远只看到"登录异常"这种废消息。
- **`invoke-super` 参数别漏**：`invoke-super {p0,p1,p2}`，漏 p0 会 VerifyError（verifier rejected class）。
- **删除 smali 代码时注意标签**：删分支时若把跳转标签定义一起删了，会报 "Cannot get the location of a label"，需补回标签定义。