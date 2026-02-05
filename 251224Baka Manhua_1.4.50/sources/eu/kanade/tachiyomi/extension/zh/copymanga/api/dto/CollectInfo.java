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
import kotlinx.serialization.internal.IntSerializer;
import kotlinx.serialization.internal.PluginExceptionsKt;
import kotlinx.serialization.internal.SerializationConstructorMarker;
import kotlinx.serialization.internal.StringSerializer;

/* compiled from: CollectResult.kt */
@Metadata(d1 = {"\u0000J\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b \n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 72\u00020\u0001:\u000267BW\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0006\u0012\b\b\u0001\u0010\u0007\u001a\u00020\b\u0012\n\b\u0001\u0010\t\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0001\u0010\n\u001a\u0004\u0018\u00010\u000b\u0012\b\u0010\f\u001a\u0004\u0018\u00010\r\u0012\b\u0010\u000e\u001a\u0004\u0018\u00010\u000f¢\u0006\u0002\u0010\u0010BA\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\n\b\u0002\u0010\u0005\u001a\u0004\u0018\u00010\u0006\u0012\u0006\u0010\u0007\u001a\u00020\b\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u000b\u0012\u0006\u0010\f\u001a\u00020\r¢\u0006\u0002\u0010\u0011J\t\u0010#\u001a\u00020\u0003HÆ\u0003J\u000b\u0010$\u001a\u0004\u0018\u00010\u0006HÆ\u0003J\t\u0010%\u001a\u00020\bHÆ\u0003J\u0010\u0010&\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u001aJ\u000b\u0010'\u001a\u0004\u0018\u00010\u000bHÆ\u0003J\t\u0010(\u001a\u00020\rHÆ\u0003JP\u0010)\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00032\n\b\u0002\u0010\u0005\u001a\u0004\u0018\u00010\u00062\b\b\u0002\u0010\u0007\u001a\u00020\b2\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u000b2\b\b\u0002\u0010\f\u001a\u00020\rHÆ\u0001¢\u0006\u0002\u0010*J\u0013\u0010+\u001a\u00020\b2\b\u0010,\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010-\u001a\u00020\u0003HÖ\u0001J\t\u0010.\u001a\u00020\u0006HÖ\u0001J!\u0010/\u001a\u0002002\u0006\u00101\u001a\u00020\u00002\u0006\u00102\u001a\u0002032\u0006\u00104\u001a\u000205HÇ\u0001R\u001c\u0010\u0007\u001a\u00020\b8\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0012\u0010\u0013\u001a\u0004\b\u0014\u0010\u0015R\u0011\u0010\f\u001a\u00020\r¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0017R \u0010\t\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\u0010\n\u0002\u0010\u001b\u0012\u0004\b\u0018\u0010\u0013\u001a\u0004\b\u0019\u0010\u001aR\u001e\u0010\n\u001a\u0004\u0018\u00010\u000b8\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001c\u0010\u0013\u001a\u0004\b\u001d\u0010\u001eR\u0013\u0010\u0005\u001a\u0004\u0018\u00010\u0006¢\u0006\b\n\u0000\u001a\u0004\b\u001f\u0010 R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b!\u0010\"¨\u00068"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectInfo;", "", "seen1", "", "uuid", "name", "", "bFolder", "", "folderId", "lastBrowse", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/LastBrowse;", "comic", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectComic;", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(IILjava/lang/String;ZLjava/lang/Integer;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/LastBrowse;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectComic;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(ILjava/lang/String;ZLjava/lang/Integer;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/LastBrowse;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectComic;)V", "getBFolder$annotations", "()V", "getBFolder", "()Z", "getComic", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectComic;", "getFolderId$annotations", "getFolderId", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getLastBrowse$annotations", "getLastBrowse", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/LastBrowse;", "getName", "()Ljava/lang/String;", "getUuid", "()I", "component1", "component2", "component3", "component4", "component5", "component6", "copy", "(ILjava/lang/String;ZLjava/lang/Integer;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/LastBrowse;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectComic;)Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectInfo;", "equals", "other", "hashCode", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
/* loaded from: classes.dex */
public final /* data */ class CollectInfo {

    /* renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final boolean bFolder;
    private final CollectComic comic;
    private final Integer folderId;
    private final LastBrowse lastBrowse;
    private final String name;
    private final int uuid;

    public static /* synthetic */ CollectInfo copy$default(CollectInfo collectInfo, int i, String str, boolean z, Integer num, LastBrowse lastBrowse, CollectComic collectComic, int i2, Object obj) {
        if ((i2 & 1) != 0) {
            i = collectInfo.uuid;
        }
        if ((i2 & 2) != 0) {
            str = collectInfo.name;
        }
        String str2 = str;
        if ((i2 & 4) != 0) {
            z = collectInfo.bFolder;
        }
        boolean z2 = z;
        if ((i2 & 8) != 0) {
            num = collectInfo.folderId;
        }
        Integer num2 = num;
        if ((i2 & 16) != 0) {
            lastBrowse = collectInfo.lastBrowse;
        }
        LastBrowse lastBrowse2 = lastBrowse;
        if ((i2 & 32) != 0) {
            collectComic = collectInfo.comic;
        }
        return collectInfo.copy(i, str2, z2, num2, lastBrowse2, collectComic);
    }

    @SerialName("b_folder")
    public static /* synthetic */ void getBFolder$annotations() {
    }

    @SerialName("folder_id")
    public static /* synthetic */ void getFolderId$annotations() {
    }

    @SerialName("last_browse")
    public static /* synthetic */ void getLastBrowse$annotations() {
    }

    /* renamed from: component1, reason: from getter */
    public final int getUuid() {
        return this.uuid;
    }

    /* renamed from: component2, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* renamed from: component3, reason: from getter */
    public final boolean getBFolder() {
        return this.bFolder;
    }

    /* renamed from: component4, reason: from getter */
    public final Integer getFolderId() {
        return this.folderId;
    }

    /* renamed from: component5, reason: from getter */
    public final LastBrowse getLastBrowse() {
        return this.lastBrowse;
    }

    /* renamed from: component6, reason: from getter */
    public final CollectComic getComic() {
        return this.comic;
    }

    public final CollectInfo copy(int uuid, String name, boolean bFolder, Integer folderId, LastBrowse lastBrowse, CollectComic comic) {
        Intrinsics.checkNotNullParameter(comic, "comic");
        return new CollectInfo(uuid, name, bFolder, folderId, lastBrowse, comic);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof CollectInfo)) {
            return false;
        }
        CollectInfo collectInfo = (CollectInfo) other;
        return this.uuid == collectInfo.uuid && Intrinsics.areEqual(this.name, collectInfo.name) && this.bFolder == collectInfo.bFolder && Intrinsics.areEqual(this.folderId, collectInfo.folderId) && Intrinsics.areEqual(this.lastBrowse, collectInfo.lastBrowse) && Intrinsics.areEqual(this.comic, collectInfo.comic);
    }

    /* JADX WARN: Multi-variable type inference failed */
    public int hashCode() {
        int i = this.uuid * 31;
        String str = this.name;
        int iHashCode = (i + (str == null ? 0 : str.hashCode())) * 31;
        boolean z = this.bFolder;
        int i2 = z;
        if (z != 0) {
            i2 = 1;
        }
        int i3 = (iHashCode + i2) * 31;
        Integer num = this.folderId;
        int iHashCode2 = (i3 + (num == null ? 0 : num.hashCode())) * 31;
        LastBrowse lastBrowse = this.lastBrowse;
        return ((iHashCode2 + (lastBrowse != null ? lastBrowse.hashCode() : 0)) * 31) + this.comic.hashCode();
    }

    public String toString() {
        return "CollectInfo(uuid=" + this.uuid + ", name=" + this.name + ", bFolder=" + this.bFolder + ", folderId=" + this.folderId + ", lastBrowse=" + this.lastBrowse + ", comic=" + this.comic + ')';
    }

    /* compiled from: CollectResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectInfo$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectInfo;", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<CollectInfo> serializer() {
            return CollectInfo$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ CollectInfo(int i, int i2, String str, @SerialName("b_folder") boolean z, @SerialName("folder_id") Integer num, @SerialName("last_browse") LastBrowse lastBrowse, CollectComic collectComic, SerializationConstructorMarker serializationConstructorMarker) {
        if (37 != (i & 37)) {
            PluginExceptionsKt.throwMissingFieldException(i, 37, CollectInfo$$serializer.INSTANCE.getDescriptor());
        }
        this.uuid = i2;
        if ((i & 2) == 0) {
            this.name = null;
        } else {
            this.name = str;
        }
        this.bFolder = z;
        if ((i & 8) == 0) {
            this.folderId = null;
        } else {
            this.folderId = num;
        }
        if ((i & 16) == 0) {
            this.lastBrowse = null;
        } else {
            this.lastBrowse = lastBrowse;
        }
        this.comic = collectComic;
    }

    public CollectInfo(int i, String str, boolean z, Integer num, LastBrowse lastBrowse, CollectComic collectComic) {
        Intrinsics.checkNotNullParameter(collectComic, "comic");
        this.uuid = i;
        this.name = str;
        this.bFolder = z;
        this.folderId = num;
        this.lastBrowse = lastBrowse;
        this.comic = collectComic;
    }

    @JvmStatic
    public static final void write$Self(CollectInfo self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeIntElement(serialDesc, 0, self.uuid);
        if (output.shouldEncodeElementDefault(serialDesc, 1) || self.name != null) {
            output.encodeNullableSerializableElement(serialDesc, 1, StringSerializer.INSTANCE, self.name);
        }
        output.encodeBooleanElement(serialDesc, 2, self.bFolder);
        if (output.shouldEncodeElementDefault(serialDesc, 3) || self.folderId != null) {
            output.encodeNullableSerializableElement(serialDesc, 3, IntSerializer.INSTANCE, self.folderId);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 4) || self.lastBrowse != null) {
            output.encodeNullableSerializableElement(serialDesc, 4, LastBrowse$$serializer.INSTANCE, self.lastBrowse);
        }
        output.encodeSerializableElement(serialDesc, 5, CollectComic$$serializer.INSTANCE, self.comic);
    }

    public /* synthetic */ CollectInfo(int i, String str, boolean z, Integer num, LastBrowse lastBrowse, CollectComic collectComic, int i2, DefaultConstructorMarker defaultConstructorMarker) {
        this(i, (i2 & 2) != 0 ? null : str, z, (i2 & 8) != 0 ? null : num, (i2 & 16) != 0 ? null : lastBrowse, collectComic);
    }

    public final int getUuid() {
        return this.uuid;
    }

    public final String getName() {
        return this.name;
    }

    public final boolean getBFolder() {
        return this.bFolder;
    }

    public final Integer getFolderId() {
        return this.folderId;
    }

    public final LastBrowse getLastBrowse() {
        return this.lastBrowse;
    }

    public final CollectComic getComic() {
        return this.comic;
    }
}
