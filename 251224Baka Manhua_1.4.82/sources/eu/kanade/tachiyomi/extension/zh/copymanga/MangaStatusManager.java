package eu.kanade.tachiyomi.extension.zh.copymanga;

import kotlin.Metadata;

/* JADX INFO: compiled from: Constants.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000\u0014\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\u0002\bÆ\u0002\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000e\u0010\u0003\u001a\u00020\u00042\u0006\u0010\u0005\u001a\u00020\u0004¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/MangaStatusManager;", "", "()V", "parseStatus", "", "status", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class MangaStatusManager {
    public static final MangaStatusManager INSTANCE = new MangaStatusManager();

    public final int parseStatus(int status) {
        if (status == 0) {
            return 1;
        }
        return (1 > status || status >= 3) ? 0 : 2;
    }

    private MangaStatusManager() {
    }
}
