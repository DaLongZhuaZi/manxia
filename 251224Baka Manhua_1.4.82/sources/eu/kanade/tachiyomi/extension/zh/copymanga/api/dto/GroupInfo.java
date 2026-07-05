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

/* JADX INFO: compiled from: ComicDetailResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000>\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u000e\n\u0002\u0010\u000b\n\u0002\b\u0004\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 $2\u00020\u0001:\u0002#$B7\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\n\b\u0001\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0003\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\b\u001a\u0004\u0018\u00010\t¢\u0006\u0002\u0010\nB\u001d\u0012\u0006\u0010\u0004\u001a\u00020\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0003\u0012\u0006\u0010\u0007\u001a\u00020\u0005¢\u0006\u0002\u0010\u000bJ\t\u0010\u0013\u001a\u00020\u0005HÆ\u0003J\t\u0010\u0014\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0015\u001a\u00020\u0005HÆ\u0003J'\u0010\u0016\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00052\b\b\u0002\u0010\u0006\u001a\u00020\u00032\b\b\u0002\u0010\u0007\u001a\u00020\u0005HÆ\u0001J\u0013\u0010\u0017\u001a\u00020\u00182\b\u0010\u0019\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u001a\u001a\u00020\u0003HÖ\u0001J\t\u0010\u001b\u001a\u00020\u0005HÖ\u0001J!\u0010\u001c\u001a\u00020\u001d2\u0006\u0010\u001e\u001a\u00020\u00002\u0006\u0010\u001f\u001a\u00020 2\u0006\u0010!\u001a\u00020\"HÇ\u0001R\u0011\u0010\u0006\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0011\u0010\u0007\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\u000fR\u001c\u0010\u0004\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0010\u0010\u0011\u001a\u0004\b\u0012\u0010\u000f¨\u0006%"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/GroupInfo;", "", "seen1", "", "pathWord", "", "count", "name", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(ILjava/lang/String;ILjava/lang/String;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(Ljava/lang/String;ILjava/lang/String;)V", "getCount", "()I", "getName", "()Ljava/lang/String;", "getPathWord$annotations", "()V", "getPathWord", "component1", "component2", "component3", "copy", "equals", "", "other", "hashCode", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
public final /* data */ class GroupInfo {

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final int count;
    private final String name;
    private final String pathWord;

    public static /* synthetic */ GroupInfo copy$default(GroupInfo groupInfo, String str, int i, String str2, int i2, Object obj) {
        if ((i2 & 1) != 0) {
            str = groupInfo.pathWord;
        }
        if ((i2 & 2) != 0) {
            i = groupInfo.count;
        }
        if ((i2 & 4) != 0) {
            str2 = groupInfo.name;
        }
        return groupInfo.copy(str, i, str2);
    }

    @SerialName("path_word")
    public static /* synthetic */ void getPathWord$annotations() {
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getPathWord() {
        return this.pathWord;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final int getCount() {
        return this.count;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getName() {
        return this.name;
    }

    public final GroupInfo copy(String pathWord, int count, String name) {
        Intrinsics.checkNotNullParameter(pathWord, "pathWord");
        Intrinsics.checkNotNullParameter(name, "name");
        return new GroupInfo(pathWord, count, name);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof GroupInfo)) {
            return false;
        }
        GroupInfo groupInfo = (GroupInfo) other;
        return Intrinsics.areEqual(this.pathWord, groupInfo.pathWord) && this.count == groupInfo.count && Intrinsics.areEqual(this.name, groupInfo.name);
    }

    public int hashCode() {
        return (((this.pathWord.hashCode() * 31) + this.count) * 31) + this.name.hashCode();
    }

    public String toString() {
        return "GroupInfo(pathWord=" + this.pathWord + ", count=" + this.count + ", name=" + this.name + ')';
    }

    /* JADX INFO: compiled from: ComicDetailResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/GroupInfo$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/GroupInfo;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<GroupInfo> serializer() {
            return GroupInfo$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ GroupInfo(int i, @SerialName("path_word") String str, int i2, String str2, SerializationConstructorMarker serializationConstructorMarker) {
        if (7 != (i & 7)) {
            PluginExceptionsKt.throwMissingFieldException(i, 7, GroupInfo$$serializer.INSTANCE.getDescriptor());
        }
        this.pathWord = str;
        this.count = i2;
        this.name = str2;
    }

    public GroupInfo(String str, int i, String str2) {
        Intrinsics.checkNotNullParameter(str, "pathWord");
        Intrinsics.checkNotNullParameter(str2, "name");
        this.pathWord = str;
        this.count = i;
        this.name = str2;
    }

    @JvmStatic
    public static final void write$Self(GroupInfo self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeStringElement(serialDesc, 0, self.pathWord);
        output.encodeIntElement(serialDesc, 1, self.count);
        output.encodeStringElement(serialDesc, 2, self.name);
    }

    public final String getPathWord() {
        return this.pathWord;
    }

    public final int getCount() {
        return this.count;
    }

    public final String getName() {
        return this.name;
    }
}
