package eu.kanade.tachiyomi.extension.zh.copymanga;

import kotlin.Metadata;

/* JADX INFO: compiled from: Constants.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000\u0014\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0006\bÆ\u0002\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002R\u000e\u0010\u0003\u001a\u00020\u0004X\u0082T¢\u0006\u0002\n\u0000R\u000e\u0010\u0005\u001a\u00020\u0004X\u0082T¢\u0006\u0002\n\u0000R\u000e\u0010\u0006\u001a\u00020\u0004X\u0082T¢\u0006\u0002\n\u0000R\u0011\u0010\u0007\u001a\u00020\u0004¢\u0006\b\n\u0000\u001a\u0004\b\b\u0010\t¨\u0006\n"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/PluginCommunityInfo;", "", "()V", "DISCORD_URL", "", "QQ_GROUP", "REPO_URL", "SUMMERY", "getSUMMERY", "()Ljava/lang/String;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class PluginCommunityInfo {
    private static final String DISCORD_URL = "https://discord.gg/kE2VAZk2pd";
    private static final String QQ_GROUP = "516631221";
    private static final String REPO_URL = "https://github.com/LittleSurvival/copymanga-copy20";
    public static final PluginCommunityInfo INSTANCE = new PluginCommunityInfo();
    private static final String SUMMERY = "https://github.com/LittleSurvival/copymanga-copy20\nhttps://discord.gg/kE2VAZk2pd\n516631221(qq)";

    private PluginCommunityInfo() {
    }

    public final String getSUMMERY() {
        return SUMMERY;
    }
}
