package eu.kanade.tachiyomi.extension.zh.copymanga.api.dto;

import java.util.Map;
import kotlin.Deprecated;
import kotlin.DeprecationLevel;
import kotlin.Metadata;
import kotlin.ReplaceWith;
import kotlin.jvm.JvmStatic;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlinx.serialization.KSerializer;
import kotlinx.serialization.SerialName;
import kotlinx.serialization.Serializable;
import kotlinx.serialization.descriptors.SerialDescriptor;
import kotlinx.serialization.encoding.CompositeEncoder;
import kotlinx.serialization.internal.LinkedHashMapSerializer;
import kotlinx.serialization.internal.PluginExceptionsKt;
import kotlinx.serialization.internal.SerializationConstructorMarker;
import kotlinx.serialization.internal.StringSerializer;

/* JADX INFO: compiled from: ComicDetailResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000L\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000b\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010$\n\u0002\u0010\u000e\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u001d\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 72\u00020\u0001:\u000267Bs\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\b\b\u0001\u0010\u0004\u001a\u00020\u0005\u0012\b\b\u0001\u0010\u0006\u001a\u00020\u0005\u0012\b\b\u0001\u0010\u0007\u001a\u00020\u0005\u0012\b\b\u0001\u0010\b\u001a\u00020\u0005\u0012\b\b\u0001\u0010\t\u001a\u00020\u0005\u0012\b\u0010\n\u001a\u0004\u0018\u00010\u000b\u0012\u0006\u0010\f\u001a\u00020\u0003\u0012\u0014\u0010\r\u001a\u0010\u0012\u0004\u0012\u00020\u000f\u0012\u0004\u0012\u00020\u0010\u0018\u00010\u000e\u0012\b\u0010\u0011\u001a\u0004\u0018\u00010\u0012¢\u0006\u0002\u0010\u0013BS\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0005\u0012\u0006\u0010\u0007\u001a\u00020\u0005\u0012\u0006\u0010\b\u001a\u00020\u0005\u0012\u0006\u0010\t\u001a\u00020\u0005\u0012\u0006\u0010\n\u001a\u00020\u000b\u0012\u0006\u0010\f\u001a\u00020\u0003\u0012\u0012\u0010\r\u001a\u000e\u0012\u0004\u0012\u00020\u000f\u0012\u0004\u0012\u00020\u00100\u000e¢\u0006\u0002\u0010\u0014J\t\u0010\"\u001a\u00020\u0005HÆ\u0003J\t\u0010#\u001a\u00020\u0005HÆ\u0003J\t\u0010$\u001a\u00020\u0005HÆ\u0003J\t\u0010%\u001a\u00020\u0005HÆ\u0003J\t\u0010&\u001a\u00020\u0005HÆ\u0003J\t\u0010'\u001a\u00020\u000bHÆ\u0003J\t\u0010(\u001a\u00020\u0003HÆ\u0003J\u0015\u0010)\u001a\u000e\u0012\u0004\u0012\u00020\u000f\u0012\u0004\u0012\u00020\u00100\u000eHÆ\u0003Je\u0010*\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00052\b\b\u0002\u0010\u0006\u001a\u00020\u00052\b\b\u0002\u0010\u0007\u001a\u00020\u00052\b\b\u0002\u0010\b\u001a\u00020\u00052\b\b\u0002\u0010\t\u001a\u00020\u00052\b\b\u0002\u0010\n\u001a\u00020\u000b2\b\b\u0002\u0010\f\u001a\u00020\u00032\u0014\b\u0002\u0010\r\u001a\u000e\u0012\u0004\u0012\u00020\u000f\u0012\u0004\u0012\u00020\u00100\u000eHÆ\u0001J\u0013\u0010+\u001a\u00020\u00052\b\u0010,\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010-\u001a\u00020\u0003HÖ\u0001J\t\u0010.\u001a\u00020\u000fHÖ\u0001J!\u0010/\u001a\u0002002\u0006\u00101\u001a\u00020\u00002\u0006\u00102\u001a\u0002032\u0006\u00104\u001a\u000205HÇ\u0001R\u0011\u0010\n\u001a\u00020\u000b¢\u0006\b\n\u0000\u001a\u0004\b\u0015\u0010\u0016R\u001d\u0010\r\u001a\u000e\u0012\u0004\u0012\u00020\u000f\u0012\u0004\u0012\u00020\u00100\u000e¢\u0006\b\n\u0000\u001a\u0004\b\u0017\u0010\u0018R\u001c\u0010\u0004\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0019\u0010\u001a\u001a\u0004\b\u0004\u0010\u001bR\u001c\u0010\u0006\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001c\u0010\u001a\u001a\u0004\b\u0006\u0010\u001bR\u001c\u0010\u0007\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001d\u0010\u001a\u001a\u0004\b\u0007\u0010\u001bR\u001c\u0010\b\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001e\u0010\u001a\u001a\u0004\b\b\u0010\u001bR\u001c\u0010\t\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001f\u0010\u001a\u001a\u0004\b\t\u0010\u001bR\u0011\u0010\f\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b \u0010!¨\u00068"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicDetailResult;", "", "seen1", "", "isBanned", "", "isLock", "isLogin", "isMobileBind", "isVip", "comic", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicDetail;", "popular", "groups", "", "", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/GroupInfo;", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(IZZZZZLeu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicDetail;ILjava/util/Map;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(ZZZZZLeu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicDetail;ILjava/util/Map;)V", "getComic", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicDetail;", "getGroups", "()Ljava/util/Map;", "isBanned$annotations", "()V", "()Z", "isLock$annotations", "isLogin$annotations", "isMobileBind$annotations", "isVip$annotations", "getPopular", "()I", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "copy", "equals", "other", "hashCode", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
public final /* data */ class ComicDetailResult {

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final ComicDetail comic;
    private final Map<String, GroupInfo> groups;
    private final boolean isBanned;
    private final boolean isLock;
    private final boolean isLogin;
    private final boolean isMobileBind;
    private final boolean isVip;
    private final int popular;

    @SerialName("is_banned")
    public static /* synthetic */ void isBanned$annotations() {
    }

    @SerialName("is_lock")
    public static /* synthetic */ void isLock$annotations() {
    }

    @SerialName("is_login")
    public static /* synthetic */ void isLogin$annotations() {
    }

    @SerialName("is_mobile_bind")
    public static /* synthetic */ void isMobileBind$annotations() {
    }

    @SerialName("is_vip")
    public static /* synthetic */ void isVip$annotations() {
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final boolean getIsBanned() {
        return this.isBanned;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final boolean getIsLock() {
        return this.isLock;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final boolean getIsLogin() {
        return this.isLogin;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final boolean getIsMobileBind() {
        return this.isMobileBind;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final boolean getIsVip() {
        return this.isVip;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final ComicDetail getComic() {
        return this.comic;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final int getPopular() {
        return this.popular;
    }

    public final Map<String, GroupInfo> component8() {
        return this.groups;
    }

    public final ComicDetailResult copy(boolean isBanned, boolean isLock, boolean isLogin, boolean isMobileBind, boolean isVip, ComicDetail comic, int popular, Map<String, GroupInfo> groups) {
        Intrinsics.checkNotNullParameter(comic, "comic");
        Intrinsics.checkNotNullParameter(groups, "groups");
        return new ComicDetailResult(isBanned, isLock, isLogin, isMobileBind, isVip, comic, popular, groups);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ComicDetailResult)) {
            return false;
        }
        ComicDetailResult comicDetailResult = (ComicDetailResult) other;
        return this.isBanned == comicDetailResult.isBanned && this.isLock == comicDetailResult.isLock && this.isLogin == comicDetailResult.isLogin && this.isMobileBind == comicDetailResult.isMobileBind && this.isVip == comicDetailResult.isVip && Intrinsics.areEqual(this.comic, comicDetailResult.comic) && this.popular == comicDetailResult.popular && Intrinsics.areEqual(this.groups, comicDetailResult.groups);
    }

    /* JADX WARN: Multi-variable type inference failed */
    /* JADX WARN: Type inference failed for: r0v1, types: [int] */
    /* JADX WARN: Type inference failed for: r0v16 */
    /* JADX WARN: Type inference failed for: r0v17 */
    /* JADX WARN: Type inference failed for: r1v0 */
    /* JADX WARN: Type inference failed for: r1v1, types: [int] */
    /* JADX WARN: Type inference failed for: r1v7 */
    /* JADX WARN: Type inference failed for: r2v1, types: [int] */
    /* JADX WARN: Type inference failed for: r2v10 */
    /* JADX WARN: Type inference failed for: r2v11 */
    /* JADX WARN: Type inference failed for: r2v12 */
    /* JADX WARN: Type inference failed for: r2v3, types: [int] */
    /* JADX WARN: Type inference failed for: r2v5, types: [int] */
    /* JADX WARN: Type inference failed for: r2v7 */
    /* JADX WARN: Type inference failed for: r2v8 */
    /* JADX WARN: Type inference failed for: r2v9 */
    public int hashCode() {
        boolean z = this.isBanned;
        ?? r0 = z;
        if (z) {
            r0 = 1;
        }
        int i = r0 * 31;
        boolean z2 = this.isLock;
        ?? r2 = z2;
        if (z2) {
            r2 = 1;
        }
        int i2 = (i + r2) * 31;
        boolean z3 = this.isLogin;
        ?? r22 = z3;
        if (z3) {
            r22 = 1;
        }
        int i3 = (i2 + r22) * 31;
        boolean z4 = this.isMobileBind;
        ?? r23 = z4;
        if (z4) {
            r23 = 1;
        }
        int i4 = (i3 + r23) * 31;
        boolean z5 = this.isVip;
        return ((((((i4 + (z5 ? 1 : z5)) * 31) + this.comic.hashCode()) * 31) + this.popular) * 31) + this.groups.hashCode();
    }

    public String toString() {
        return "ComicDetailResult(isBanned=" + this.isBanned + ", isLock=" + this.isLock + ", isLogin=" + this.isLogin + ", isMobileBind=" + this.isMobileBind + ", isVip=" + this.isVip + ", comic=" + this.comic + ", popular=" + this.popular + ", groups=" + this.groups + ')';
    }

    /* JADX INFO: compiled from: ComicDetailResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicDetailResult$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicDetailResult;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<ComicDetailResult> serializer() {
            return ComicDetailResult$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ ComicDetailResult(int i, @SerialName("is_banned") boolean z, @SerialName("is_lock") boolean z2, @SerialName("is_login") boolean z3, @SerialName("is_mobile_bind") boolean z4, @SerialName("is_vip") boolean z5, ComicDetail comicDetail, int i2, Map map, SerializationConstructorMarker serializationConstructorMarker) {
        if (254 != (i & 254)) {
            PluginExceptionsKt.throwMissingFieldException(i, 254, ComicDetailResult$$serializer.INSTANCE.getDescriptor());
        }
        if ((i & 1) == 0) {
            this.isBanned = false;
        } else {
            this.isBanned = z;
        }
        this.isLock = z2;
        this.isLogin = z3;
        this.isMobileBind = z4;
        this.isVip = z5;
        this.comic = comicDetail;
        this.popular = i2;
        this.groups = map;
    }

    public ComicDetailResult(boolean z, boolean z2, boolean z3, boolean z4, boolean z5, ComicDetail comicDetail, int i, Map<String, GroupInfo> map) {
        Intrinsics.checkNotNullParameter(comicDetail, "comic");
        Intrinsics.checkNotNullParameter(map, "groups");
        this.isBanned = z;
        this.isLock = z2;
        this.isLogin = z3;
        this.isMobileBind = z4;
        this.isVip = z5;
        this.comic = comicDetail;
        this.popular = i;
        this.groups = map;
    }

    @JvmStatic
    public static final void write$Self(ComicDetailResult self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        if (output.shouldEncodeElementDefault(serialDesc, 0) || self.isBanned) {
            output.encodeBooleanElement(serialDesc, 0, self.isBanned);
        }
        output.encodeBooleanElement(serialDesc, 1, self.isLock);
        output.encodeBooleanElement(serialDesc, 2, self.isLogin);
        output.encodeBooleanElement(serialDesc, 3, self.isMobileBind);
        output.encodeBooleanElement(serialDesc, 4, self.isVip);
        output.encodeSerializableElement(serialDesc, 5, ComicDetail$$serializer.INSTANCE, self.comic);
        output.encodeIntElement(serialDesc, 6, self.popular);
        output.encodeSerializableElement(serialDesc, 7, new LinkedHashMapSerializer(StringSerializer.INSTANCE, GroupInfo$$serializer.INSTANCE), self.groups);
    }

    public /* synthetic */ ComicDetailResult(boolean z, boolean z2, boolean z3, boolean z4, boolean z5, ComicDetail comicDetail, int i, Map map, int i2, DefaultConstructorMarker defaultConstructorMarker) {
        this((i2 & 1) != 0 ? false : z, z2, z3, z4, z5, comicDetail, i, map);
    }

    public final boolean isBanned() {
        return this.isBanned;
    }

    public final boolean isLock() {
        return this.isLock;
    }

    public final boolean isLogin() {
        return this.isLogin;
    }

    public final boolean isMobileBind() {
        return this.isMobileBind;
    }

    public final boolean isVip() {
        return this.isVip;
    }

    public final ComicDetail getComic() {
        return this.comic;
    }

    public final int getPopular() {
        return this.popular;
    }

    public final Map<String, GroupInfo> getGroups() {
        return this.groups;
    }
}
