#!/bin/bash
# find_metadata_exits.sh <apk|smali_dir>
# 找出目标 App 的所有 MediaSession metadata 推送路径，定位唯一汇聚点（要点一）。
#
# 用法:
#   bash find_metadata_exits.sh your.apk          # 自动反编译并扫
#   bash find_metadata_exits.sh ./smali           # 直接扫已反编译的 smali 目录
#
# 输出: 所有 setMetadata 调用点 + MediaSessionCompat 内部实现位置

set -u

SRC="$1"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [ -f "$SRC" ]; then
  echo ">>> 反编译 $SRC ..."
  java -jar "${APKTOOL_JAR:-$HOME/.local/share/apktool/apktool.jar}" d -f -o "$WORK/smali" --no-res "$SRC" >/dev/null 2>&1 || \
    { echo "  apktool 反编译失败（资源阶段失败可忽略，smali 目录可能已生成）"; }
  SMALI="$WORK/smali"
  [ -d "$SMALI" ] || SMALI=$(find "$WORK" -type d -name smali 2>/dev/null | head -1)
else
  SMALI="$SRC"
fi

[ -d "$SMALI" ] || { echo "找不到 smali 目录: $SMALI"; exit 1; }
echo ">>> smali 目录: $SMALI"
echo

echo "=== 1. 所有 MediaSession(Compat).setMetadata 调用点 ==="
grep -rn "MediaSession;->setMetadata\|MediaSessionCompat;->setMetadata" "$SMALI" 2>/dev/null | \
  sed 's|.*smali|smali|' | sort -u

echo
echo "=== 2. MediaSessionCompat 内部实现（汇聚点候选）==="
grep -rn "Landroid/media/session/MediaSession;->setMetadata" \
  "$SMALI" --include=*.smali 2>/dev/null | \
  sed 's|.*smali|smali|' | sort -u

echo
echo "=== 3. setExtras 调用点（原子随身听 lrc_change 出口）==="
grep -rn "MediaSession;->setExtras\|MediaSessionCompat;->setExtras" "$SMALI" 2>/dev/null | \
  sed 's|.*smali|smali|' | sort -u

echo
echo ">>> 提示：把所有 setMetadata 路径列出来，找出唯一汇聚点，在那里注入。
  只 hook 切歌那条，后台通知刷新会推不含歌词的 metadata 覆盖车机上已有的。"