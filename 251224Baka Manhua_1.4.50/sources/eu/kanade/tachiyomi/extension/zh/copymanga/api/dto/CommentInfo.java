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

/* compiled from: CommentResult.kt */
@Metadata(d1 = {"\u0000@\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0006\n\u0002\u0018\u0002\n\u0002\b\u001a\n\u0002\u0010\u000b\n\u0002\b\u0004\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 42\u00020\u0001:\u000234Bg\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\n\b\u0001\u0010\u0005\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\u0007\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\b\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\t\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\n\u001a\u0004\u0018\u00010\u0006\u0012\b\u0010\u000b\u001a\u0004\u0018\u00010\u0006\u0012\b\u0010\f\u001a\u0004\u0018\u00010\r¢\u0006\u0002\u0010\u000eBA\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0006\u0012\u0006\u0010\u0007\u001a\u00020\u0006\u0012\u0006\u0010\b\u001a\u00020\u0006\u0012\u0006\u0010\t\u001a\u00020\u0006\u0012\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u0006\u0012\u0006\u0010\u000b\u001a\u00020\u0006¢\u0006\u0002\u0010\u000fJ\t\u0010\u001f\u001a\u00020\u0003HÆ\u0003J\t\u0010 \u001a\u00020\u0006HÆ\u0003J\t\u0010!\u001a\u00020\u0006HÆ\u0003J\t\u0010\"\u001a\u00020\u0006HÆ\u0003J\t\u0010#\u001a\u00020\u0006HÆ\u0003J\u000b\u0010$\u001a\u0004\u0018\u00010\u0006HÆ\u0003J\t\u0010%\u001a\u00020\u0006HÆ\u0003JQ\u0010&\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00062\b\b\u0002\u0010\u0007\u001a\u00020\u00062\b\b\u0002\u0010\b\u001a\u00020\u00062\b\b\u0002\u0010\t\u001a\u00020\u00062\n\b\u0002\u0010\n\u001a\u0004\u0018\u00010\u00062\b\b\u0002\u0010\u000b\u001a\u00020\u0006HÆ\u0001J\u0013\u0010'\u001a\u00020(2\b\u0010)\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010*\u001a\u00020\u0003HÖ\u0001J\t\u0010+\u001a\u00020\u0006HÖ\u0001J!\u0010,\u001a\u00020-2\u0006\u0010.\u001a\u00020\u00002\u0006\u0010/\u001a\u0002002\u0006\u00101\u001a\u000202HÇ\u0001R\u0011\u0010\u000b\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u0011R\u001c\u0010\u0005\u001a\u00020\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0012\u0010\u0013\u001a\u0004\b\u0014\u0010\u0011R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0015\u0010\u0016R\u001e\u0010\n\u001a\u0004\u0018\u00010\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0017\u0010\u0013\u001a\u0004\b\u0018\u0010\u0011R\u001c\u0010\t\u001a\u00020\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0019\u0010\u0013\u001a\u0004\b\u001a\u0010\u0011R\u001c\u0010\u0007\u001a\u00020\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001b\u0010\u0013\u001a\u0004\b\u001c\u0010\u0011R\u001c\u0010\b\u001a\u00020\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001d\u0010\u0013\u001a\u0004\b\u001e\u0010\u0011¨\u00065"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CommentInfo;", "", "seen1", "", "id", "createdAt", "", "userId", "userName", "userAvatar", "parentUserName", "comment", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(IILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", "getComment", "()Ljava/lang/String;", "getCreatedAt$annotations", "()V", "getCreatedAt", "getId", "()I", "getParentUserName$annotations", "getParentUserName", "getUserAvatar$annotations", "getUserAvatar", "getUserId$annotations", "getUserId", "getUserName$annotations", "getUserName", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "copy", "equals", "", "other", "hashCode", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
/* loaded from: classes.dex */
public final /* data */ class CommentInfo {

    /* renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final String comment;
    private final String createdAt;
    private final int id;
    private final String parentUserName;
    private final String userAvatar;
    private final String userId;
    private final String userName;

    public static /* synthetic */ CommentInfo copy$default(CommentInfo commentInfo, int i, String str, String str2, String str3, String str4, String str5, String str6, int i2, Object obj) {
        if ((i2 & 1) != 0) {
            i = commentInfo.id;
        }
        if ((i2 & 2) != 0) {
            str = commentInfo.createdAt;
        }
        String str7 = str;
        if ((i2 & 4) != 0) {
            str2 = commentInfo.userId;
        }
        String str8 = str2;
        if ((i2 & 8) != 0) {
            str3 = commentInfo.userName;
        }
        String str9 = str3;
        if ((i2 & 16) != 0) {
            str4 = commentInfo.userAvatar;
        }
        String str10 = str4;
        if ((i2 & 32) != 0) {
            str5 = commentInfo.parentUserName;
        }
        String str11 = str5;
        if ((i2 & 64) != 0) {
            str6 = commentInfo.comment;
        }
        return commentInfo.copy(i, str7, str8, str9, str10, str11, str6);
    }

    @SerialName("create_at")
    public static /* synthetic */ void getCreatedAt$annotations() {
    }

    @SerialName("parent_user_name")
    public static /* synthetic */ void getParentUserName$annotations() {
    }

    @SerialName("user_avatar")
    public static /* synthetic */ void getUserAvatar$annotations() {
    }

    @SerialName("user_id")
    public static /* synthetic */ void getUserId$annotations() {
    }

    @SerialName("user_name")
    public static /* synthetic */ void getUserName$annotations() {
    }

    /* renamed from: component1, reason: from getter */
    public final int getId() {
        return this.id;
    }

    /* renamed from: component2, reason: from getter */
    public final String getCreatedAt() {
        return this.createdAt;
    }

    /* renamed from: component3, reason: from getter */
    public final String getUserId() {
        return this.userId;
    }

    /* renamed from: component4, reason: from getter */
    public final String getUserName() {
        return this.userName;
    }

    /* renamed from: component5, reason: from getter */
    public final String getUserAvatar() {
        return this.userAvatar;
    }

    /* renamed from: component6, reason: from getter */
    public final String getParentUserName() {
        return this.parentUserName;
    }

    /* renamed from: component7, reason: from getter */
    public final String getComment() {
        return this.comment;
    }

    public final CommentInfo copy(int id, String createdAt, String userId, String userName, String userAvatar, String parentUserName, String comment) {
        Intrinsics.checkNotNullParameter(createdAt, "createdAt");
        Intrinsics.checkNotNullParameter(userId, "userId");
        Intrinsics.checkNotNullParameter(userName, "userName");
        Intrinsics.checkNotNullParameter(userAvatar, "userAvatar");
        Intrinsics.checkNotNullParameter(comment, "comment");
        return new CommentInfo(id, createdAt, userId, userName, userAvatar, parentUserName, comment);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof CommentInfo)) {
            return false;
        }
        CommentInfo commentInfo = (CommentInfo) other;
        return this.id == commentInfo.id && Intrinsics.areEqual(this.createdAt, commentInfo.createdAt) && Intrinsics.areEqual(this.userId, commentInfo.userId) && Intrinsics.areEqual(this.userName, commentInfo.userName) && Intrinsics.areEqual(this.userAvatar, commentInfo.userAvatar) && Intrinsics.areEqual(this.parentUserName, commentInfo.parentUserName) && Intrinsics.areEqual(this.comment, commentInfo.comment);
    }

    public int hashCode() {
        int iHashCode = ((((((((this.id * 31) + this.createdAt.hashCode()) * 31) + this.userId.hashCode()) * 31) + this.userName.hashCode()) * 31) + this.userAvatar.hashCode()) * 31;
        String str = this.parentUserName;
        return ((iHashCode + (str == null ? 0 : str.hashCode())) * 31) + this.comment.hashCode();
    }

    public String toString() {
        return "CommentInfo(id=" + this.id + ", createdAt=" + this.createdAt + ", userId=" + this.userId + ", userName=" + this.userName + ", userAvatar=" + this.userAvatar + ", parentUserName=" + this.parentUserName + ", comment=" + this.comment + ')';
    }

    /* compiled from: CommentResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CommentInfo$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CommentInfo;", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<CommentInfo> serializer() {
            return CommentInfo$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ CommentInfo(int i, int i2, @SerialName("create_at") String str, @SerialName("user_id") String str2, @SerialName("user_name") String str3, @SerialName("user_avatar") String str4, @SerialName("parent_user_name") String str5, String str6, SerializationConstructorMarker serializationConstructorMarker) {
        if (95 != (i & 95)) {
            PluginExceptionsKt.throwMissingFieldException(i, 95, CommentInfo$$serializer.INSTANCE.getDescriptor());
        }
        this.id = i2;
        this.createdAt = str;
        this.userId = str2;
        this.userName = str3;
        this.userAvatar = str4;
        if ((i & 32) == 0) {
            this.parentUserName = null;
        } else {
            this.parentUserName = str5;
        }
        this.comment = str6;
    }

    public CommentInfo(int i, String str, String str2, String str3, String str4, String str5, String str6) {
        Intrinsics.checkNotNullParameter(str, "createdAt");
        Intrinsics.checkNotNullParameter(str2, "userId");
        Intrinsics.checkNotNullParameter(str3, "userName");
        Intrinsics.checkNotNullParameter(str4, "userAvatar");
        Intrinsics.checkNotNullParameter(str6, "comment");
        this.id = i;
        this.createdAt = str;
        this.userId = str2;
        this.userName = str3;
        this.userAvatar = str4;
        this.parentUserName = str5;
        this.comment = str6;
    }

    @JvmStatic
    public static final void write$Self(CommentInfo self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeIntElement(serialDesc, 0, self.id);
        output.encodeStringElement(serialDesc, 1, self.createdAt);
        output.encodeStringElement(serialDesc, 2, self.userId);
        output.encodeStringElement(serialDesc, 3, self.userName);
        output.encodeStringElement(serialDesc, 4, self.userAvatar);
        if (output.shouldEncodeElementDefault(serialDesc, 5) || self.parentUserName != null) {
            output.encodeNullableSerializableElement(serialDesc, 5, StringSerializer.INSTANCE, self.parentUserName);
        }
        output.encodeStringElement(serialDesc, 6, self.comment);
    }

    public /* synthetic */ CommentInfo(int i, String str, String str2, String str3, String str4, String str5, String str6, int i2, DefaultConstructorMarker defaultConstructorMarker) {
        this(i, str, str2, str3, str4, (i2 & 32) != 0 ? null : str5, str6);
    }

    public final int getId() {
        return this.id;
    }

    public final String getCreatedAt() {
        return this.createdAt;
    }

    public final String getUserId() {
        return this.userId;
    }

    public final String getUserName() {
        return this.userName;
    }

    public final String getUserAvatar() {
        return this.userAvatar;
    }

    public final String getParentUserName() {
        return this.parentUserName;
    }

    public final String getComment() {
        return this.comment;
    }
}
