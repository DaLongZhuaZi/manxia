package eu.kanade.tachiyomi.extension.zh.copymanga.api.dto;

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

/* compiled from: RecommendResult.kt */
@Metadata(d1 = {"\u0000H\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0004\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u000e\n\u0002\u0010\u000b\n\u0002\b\u0004\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 (2\u00020\u0001:\u0002'(BA\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0003\u0012\u0006\u0010\u0006\u001a\u00020\u0003\u0012\u000e\u0010\u0007\u001a\n\u0012\u0004\u0012\u00020\t\u0018\u00010\b\u0012\b\u0010\n\u001a\u0004\u0018\u00010\u000b¢\u0006\u0002\u0010\fB+\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0003\u0012\u0006\u0010\u0006\u001a\u00020\u0003\u0012\f\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\t0\b¢\u0006\u0002\u0010\rJ\t\u0010\u0014\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0015\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0016\u001a\u00020\u0003HÆ\u0003J\u000f\u0010\u0017\u001a\b\u0012\u0004\u0012\u00020\t0\bHÆ\u0003J7\u0010\u0018\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00032\b\b\u0002\u0010\u0006\u001a\u00020\u00032\u000e\b\u0002\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\t0\bHÆ\u0001J\u0013\u0010\u0019\u001a\u00020\u001a2\b\u0010\u001b\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\u0006\u0010\u001c\u001a\u00020\u001aJ\t\u0010\u001d\u001a\u00020\u0003HÖ\u0001J\t\u0010\u001e\u001a\u00020\u001fHÖ\u0001J!\u0010 \u001a\u00020!2\u0006\u0010\"\u001a\u00020\u00002\u0006\u0010#\u001a\u00020$2\u0006\u0010%\u001a\u00020&HÇ\u0001R\u0011\u0010\u0005\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\u000fR\u0017\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\t0\b¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u0011R\u0011\u0010\u0006\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0012\u0010\u000fR\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0013\u0010\u000f¨\u0006)"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/RecommendResult;", "", "seen1", "", "total", "limit", "offset", "list", "", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Recommendation;", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(IIIILjava/util/List;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(IIILjava/util/List;)V", "getLimit", "()I", "getList", "()Ljava/util/List;", "getOffset", "getTotal", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hasNext", "hashCode", "toString", "", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
/* loaded from: classes.dex */
public final /* data */ class RecommendResult {

    /* renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final int limit;
    private final List<Recommendation> list;
    private final int offset;
    private final int total;

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ RecommendResult copy$default(RecommendResult recommendResult, int i, int i2, int i3, List list, int i4, Object obj) {
        if ((i4 & 1) != 0) {
            i = recommendResult.total;
        }
        if ((i4 & 2) != 0) {
            i2 = recommendResult.limit;
        }
        if ((i4 & 4) != 0) {
            i3 = recommendResult.offset;
        }
        if ((i4 & 8) != 0) {
            list = recommendResult.list;
        }
        return recommendResult.copy(i, i2, i3, list);
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

    public final List<Recommendation> component4() {
        return this.list;
    }

    public final RecommendResult copy(int total, int limit, int offset, List<Recommendation> list) {
        Intrinsics.checkNotNullParameter(list, "list");
        return new RecommendResult(total, limit, offset, list);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof RecommendResult)) {
            return false;
        }
        RecommendResult recommendResult = (RecommendResult) other;
        return this.total == recommendResult.total && this.limit == recommendResult.limit && this.offset == recommendResult.offset && Intrinsics.areEqual(this.list, recommendResult.list);
    }

    public int hashCode() {
        return (((((this.total * 31) + this.limit) * 31) + this.offset) * 31) + this.list.hashCode();
    }

    public String toString() {
        return "RecommendResult(total=" + this.total + ", limit=" + this.limit + ", offset=" + this.offset + ", list=" + this.list + ')';
    }

    /* compiled from: RecommendResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/RecommendResult$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/RecommendResult;", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<RecommendResult> serializer() {
            return RecommendResult$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ RecommendResult(int i, int i2, int i3, int i4, List list, SerializationConstructorMarker serializationConstructorMarker) {
        if (15 != (i & 15)) {
            PluginExceptionsKt.throwMissingFieldException(i, 15, RecommendResult$$serializer.INSTANCE.getDescriptor());
        }
        this.total = i2;
        this.limit = i3;
        this.offset = i4;
        this.list = list;
    }

    public RecommendResult(int i, int i2, int i3, List<Recommendation> list) {
        Intrinsics.checkNotNullParameter(list, "list");
        this.total = i;
        this.limit = i2;
        this.offset = i3;
        this.list = list;
    }

    @JvmStatic
    public static final void write$Self(RecommendResult self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeIntElement(serialDesc, 0, self.total);
        output.encodeIntElement(serialDesc, 1, self.limit);
        output.encodeIntElement(serialDesc, 2, self.offset);
        output.encodeSerializableElement(serialDesc, 3, new ArrayListSerializer(Recommendation$$serializer.INSTANCE), self.list);
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

    public final List<Recommendation> getList() {
        return this.list;
    }

    public final boolean hasNext() {
        return this.total >= this.offset + this.limit;
    }
}
