package eu.kanade.tachiyomi.extension.zh.copymanga.api.dto;

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
import kotlinx.serialization.internal.PluginExceptionsKt;
import kotlinx.serialization.internal.SerializationConstructorMarker;

/* compiled from: ContentResult.kt */
@Metadata(d1 = {"\u0000H\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000b\n\u0002\b\u0006\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u001c\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 62\u00020\u0001:\u000256Bi\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\b\b\u0001\u0010\u0004\u001a\u00020\u0005\u0012\b\b\u0001\u0010\u0006\u001a\u00020\u0005\u0012\b\b\u0001\u0010\u0007\u001a\u00020\u0005\u0012\b\b\u0001\u0010\b\u001a\u00020\u0005\u0012\b\b\u0001\u0010\t\u001a\u00020\u0005\u0012\b\b\u0001\u0010\n\u001a\u00020\u0005\u0012\b\u0010\u000b\u001a\u0004\u0018\u00010\f\u0012\b\u0010\r\u001a\u0004\u0018\u00010\u000e\u0012\b\u0010\u000f\u001a\u0004\u0018\u00010\u0010¢\u0006\u0002\u0010\u0011BI\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0005\u0012\u0006\u0010\u0007\u001a\u00020\u0005\u0012\u0006\u0010\b\u001a\u00020\u0005\u0012\u0006\u0010\t\u001a\u00020\u0005\u0012\b\b\u0002\u0010\n\u001a\u00020\u0005\u0012\u0006\u0010\u000b\u001a\u00020\f\u0012\u0006\u0010\r\u001a\u00020\u000e¢\u0006\u0002\u0010\u0012J\t\u0010 \u001a\u00020\u0005HÆ\u0003J\t\u0010!\u001a\u00020\u0005HÆ\u0003J\t\u0010\"\u001a\u00020\u0005HÆ\u0003J\t\u0010#\u001a\u00020\u0005HÆ\u0003J\t\u0010$\u001a\u00020\u0005HÆ\u0003J\t\u0010%\u001a\u00020\u0005HÆ\u0003J\t\u0010&\u001a\u00020\fHÆ\u0003J\t\u0010'\u001a\u00020\u000eHÆ\u0003JY\u0010(\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00052\b\b\u0002\u0010\u0006\u001a\u00020\u00052\b\b\u0002\u0010\u0007\u001a\u00020\u00052\b\b\u0002\u0010\b\u001a\u00020\u00052\b\b\u0002\u0010\t\u001a\u00020\u00052\b\b\u0002\u0010\n\u001a\u00020\u00052\b\b\u0002\u0010\u000b\u001a\u00020\f2\b\b\u0002\u0010\r\u001a\u00020\u000eHÆ\u0001J\u0013\u0010)\u001a\u00020\u00052\b\u0010*\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010+\u001a\u00020\u0003HÖ\u0001J\t\u0010,\u001a\u00020-HÖ\u0001J!\u0010.\u001a\u00020/2\u0006\u00100\u001a\u00020\u00002\u0006\u00101\u001a\u0002022\u0006\u00103\u001a\u000204HÇ\u0001R\u0011\u0010\r\u001a\u00020\u000e¢\u0006\b\n\u0000\u001a\u0004\b\u0013\u0010\u0014R\u0011\u0010\u000b\u001a\u00020\f¢\u0006\b\n\u0000\u001a\u0004\b\u0015\u0010\u0016R\u001c\u0010\n\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0017\u0010\u0018\u001a\u0004\b\n\u0010\u0019R\u001c\u0010\u0006\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001a\u0010\u0018\u001a\u0004\b\u0006\u0010\u0019R\u001c\u0010\u0007\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001b\u0010\u0018\u001a\u0004\b\u0007\u0010\u0019R\u001c\u0010\b\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001c\u0010\u0018\u001a\u0004\b\b\u0010\u0019R\u001c\u0010\t\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001d\u0010\u0018\u001a\u0004\b\t\u0010\u0019R\u001c\u0010\u0004\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001e\u0010\u0018\u001a\u0004\b\u001f\u0010\u0019¨\u00067"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ContentResult;", "", "seen1", "", "showApp", "", "isLock", "isLogin", "isMobileBind", "isVip", "isBanned", "comic", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicSummaryFace;", "chapter", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ChapterDetail;", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(IZZZZZZLeu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicSummaryFace;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ChapterDetail;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(ZZZZZZLeu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicSummaryFace;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ChapterDetail;)V", "getChapter", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ChapterDetail;", "getComic", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicSummaryFace;", "isBanned$annotations", "()V", "()Z", "isLock$annotations", "isLogin$annotations", "isMobileBind$annotations", "isVip$annotations", "getShowApp$annotations", "getShowApp", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "copy", "equals", "other", "hashCode", "toString", "", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
/* loaded from: classes.dex */
public final /* data */ class ContentResult {

    /* renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final ChapterDetail chapter;
    private final ComicSummaryFace comic;
    private final boolean isBanned;
    private final boolean isLock;
    private final boolean isLogin;
    private final boolean isMobileBind;
    private final boolean isVip;
    private final boolean showApp;

    @SerialName("show_app")
    public static /* synthetic */ void getShowApp$annotations() {
    }

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

    /* renamed from: component1, reason: from getter */
    public final boolean getShowApp() {
        return this.showApp;
    }

    /* renamed from: component2, reason: from getter */
    public final boolean getIsLock() {
        return this.isLock;
    }

    /* renamed from: component3, reason: from getter */
    public final boolean getIsLogin() {
        return this.isLogin;
    }

    /* renamed from: component4, reason: from getter */
    public final boolean getIsMobileBind() {
        return this.isMobileBind;
    }

    /* renamed from: component5, reason: from getter */
    public final boolean getIsVip() {
        return this.isVip;
    }

    /* renamed from: component6, reason: from getter */
    public final boolean getIsBanned() {
        return this.isBanned;
    }

    /* renamed from: component7, reason: from getter */
    public final ComicSummaryFace getComic() {
        return this.comic;
    }

    /* renamed from: component8, reason: from getter */
    public final ChapterDetail getChapter() {
        return this.chapter;
    }

    public final ContentResult copy(boolean showApp, boolean isLock, boolean isLogin, boolean isMobileBind, boolean isVip, boolean isBanned, ComicSummaryFace comic, ChapterDetail chapter) {
        Intrinsics.checkNotNullParameter(comic, "comic");
        Intrinsics.checkNotNullParameter(chapter, "chapter");
        return new ContentResult(showApp, isLock, isLogin, isMobileBind, isVip, isBanned, comic, chapter);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ContentResult)) {
            return false;
        }
        ContentResult contentResult = (ContentResult) other;
        return this.showApp == contentResult.showApp && this.isLock == contentResult.isLock && this.isLogin == contentResult.isLogin && this.isMobileBind == contentResult.isMobileBind && this.isVip == contentResult.isVip && this.isBanned == contentResult.isBanned && Intrinsics.areEqual(this.comic, contentResult.comic) && Intrinsics.areEqual(this.chapter, contentResult.chapter);
    }

    /* JADX WARN: Multi-variable type inference failed */
    /* JADX WARN: Type inference failed for: r0v1, types: [int] */
    /* JADX WARN: Type inference failed for: r0v16 */
    /* JADX WARN: Type inference failed for: r0v17 */
    /* JADX WARN: Type inference failed for: r2v0, types: [boolean] */
    /* JADX WARN: Type inference failed for: r2v2, types: [boolean] */
    /* JADX WARN: Type inference failed for: r2v4, types: [boolean] */
    /* JADX WARN: Type inference failed for: r2v6, types: [boolean] */
    public int hashCode() {
        boolean z = this.showApp;
        ?? r0 = z;
        if (z) {
            r0 = 1;
        }
        int i = r0 * 31;
        ?? r2 = this.isLock;
        int i2 = r2;
        if (r2 != 0) {
            i2 = 1;
        }
        int i3 = (i + i2) * 31;
        ?? r22 = this.isLogin;
        int i4 = r22;
        if (r22 != 0) {
            i4 = 1;
        }
        int i5 = (i3 + i4) * 31;
        ?? r23 = this.isMobileBind;
        int i6 = r23;
        if (r23 != 0) {
            i6 = 1;
        }
        int i7 = (i5 + i6) * 31;
        ?? r24 = this.isVip;
        int i8 = r24;
        if (r24 != 0) {
            i8 = 1;
        }
        int i9 = (i7 + i8) * 31;
        boolean z2 = this.isBanned;
        return ((((i9 + (z2 ? 1 : z2 ? 1 : 0)) * 31) + this.comic.hashCode()) * 31) + this.chapter.hashCode();
    }

    public String toString() {
        return "ContentResult(showApp=" + this.showApp + ", isLock=" + this.isLock + ", isLogin=" + this.isLogin + ", isMobileBind=" + this.isMobileBind + ", isVip=" + this.isVip + ", isBanned=" + this.isBanned + ", comic=" + this.comic + ", chapter=" + this.chapter + ')';
    }

    /* compiled from: ContentResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ContentResult$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ContentResult;", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<ContentResult> serializer() {
            return ContentResult$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ ContentResult(int i, @SerialName("show_app") boolean z, @SerialName("is_lock") boolean z2, @SerialName("is_login") boolean z3, @SerialName("is_mobile_bind") boolean z4, @SerialName("is_vip") boolean z5, @SerialName("is_banned") boolean z6, ComicSummaryFace comicSummaryFace, ChapterDetail chapterDetail, SerializationConstructorMarker serializationConstructorMarker) {
        if (222 != (i & 222)) {
            PluginExceptionsKt.throwMissingFieldException(i, 222, ContentResult$$serializer.INSTANCE.getDescriptor());
        }
        if ((i & 1) == 0) {
            this.showApp = false;
        } else {
            this.showApp = z;
        }
        this.isLock = z2;
        this.isLogin = z3;
        this.isMobileBind = z4;
        this.isVip = z5;
        if ((i & 32) == 0) {
            this.isBanned = false;
        } else {
            this.isBanned = z6;
        }
        this.comic = comicSummaryFace;
        this.chapter = chapterDetail;
    }

    public ContentResult(boolean z, boolean z2, boolean z3, boolean z4, boolean z5, boolean z6, ComicSummaryFace comicSummaryFace, ChapterDetail chapterDetail) {
        Intrinsics.checkNotNullParameter(comicSummaryFace, "comic");
        Intrinsics.checkNotNullParameter(chapterDetail, "chapter");
        this.showApp = z;
        this.isLock = z2;
        this.isLogin = z3;
        this.isMobileBind = z4;
        this.isVip = z5;
        this.isBanned = z6;
        this.comic = comicSummaryFace;
        this.chapter = chapterDetail;
    }

    @JvmStatic
    public static final void write$Self(ContentResult self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        if (output.shouldEncodeElementDefault(serialDesc, 0) || self.showApp) {
            output.encodeBooleanElement(serialDesc, 0, self.showApp);
        }
        output.encodeBooleanElement(serialDesc, 1, self.isLock);
        output.encodeBooleanElement(serialDesc, 2, self.isLogin);
        output.encodeBooleanElement(serialDesc, 3, self.isMobileBind);
        output.encodeBooleanElement(serialDesc, 4, self.isVip);
        if (output.shouldEncodeElementDefault(serialDesc, 5) || self.isBanned) {
            output.encodeBooleanElement(serialDesc, 5, self.isBanned);
        }
        output.encodeSerializableElement(serialDesc, 6, ComicSummaryFace$$serializer.INSTANCE, self.comic);
        output.encodeSerializableElement(serialDesc, 7, ChapterDetail$$serializer.INSTANCE, self.chapter);
    }

    public /* synthetic */ ContentResult(boolean z, boolean z2, boolean z3, boolean z4, boolean z5, boolean z6, ComicSummaryFace comicSummaryFace, ChapterDetail chapterDetail, int i, DefaultConstructorMarker defaultConstructorMarker) {
        this((i & 1) != 0 ? false : z, z2, z3, z4, z5, (i & 32) != 0 ? false : z6, comicSummaryFace, chapterDetail);
    }

    public final boolean getShowApp() {
        return this.showApp;
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

    public final boolean isBanned() {
        return this.isBanned;
    }

    public final ComicSummaryFace getComic() {
        return this.comic;
    }

    public final ChapterDetail getChapter() {
        return this.chapter;
    }
}
