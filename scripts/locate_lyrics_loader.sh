#!/bin/bash
# locate_lyrics_loader.sh <apk|smali_dir>
# 找出目标 App 的歌词加载器入口，并判断其调用点是否全绑 UI（要点二）。
#
# 核心认知：vivo 车机只会发 ucar.*/vivomusicmix.*，永远不会发厂商私有 REQUEST_LYRIC。
# 如果歌词加载全绑 UI，车机后台切歌时没有任何代码去加载歌词 → 缓存未命中 → 单行。

set -u

SRC="$1"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [ -f "$SRC" ]; then
  echo ">>> 反编译 $SRC ..."
  java -jar "${APKTOOL_JAR:-$HOME/.local/share/apktool/apktool.jar}" d -f -o "$WORK/smali" --no-res "$SRC" >/dev/null 2>&1 || true
  SMALI="$WORK/smali"
  [ -d "$SMALI" ] || SMALI=$(find "$WORK" -type d -name smali 2>/dev/null | head -1)
else
  SMALI="$SRC"
fi

[ -d "$SMALI" ] || { echo "找不到 smali 目录: $SMALI"; exit 1; }
echo ">>> smali 目录: $SMALI"
echo

echo "=== 1. 含 lyrics 的类（候选歌词加载器）==="
grep -rli "lyric" "$SMALI" --include=*.smali 2>/dev/null | head -20 | sed 's|.*/smali/|smali/|'

echo
echo "=== 2. 疑似 requestLyric / 歌词加载方法定义 ==="
grep -rhn "requestLyric\|requestLyrics\|loadLyric\|fetchLyric\|LyricsLoader" \
  "$SMALI" --include=*.smali 2>/dev/null | \
  grep -i "method\|->.*Lyric" | sort -u | head -30

echo
echo "=== 3. 该加载方法的全部调用点（判断是否绑 UI）==="
# 自动猜测常见加载方法名并列出调用点
for m in requestLyric requestLyrics loadLyric fetchLyric; do
  hits=$(grep -rn "->$m(" "$SMALI" --include=*.smali 2>/dev/null | wc -l)
  [ "$hits" -gt 0 ] && echo "  $m: $hits 处调用"
done

echo
echo ">>> 判断：如果所有调用点都在 UI 类（activity/fragment/dialog/歌词页）里，
  必须自己加一条后台请求路径（在切歌回调里主动调歌词加载器）。
  否则表现就是：进过播放页后切'下一首'多行，再往下切单行（UI 分页只预取相邻曲目）。"