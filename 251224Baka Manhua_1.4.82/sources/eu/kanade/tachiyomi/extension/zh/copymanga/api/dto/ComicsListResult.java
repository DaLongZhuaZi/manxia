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

/* JADX INFO: compiled from: ComicsListResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000J\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0002\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u000e\n\u0002\u0010\u000b\n\u0002\b\u0004\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 (2\u00020\u0001:\u0002'(BA\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u000e\u0010\u0005\u001a\n\u0012\u0004\u0012\u00020\u0007\u0018\u00010\u0006\u0012\u0006\u0010\b\u001a\u00020\u0003\u0012\u0006\u0010\t\u001a\u00020\u0003\u0012\b\u0010\n\u001a\u0004\u0018\u00010\u000b¢\u0006\u0002\u0010\fB+\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\f\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00070\u0006\u0012\u0006\u0010\b\u001a\u00020\u0003\u0012\u0006\u0010\t\u001a\u00020\u0003¢\u0006\u0002\u0010\rJ\t\u0010\u0014\u001a\u00020\u0003HÆ\u0003J\u000f\u0010\u0015\u001a\b\u0012\u0004\u0012\u00020\u00070\u0006HÆ\u0003J\t\u0010\u0016\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0017\u001a\u00020\u0003HÆ\u0003J7\u0010\u0018\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00032\u000e\b\u0002\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00070\u00062\b\b\u0002\u0010\b\u001a\u00020\u00032\b\b\u0002\u0010\t\u001a\u00020\u0003HÆ\u0001J\u0013\u0010\u0019\u001a\u00020\u001a2\b\u0010\u001b\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\u0006\u0010\u001c\u001a\u00020\u001aJ\t\u0010\u001d\u001a\u00020\u0003HÖ\u0001J\t\u0010\u001e\u001a\u00020\u001fHÖ\u0001J!\u0010 \u001a\u00020!2\u0006\u0010\"\u001a\u00020\u00002\u0006\u0010#\u001a\u00020$2\u0006\u0010%\u001a\u00020&HÇ\u0001R\u0011\u0010\b\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\u000fR\u0017\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00070\u0006¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u0011R\u0011\u0010\t\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0012\u0010\u000fR\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0013\u0010\u000f¨\u0006)"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicsListResult;", "", "seen1", "", "total", "list", "", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicSummary;", "limit", "offset", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(IILjava/util/List;IILkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(ILjava/util/List;II)V", "getLimit", "()I", "getList", "()Ljava/util/List;", "getOffset", "getTotal", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hasNext", "hashCode", "toString", "", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
public final /* data */ class ComicsListResult {

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final int limit;
    private final List<ComicSummary> list;
    private final int offset;
    private final int total;

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ ComicsListResult copy$default(ComicsListResult comicsListResult, int i, List list, int i2, int i3, int i4, Object obj) {
        if ((i4 & 1) != 0) {
            i = comicsListResult.total;
        }
        if ((i4 & 2) != 0) {
            list = comicsListResult.list;
        }
        if ((i4 & 4) != 0) {
            i2 = comicsListResult.limit;
        }
        if ((i4 & 8) != 0) {
            i3 = comicsListResult.offset;
        }
        return comicsListResult.copy(i, list, i2, i3);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final int getTotal() {
        return this.total;
    }

    public final List<ComicSummary> component2() {
        return this.list;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final int getLimit() {
        return this.limit;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final int getOffset() {
        return this.offset;
    }

    public final ComicsListResult copy(int total, List<ComicSummary> list, int limit, int offset) {
        Intrinsics.checkNotNullParameter(list, "list");
        return new ComicsListResult(total, list, limit, offset);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ComicsListResult)) {
            return false;
        }
        ComicsListResult comicsListResult = (ComicsListResult) other;
        return this.total == comicsListResult.total && Intrinsics.areEqual(this.list, comicsListResult.list) && this.limit == comicsListResult.limit && this.offset == comicsListResult.offset;
    }

    public int hashCode() {
        return (((((this.total * 31) + this.list.hashCode()) * 31) + this.limit) * 31) + this.offset;
    }

    public String toString() {
        return "ComicsListResult(total=" + this.total + ", list=" + this.list + ", limit=" + this.limit + ", offset=" + this.offset + ')';
    }

    /* JADX INFO: compiled from: ComicsListResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicsListResult$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicsListResult;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<ComicsListResult> serializer() {
            return ComicsListResult$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ ComicsListResult(int i, int i2, List list, int i3, int i4, SerializationConstructorMarker serializationConstructorMarker) {
        if (15 != (i & 15)) {
            PluginExceptionsKt.throwMissingFieldException(i, 15, ComicsListResult$$serializer.INSTANCE.getDescriptor());
        }
        this.total = i2;
        this.list = list;
        this.limit = i3;
        this.offset = i4;
    }

    public ComicsListResult(int i, List<ComicSummary> list, int i2, int i3) {
        Intrinsics.checkNotNullParameter(list, "list");
        this.total = i;
        this.list = list;
        this.limit = i2;
        this.offset = i3;
    }

    @JvmStatic
    public static final void write$Self(ComicsListResult self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeIntElement(serialDesc, 0, self.total);
        output.encodeSerializableElement(serialDesc, 1, new ArrayListSerializer(ComicSummary$$serializer.INSTANCE), self.list);
        output.encodeIntElement(serialDesc, 2, self.limit);
        output.encodeIntElement(serialDesc, 3, self.offset);
    }

    public final int getTotal() {
        return this.total;
    }

    public final List<ComicSummary> getList() {
        return this.list;
    }

    public final int getLimit() {
        return this.limit;
    }

    public final int getOffset() {
        return this.offset;
    }

    public final boolean hasNext() {
        return this.total >= this.offset + this.limit;
    }
}
