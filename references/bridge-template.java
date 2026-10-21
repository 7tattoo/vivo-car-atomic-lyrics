/*
 * vivo 车机歌词 + 原子随身听 桥接类（最小可用实现，完整版）
 *
 * 挂载点（见 SKILL.md 第 5 节）：
 *   A. MediaSessionCompat 内部 setMetadata 汇聚点  → setMetadata(CarLyricsBridge.applyRaw(raw, session))
 *   B. 切歌回调（拿到 Music/MediaItem 处）          → CarLyricsBridge.onTrackChanged(...)
 *   C. 歌词加载回调                                 → CarLyricsBridge.seedLrc(audioId, lrc); CarLyricsBridge.onLrcReady();
 *   D. Application.onCreate                        → CarLyricsBridge.init(getApplicationContext());
 *
 * 热路径三条铁律：
 *   1. 没有整段歌词 → 原样返回，绝不写负状态
 *   2. 零 side effect（不写缓存 / 不检查歌曲变化 / 不写日志落盘）
 *   3. 无歌词窗口零开销（无歌词时连 Builder 都不进，已带相同歌词跳过拷贝）
 */
public final class CarLyricsBridge {

    private static volatile String  sWholeLrc = "";
    private static volatile long    sTrackId  = -1L;
    private static volatile MediaSession sSession;      // 统一出口抓到的引用（要点三）
    private static volatile MediaSession sCarSession;
    private static volatile long    sLastLrcSentAt;
    private static volatile Context sAppContext;

    // ── 1. metadata 唯一出口的装饰器（超热路径，严守三条铁律） ──
    public static MediaMetadata applyRaw(MediaMetadata src, MediaSession session) {
        // 要点三：抓 session 引用（零开销）
        if (session != null && sSession != session) sSession = session;

        if (src == null) return src;

        String lrc = sWholeLrc;
        if (lrc == null || lrc.isEmpty()) return src;   // 铁律 1 + 3

        try {
            if (lrc.equals(src.getString("ucar.media.metadata.LYRICS_WHOLE")))
                return src;                            // 铁律 3：跳过重复拷贝

            MediaMetadata.Builder b = new MediaMetadata.Builder(src);
            b.putString("ucar.media.metadata.LYRICS_WHOLE", lrc);
            b.putLong("ucar.media.metadata.LYRICS_STATUS", 0L);
            b.putLong("vivomusicmix.media.metadata.support_event", 31L);
            return b.build();
        } catch (Throwable t) {
            return src;                                // 出错原样返回
        }
    }

    // ── 2. 切歌时调用：清旧歌词 + 主动请求新歌词（要点二） ──
    public static void onTrackChanged(long cpAttrs, long audioId) {
        if (sTrackId != audioId) {
            sTrackId  = audioId;
            sWholeLrc = "";
            sLastLrcSentAt = 0L;
        }
        requestLyrics(cpAttrs, audioId);
    }

    private static void requestLyrics(long cpAttrs, long audioId) {
        LyricsLoader loader = LyricsLoaderHolder.INSTANCE;
        if (loader == null) return;
        if (loader.context == null) {
            if (sAppContext == null) return;
            loader.context = sAppContext;              // Context 兜底
        }
        if (sTrackId == audioId && !sWholeLrc.isEmpty()) return;
        loader.requestLyric((int) cpAttrs, audioId, new CarLrcCallback(), null);
    }

    // ── 3. 歌词到达：存入 + 强推（要点四） ──
    static void seedLrc(long audioId, String lrc) {
        if (lrc == null || lrc.isEmpty()) return;
        if (sTrackId != -1L && sTrackId != audioId) return;   // 只接受当前曲目
        sWholeLrc = lrc;
    }

    static void onLrcReady() {
        if (sWholeLrc.isEmpty()) return;
        MediaSession s = (sCarSession != null) ? sCarSession : sSession;
        if (s == null) return;
        try {
            MediaController c = s.getController();
            if (c == null) return;
            MediaMetadata now = c.getMetadata();
            if (now == null) return;
            MediaMetadata withLrc = applyRaw(now, s);
            if (withLrc != null) s.setMetadata(withLrc);
        } catch (Throwable ignored) { }
        pushAtomicExtras(s);
    }

    // ── 4. 原子随身听 lrc_change ──
    static void pushAtomicExtras(MediaSession session) {
        if (session == null || sWholeLrc.isEmpty()) return;
        if (System.currentTimeMillis() - sLastLrcSentAt < 25_000L) return;
        try {
            Bundle b = new Bundle();
            b.putString("vivomusicmix.meida.extra.key.action",
                        "vivomusicmix.extra.lrc_change");
            b.putString("vivomusicmix.extra.key.meidia_id", String.valueOf(sTrackId));
            b.putString("vivomusicmix.extra.key.lyric", sWholeLrc);
            session.setExtras(b);
            sLastLrcSentAt = System.currentTimeMillis();
        } catch (Throwable ignored) { }
    }

    public static void init(Context ctx) { sAppContext = ctx.getApplicationContext(); }

    // 歌词加载回调的样例：把厂商私有 LyricsData 转成标准 LRC
    public static class CarLrcCallback implements LyricsCallback {
        @Override
        public void onLyricsLoaded(long audioId, LyricsData data, Object extras) {
            if (data == null) return;
            // 很多播放器用一个单例哨兵对象表示"本曲无歌词"，必须过滤
            if (data == LyricsData.EMPTY_SENTINEL) return;
            String lrc = LrcBuilder.build(data);   // 从 List<LyricLine> 重建标准 [mm:ss.xx] LRC
            if (lrc == null || lrc.isEmpty()) return;
            seedLrc(audioId, lrc);
            onLrcReady();
        }
    }
}