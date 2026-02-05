package eu.kanade.tachiyomi.extension.zh.copymanga.api.dto;

import eu.kanade.tachiyomi.extension.zh.copymanga.ApiDomainOption;
import eu.kanade.tachiyomi.extension.zh.copymanga.CCOption;
import eu.kanade.tachiyomi.extension.zh.copymanga.language.TranslateKt;
import eu.kanade.tachiyomi.source.model.SManga;
import java.util.List;
import kotlin.Deprecated;
import kotlin.DeprecationLevel;
import kotlin.Metadata;
import kotlin.ReplaceWith;
import kotlin.jvm.JvmStatic;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlinx.serialization.KSerializer;
import kotlinx.serialization.Serializable;
import kotlinx.serialization.descriptors.SerialDescriptor;
import kotlinx.serialization.encoding.CompositeEncoder;
import kotlinx.serialization.internal.ArrayListSerializer;
import kotlinx.serialization.internal.PluginExceptionsKt;
import kotlinx.serialization.internal.SerializationConstructorMarker;

/* compiled from: CollectResult.kt */
@Metadata(d1 = {"\u0000V\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0004\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u000e\n\u0002\u0010\u000b\n\u0002\b\u0004\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 -2\u00020\u0001:\u0002,-BA\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0003\u0012\u0006\u0010\u0006\u001a\u00020\u0003\u0012\u000e\u0010\u0007\u001a\n\u0012\u0004\u0012\u00020\t\u0018\u00010\b\u0012\b\u0010\n\u001a\u0004\u0018\u00010\u000b¢\u0006\u0002\u0010\fB+\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0003\u0012\u0006\u0010\u0006\u001a\u00020\u0003\u0012\f\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\t0\b¢\u0006\u0002\u0010\rJ\t\u0010\u0014\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0015\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0016\u001a\u00020\u0003HÆ\u0003J\u000f\u0010\u0017\u001a\b\u0012\u0004\u0012\u00020\t0\bHÆ\u0003J7\u0010\u0018\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00032\b\b\u0002\u0010\u0006\u001a\u00020\u00032\u000e\b\u0002\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\t0\bHÆ\u0001J\u0013\u0010\u0019\u001a\u00020\u001a2\b\u0010\u001b\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\u0006\u0010\u001c\u001a\u00020\u001aJ\t\u0010\u001d\u001a\u00020\u0003HÖ\u0001J\u0016\u0010\u001e\u001a\u00020\u001f2\u0006\u0010 \u001a\u00020!2\u0006\u0010\"\u001a\u00020#J\t\u0010$\u001a\u00020!HÖ\u0001J!\u0010%\u001a\u00020&2\u0006\u0010'\u001a\u00020\u00002\u0006\u0010(\u001a\u00020)2\u0006\u0010*\u001a\u00020+HÇ\u0001R\u0011\u0010\u0005\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\u000fR\u0017\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\t0\b¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u0011R\u0011\u0010\u0006\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0012\u0010\u000fR\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0013\u0010\u000f¨\u0006."}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectResult;", "", "seen1", "", "total", "limit", "offset", "list", "", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectInfo;", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(IIIILjava/util/List;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(IIILjava/util/List;)V", "getLimit", "()I", "getList", "()Ljava/util/List;", "getOffset", "getTotal", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hasNext", "hashCode", "infoComic", "Leu/kanade/tachiyomi/source/model/SManga;", "domain", "", "language", "Leu/kanade/tachiyomi/extension/zh/copymanga/CCOption;", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
/* loaded from: classes.dex */
public final /* data */ class CollectResult {

    /* renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final int limit;
    private final List<CollectInfo> list;
    private final int offset;
    private final int total;

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ CollectResult copy$default(CollectResult collectResult, int i, int i2, int i3, List list, int i4, Object obj) {
        if ((i4 & 1) != 0) {
            i = collectResult.total;
        }
        if ((i4 & 2) != 0) {
            i2 = collectResult.limit;
        }
        if ((i4 & 4) != 0) {
            i3 = collectResult.offset;
        }
        if ((i4 & 8) != 0) {
            list = collectResult.list;
        }
        return collectResult.copy(i, i2, i3, list);
    }

    /* renamed from: component1, reason: from getter */
    public final int getTotal() {
        return this.total;
    }

    /* renamed from: component2, reason: from getter */
    public final int getLimit() {
        return this.limit;
    }

    /* renamed from: component3, reason: from getter */
    public final int getOffset() {
        return this.offset;
    }

    public final List<CollectInfo> component4() {
        return this.list;
    }

    public final CollectResult copy(int total, int limit, int offset, List<CollectInfo> list) {
        Intrinsics.checkNotNullParameter(list, "list");
        return new CollectResult(total, limit, offset, list);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof CollectResult)) {
            return false;
        }
        CollectResult collectResult = (CollectResult) other;
        return this.total == collectResult.total && this.limit == collectResult.limit && this.offset == collectResult.offset && Intrinsics.areEqual(this.list, collectResult.list);
    }

    public int hashCode() {
        return (((((this.total * 31) + this.limit) * 31) + this.offset) * 31) + this.list.hashCode();
    }

    public String toString() {
        return "CollectResult(total=" + this.total + ", limit=" + this.limit + ", offset=" + this.offset + ", list=" + this.list + ')';
    }

    /* compiled from: CollectResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectResult$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectResult;", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<CollectResult> serializer() {
            return CollectResult$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ CollectResult(int i, int i2, int i3, int i4, List list, SerializationConstructorMarker serializationConstructorMarker) {
        if (15 != (i & 15)) {
            PluginExceptionsKt.throwMissingFieldException(i, 15, CollectResult$$serializer.INSTANCE.getDescriptor());
        }
        this.total = i2;
        this.limit = i3;
        this.offset = i4;
        this.list = list;
    }

    public CollectResult(int i, int i2, int i3, List<CollectInfo> list) {
        Intrinsics.checkNotNullParameter(list, "list");
        this.total = i;
        this.limit = i2;
        this.offset = i3;
        this.list = list;
    }

    @JvmStatic
    public static final void write$Self(CollectResult self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeIntElement(serialDesc, 0, self.total);
        output.encodeIntElement(serialDesc, 1, self.limit);
        output.encodeIntElement(serialDesc, 2, self.offset);
        output.encodeSerializableElement(serialDesc, 3, new ArrayListSerializer(CollectInfo$$serializer.INSTANCE), self.list);
    }

    public final int getTotal() {
        return this.total;
    }

    public final int getLimit() {
        return this.limit;
    }

    public final int getOffset() {
        return this.offset;
    }

    public final List<CollectInfo> getList() {
        return this.list;
    }

    public final SManga infoComic(String domain, CCOption language) {
        Intrinsics.checkNotNullParameter(domain, "domain");
        Intrinsics.checkNotNullParameter(language, "language");
        SManga sMangaCreate = SManga.Companion.create();
        String str = ApiDomainOption.INSTANCE.isCopyManga(domain) ? "拷貝" : "熱辣";
        String str2 = ApiDomainOption.INSTANCE.isCopyManga(domain) ? "熱辣" : "拷貝";
        String str3 = ApiDomainOption.INSTANCE.isCopyManga(domain) ? "https://hi77-overseas.mangafuna.xyz/static/free.ico" : "https://hi77-overseas.mangafuna.xyz/static/favicon.ico";
        sMangaCreate.setTitle(TranslateKt.translate("此篩選結果為你的" + str + "漫畫帳號書櫃", language));
        sMangaCreate.setUrl("extension-info/collection/".concat(str));
        sMangaCreate.setAuthor("TheNano/LittleSurvival");
        sMangaCreate.setDescription(TranslateKt.translate("若要瀏覽" + str2 + "漫畫收藏，請在插鍵設定中切換API域名\n\n防文盲的简易提示，请勿收藏", language));
        sMangaCreate.setGenre("插键资讯");
        sMangaCreate.setStatus(2);
        sMangaCreate.setThumbnail_url(str3);
        sMangaCreate.setInitialized(true);
        return sMangaCreate;
    }

    public final boolean hasNext() {
        return this.total >= this.offset + this.limit;
    }
}
