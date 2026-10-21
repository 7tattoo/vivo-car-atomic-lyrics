#!/bin/bash
# check_protocol_fields.sh <apk...>
# 字段级验证：检查 APK 里是否包含正确的协议字段、是否残留单行信号。
# 必做——曾跳过这步漏掉第二条独立注入路径，白发一个版本。
#
# 用法: bash check_protocol_fields.sh your.apk [能用的.apk 不能用的.apk]
# 强烈建议同时传一个"能用的.apk"和一个"不能用的.apk"做横向对比，
# 比读代码逻辑快得多（参考 find-hook-points.md Step 6）。
#
# 输出: 每个 APK 一行，逐个字段标记 OK/MISS/WARN

set -u

# 期望出现的关键字段
GOOD_KEYS=(
  "ucar.media.metadata.LYRICS_WHOLE"
  "ucar.media.metadata.LYRICS_STATUS"
  "vivomusicmix.media.metadata.support_event"
  "vivomusicmix.meida.extra.key.action"
  "vivomusicmix.extra.key.lyric"
  "vivomusicmix.extra.key.meidia_id"
)

# 单行信号字段。⚠️ 注意：酷我音乐 12.0.8.0 在 CarLinkMediaMetadata
# 常量表里 *定义* 了 LYRICS_LINE 但 *从不 put*，所以"存在于 dex"不等于"在使用"。
# 这里只做 WARN，真正的判定见脚本末尾的 jadx 语义检查。
BAD_KEYS=(
  "ucar.media.metadata.LYRICS_LINE"
  "music.media.extras.LYRIC"
  "music.media.extras.LYRIC_IS_ALLOWED"
  "music.media.extras.NOTICE_CAR"
)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

has_key() { # $1=dexdir $2=key
  grep -rqaF -- "$2" "$1" 2>/dev/null
}

# manifest 里的原子随身听 action（必须存在且只出现一次）
manifest_action_count() { # $1=apk
  "${AAPT2:-aapt2}" dump xmltree "$1" --file AndroidManifest.xml 2>/dev/null | \
    grep -c "com.vivo.musicwidgetmix.support.service"
}

for apk in "$@"; do
  echo "=== $apk ==="
  [ -f "$apk" ] || { echo "  (文件不存在)"; continue; }

  d="$WORK/dex"
  mkdir -p "$d"
  unzip -o -q "$apk" 'classes*.dex' -d "$d" 2>/dev/null || true

  echo "  -- 应存在（协议字段）--"
  for k in "${GOOD_KEYS[@]}"; do
    if has_key "$d" "$k"; then
      printf "  OK   %-45s %s\n" "$k" "存在"
    else
      printf "  MISS %-45s %s\n" "$k" "无"
    fi
  done

  echo "  -- 不应存在（单行信号，仅警告）--"
  for k in "${BAD_KEYS[@]}"; do
    if has_key "$d" "$k"; then
      printf "  WARN %-45s %s\n" "$k" "存在(需确认是否仅常量定义未使用)"
    else
      printf "  OK   %-45s %s\n" "$k" "无"
    fi
  done

  echo "  -- manifest --"
  mf=$(manifest_action_count "$apk")
  echo "  com.vivo.musicwidgetmix.support.service 出现次数: ${mf} (应为 1)"
  [ "${mf:-0}" = "1" ] && echo "  OK   action 已正确声明" || echo "  MISS action 未声明或数量异常"

  rm -rf "$d"
done

echo
echo ">>> 期望结果：协议字段全部 存在，manifest action = 1。"
echo ">>> 单行信号若 WARN，用 jadx 反编译确认是否真的 putString（酷我只定义不 put，是合法例外）："
echo "    jadx -d out --no-res --no-imports -j 2 <apk>"
echo "    grep -rn 'LYRICS_LINE\\|NOTICE_CAR\\|LYRIC_IS_ALLOWED' out/sources/ | grep -i 'put\\|set'"