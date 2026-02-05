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
import kotlinx.serialization.internal.StringSerializer;

/* compiled from: TagResult.kt */
@Metadata(d1 = {"\u0000@\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0002\b\u0015\n\u0002\u0010\u000b\n\u0002\b\u0004\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 .2\u00020\u0001:\u0002-.BU\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0006\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\b\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\t\u001a\u0004\u0018\u00010\u0006\u0012\u0006\u0010\n\u001a\u00020\u0003\u0012\b\u0010\u000b\u001a\u0004\u0018\u00010\f¢\u0006\u0002\u0010\rB=\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0006\u0012\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0006\u0012\u0006\u0010\t\u001a\u00020\u0006\u0012\u0006\u0010\n\u001a\u00020\u0003¢\u0006\u0002\u0010\u000eJ\t\u0010\u001a\u001a\u00020\u0003HÆ\u0003J\t\u0010\u001b\u001a\u00020\u0006HÆ\u0003J\u000b\u0010\u001c\u001a\u0004\u0018\u00010\u0006HÆ\u0003J\u000b\u0010\u001d\u001a\u0004\u0018\u00010\u0006HÆ\u0003J\t\u0010\u001e\u001a\u00020\u0006HÆ\u0003J\t\u0010\u001f\u001a\u00020\u0003HÆ\u0003JI\u0010 \u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00062\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\u00062\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00062\b\b\u0002\u0010\t\u001a\u00020\u00062\b\b\u0002\u0010\n\u001a\u00020\u0003HÆ\u0001J\u0013\u0010!\u001a\u00020\"2\b\u0010#\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010$\u001a\u00020\u0003HÖ\u0001J\t\u0010%\u001a\u00020\u0006HÖ\u0001J!\u0010&\u001a\u00020'2\u0006\u0010(\u001a\u00020\u00002\u0006\u0010)\u001a\u00020*2\u0006\u0010+\u001a\u00020,HÇ\u0001R\u001e\u0010\b\u001a\u0004\u0018\u00010\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u000f\u0010\u0010\u001a\u0004\b\u0011\u0010\u0012R\u0011\u0010\n\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0013\u0010\u0014R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0015\u0010\u0014R\u0013\u0010\u0007\u001a\u0004\u0018\u00010\u0006¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0012R\u0011\u0010\u0005\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b\u0017\u0010\u0012R\u001c\u0010\t\u001a\u00020\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0018\u0010\u0010\u001a\u0004\b\u0019\u0010\u0012¨\u0006/"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ThemeDetail;", "", "seen1", "", "initials", "name", "", "logo", "colorH5", "pathWord", "count", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(IILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ILkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;I)V", "getColorH5$annotations", "()V", "getColorH5", "()Ljava/lang/String;", "getCount", "()I", "getInitials", "getLogo", "getName", "getPathWord$annotations", "getPathWord", "component1", "component2", "component3", "component4", "component5", "component6", "copy", "equals", "", "other", "hashCode", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
/* loaded from: classes.dex */
public final /* data */ class ThemeDetail {

    /* renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final String colorH5;
    private final int count;
    private final int initials;
    private final String logo;
    private final String name;
    private final String pathWord;

    public static /* synthetic */ ThemeDetail copy$default(ThemeDetail themeDetail, int i, String str, String str2, String str3, String str4, int i2, int i3, Object obj) {
        if ((i3 & 1) != 0) {
            i = themeDetail.initials;
        }
        if ((i3 & 2) != 0) {
            str = themeDetail.name;
        }
        String str5 = str;
        if ((i3 & 4) != 0) {
            str2 = themeDetail.logo;
        }
        String str6 = str2;
        if ((i3 & 8) != 0) {
            str3 = themeDetail.colorH5;
        }
        String str7 = str3;
        if ((i3 & 16) != 0) {
            str4 = themeDetail.pathWord;
        }
        String str8 = str4;
        if ((i3 & 32) != 0) {
            i2 = themeDetail.count;
        }
        return themeDetail.copy(i, str5, str6, str7, str8, i2);
    }

    @SerialName("color_h5")
    public static /* synthetic */ void getColorH5$annotations() {
    }

    @SerialName("path_word")
    public static /* synthetic */ void getPathWord$annotations() {
    }

    /* renamed from: component1, reason: from getter */
    public final int getInitials() {
        return this.initials;
    }

    /* renamed from: component2, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* renamed from: component3, reason: from getter */
    public final String getLogo() {
        return this.logo;
    }

    /* renamed from: component4, reason: from getter */
    public final String getColorH5() {
        return this.colorH5;
    }

    /* renamed from: component5, reason: from getter */
    public final String getPathWord() {
        return this.pathWord;
    }

    /* renamed from: component6, reason: from getter */
    public final int getCount() {
        return this.count;
    }

    public final ThemeDetail copy(int initials, String name, String logo, String colorH5, String pathWord, int count) {
        Intrinsics.checkNotNullParameter(name, "name");
        Intrinsics.checkNotNullParameter(pathWord, "pathWord");
        return new ThemeDetail(initials, name, logo, colorH5, pathWord, count);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ThemeDetail)) {
            return false;
        }
        ThemeDetail themeDetail = (ThemeDetail) other;
        return this.initials == themeDetail.initials && Intrinsics.areEqual(this.name, themeDetail.name) && Intrinsics.areEqual(this.logo, themeDetail.logo) && Intrinsics.areEqual(this.colorH5, themeDetail.colorH5) && Intrinsics.areEqual(this.pathWord, themeDetail.pathWord) && this.count == themeDetail.count;
    }

    public int hashCode() {
        int iHashCode = ((this.initials * 31) + this.name.hashCode()) * 31;
        String str = this.logo;
        int iHashCode2 = (iHashCode + (str == null ? 0 : str.hashCode())) * 31;
        String str2 = this.colorH5;
        return ((((iHashCode2 + (str2 != null ? str2.hashCode() : 0)) * 31) + this.pathWord.hashCode()) * 31) + this.count;
    }

    public String toString() {
        return "ThemeDetail(initials=" + this.initials + ", name=" + this.name + ", logo=" + this.logo + ", colorH5=" + this.colorH5 + ", pathWord=" + this.pathWord + ", count=" + this.count + ')';
    }

    /* compiled from: TagResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ThemeDetail$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ThemeDetail;", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<ThemeDetail> serializer() {
            return ThemeDetail$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ ThemeDetail(int i, int i2, String str, String str2, @SerialName("color_h5") String str3, @SerialName("path_word") String str4, int i3, SerializationConstructorMarker serializationConstructorMarker) {
        if (51 != (i & 51)) {
            PluginExceptionsKt.throwMissingFieldException(i, 51, ThemeDetail$$serializer.INSTANCE.getDescriptor());
        }
        this.initials = i2;
        this.name = str;
        if ((i & 4) == 0) {
            this.logo = null;
        } else {
            this.logo = str2;
        }
        if ((i & 8) == 0) {
            this.colorH5 = null;
        } else {
            this.colorH5 = str3;
        }
        this.pathWord = str4;
        this.count = i3;
    }

    public ThemeDetail(int i, String str, String str2, String str3, String str4, int i2) {
        Intrinsics.checkNotNullParameter(str, "name");
        Intrinsics.checkNotNullParameter(str4, "pathWord");
        this.initials = i;
        this.name = str;
        this.logo = str2;
        this.colorH5 = str3;
        this.pathWord = str4;
        this.count = i2;
    }

    @JvmStatic
    public static final void write$Self(ThemeDetail self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeIntElement(serialDesc, 0, self.initials);
        output.encodeStringElement(serialDesc, 1, self.name);
        if (output.shouldEncodeElementDefault(serialDesc, 2) || self.logo != null) {
            output.encodeNullableSerializableElement(serialDesc, 2, StringSerializer.INSTANCE, self.logo);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 3) || self.colorH5 != null) {
            output.encodeNullableSerializableElement(serialDesc, 3, StringSerializer.INSTANCE, self.colorH5);
        }
        output.encodeStringElement(serialDesc, 4, self.pathWord);
        output.encodeIntElement(serialDesc, 5, self.count);
    }

    public /* synthetic */ ThemeDetail(int i, String str, String str2, String str3, String str4, int i2, int i3, DefaultConstructorMarker defaultConstructorMarker) {
        this(i, str, (i3 & 4) != 0 ? null : str2, (i3 & 8) != 0 ? null : str3, str4, i2);
    }

    public final int getInitials() {
        return this.initials;
    }

    public final String getName() {
        return this.name;
    }

    public final String getLogo() {
        return this.logo;
    }

    public final String getColorH5() {
        return this.colorH5;
    }

    public final String getPathWord() {
        return this.pathWord;
    }

    public final int getCount() {
        return this.count;
    }
}
