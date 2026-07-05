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
import kotlinx.serialization.internal.BooleanSerializer;
import kotlinx.serialization.internal.DoubleSerializer;
import kotlinx.serialization.internal.IntSerializer;
import kotlinx.serialization.internal.PluginExceptionsKt;
import kotlinx.serialization.internal.SerializationConstructorMarker;
import kotlinx.serialization.internal.StringSerializer;

/* JADX INFO: compiled from: LoginResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000D\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0006\n\u0002\u0010\u0006\n\u0002\b\t\n\u0002\u0010\u000b\n\u0000\n\u0002\u0018\u0002\n\u0002\b:\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 Z2\u00020\u0001:\u0002YZBË\u0001\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\b\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\n\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u000b\u001a\u0004\u0018\u00010\f\u0012\n\b\u0001\u0010\r\u001a\u0004\u0018\u00010\f\u0012\n\b\u0001\u0010\u000e\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\u000f\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0010\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0001\u0010\u0011\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0001\u0010\u0012\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0001\u0010\u0013\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0014\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\u0015\u001a\u0004\u0018\u00010\u0016\u0012\b\u0010\u0017\u001a\u0004\u0018\u00010\u0018¢\u0006\u0002\u0010\u0019B\u00ad\u0001\u0012\u0006\u0010\u0004\u001a\u00020\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0005\u0012\u0006\u0010\u0007\u001a\u00020\u0005\u0012\u0006\u0010\b\u001a\u00020\u0005\u0012\u0006\u0010\t\u001a\u00020\u0005\u0012\u0006\u0010\n\u001a\u00020\u0005\u0012\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\f\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\f\u0012\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0013\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0015\u001a\u0004\u0018\u00010\u0016¢\u0006\u0002\u0010\u001aJ\t\u0010<\u001a\u00020\u0005HÆ\u0003J\u000b\u0010=\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010>\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010#J\u0010\u0010?\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010#J\u0010\u0010@\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010#J\u000b\u0010A\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u000b\u0010B\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\u0010\u0010C\u001a\u0004\u0018\u00010\u0016HÆ\u0003¢\u0006\u0002\u00103J\t\u0010D\u001a\u00020\u0005HÆ\u0003J\t\u0010E\u001a\u00020\u0005HÆ\u0003J\t\u0010F\u001a\u00020\u0005HÆ\u0003J\t\u0010G\u001a\u00020\u0005HÆ\u0003J\t\u0010H\u001a\u00020\u0005HÆ\u0003J\u0010\u0010I\u001a\u0004\u0018\u00010\fHÆ\u0003¢\u0006\u0002\u0010/J\u0010\u0010J\u001a\u0004\u0018\u00010\fHÆ\u0003¢\u0006\u0002\u0010/J\u000b\u0010K\u001a\u0004\u0018\u00010\u0005HÆ\u0003JÂ\u0001\u0010L\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00052\b\b\u0002\u0010\u0006\u001a\u00020\u00052\b\b\u0002\u0010\u0007\u001a\u00020\u00052\b\b\u0002\u0010\b\u001a\u00020\u00052\b\b\u0002\u0010\t\u001a\u00020\u00052\b\b\u0002\u0010\n\u001a\u00020\u00052\n\b\u0002\u0010\u000b\u001a\u0004\u0018\u00010\f2\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\f2\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0013\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0015\u001a\u0004\u0018\u00010\u0016HÆ\u0001¢\u0006\u0002\u0010MJ\u0013\u0010N\u001a\u00020\u00162\b\u0010O\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010P\u001a\u00020\u0003HÖ\u0001J\t\u0010Q\u001a\u00020\u0005HÖ\u0001J!\u0010R\u001a\u00020S2\u0006\u0010T\u001a\u00020\u00002\u0006\u0010U\u001a\u00020V2\u0006\u0010W\u001a\u00020XHÇ\u0001R\u001e\u0010\u000e\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001b\u0010\u001c\u001a\u0004\b\u001d\u0010\u001eR\u0011\u0010\t\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u001f\u0010\u001eR\u001c\u0010\n\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b \u0010\u001c\u001a\u0004\b!\u0010\u001eR\u0015\u0010\u0010\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010$\u001a\u0004\b\"\u0010#R\u001e\u0010\u0013\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b%\u0010\u001c\u001a\u0004\b&\u0010\u001eR\u0013\u0010\u0014\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b'\u0010\u001eR\u0011\u0010\b\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b(\u0010\u001eR\u001e\u0010\u000f\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b)\u0010\u001c\u001a\u0004\b*\u0010\u001eR \u0010\u0012\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\u0010\n\u0002\u0010$\u0012\u0004\b+\u0010\u001c\u001a\u0004\b,\u0010#R \u0010\r\u001a\u0004\u0018\u00010\f8\u0006X\u0087\u0004¢\u0006\u0010\n\u0002\u00100\u0012\u0004\b-\u0010\u001c\u001a\u0004\b.\u0010/R \u0010\u0015\u001a\u0004\u0018\u00010\u00168\u0006X\u0087\u0004¢\u0006\u0010\n\u0002\u00104\u0012\u0004\b1\u0010\u001c\u001a\u0004\b2\u00103R\u0015\u0010\u000b\u001a\u0004\u0018\u00010\f¢\u0006\n\n\u0002\u00100\u001a\u0004\b5\u0010/R\u0011\u0010\u0004\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b6\u0010\u001eR\u001c\u0010\u0006\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b7\u0010\u001c\u001a\u0004\b8\u0010\u001eR\u0011\u0010\u0007\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b9\u0010\u001eR \u0010\u0011\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\u0010\n\u0002\u0010$\u0012\u0004\b:\u0010\u001c\u001a\u0004\b;\u0010#¨\u0006["}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/LoginResult;", "", "seen1", "", "token", "", "userId", "username", "nickname", "avatar", "datetimeCreated", "ticket", "", "rewardTicket", "adsVipEnd", "postVipEnd", "downloads", "vipDownloads", "rewardDownloads", "inviteCode", "invited", "scyAnswer", "", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Double;Ljava/lang/Double;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Boolean;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Double;Ljava/lang/Double;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Boolean;)V", "getAdsVipEnd$annotations", "()V", "getAdsVipEnd", "()Ljava/lang/String;", "getAvatar", "getDatetimeCreated$annotations", "getDatetimeCreated", "getDownloads", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getInviteCode$annotations", "getInviteCode", "getInvited", "getNickname", "getPostVipEnd$annotations", "getPostVipEnd", "getRewardDownloads$annotations", "getRewardDownloads", "getRewardTicket$annotations", "getRewardTicket", "()Ljava/lang/Double;", "Ljava/lang/Double;", "getScyAnswer$annotations", "getScyAnswer", "()Ljava/lang/Boolean;", "Ljava/lang/Boolean;", "getTicket", "getToken", "getUserId$annotations", "getUserId", "getUsername", "getVipDownloads$annotations", "getVipDownloads", "component1", "component10", "component11", "component12", "component13", "component14", "component15", "component16", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "copy", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Double;Ljava/lang/Double;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Boolean;)Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/LoginResult;", "equals", "other", "hashCode", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
public final /* data */ class LoginResult {

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final String adsVipEnd;
    private final String avatar;
    private final String datetimeCreated;
    private final Integer downloads;
    private final String inviteCode;
    private final String invited;
    private final String nickname;
    private final String postVipEnd;
    private final Integer rewardDownloads;
    private final Double rewardTicket;
    private final Boolean scyAnswer;
    private final Double ticket;
    private final String token;
    private final String userId;
    private final String username;
    private final Integer vipDownloads;

    @SerialName("ads_vip_end")
    public static /* synthetic */ void getAdsVipEnd$annotations() {
    }

    @SerialName("datetime_created")
    public static /* synthetic */ void getDatetimeCreated$annotations() {
    }

    @SerialName("invite_code")
    public static /* synthetic */ void getInviteCode$annotations() {
    }

    @SerialName("post_vip_end")
    public static /* synthetic */ void getPostVipEnd$annotations() {
    }

    @SerialName("reward_downloads")
    public static /* synthetic */ void getRewardDownloads$annotations() {
    }

    @SerialName("reward_ticket")
    public static /* synthetic */ void getRewardTicket$annotations() {
    }

    @SerialName("scy_answer")
    public static /* synthetic */ void getScyAnswer$annotations() {
    }

    @SerialName("user_id")
    public static /* synthetic */ void getUserId$annotations() {
    }

    @SerialName("vip_downloads")
    public static /* synthetic */ void getVipDownloads$annotations() {
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getToken() {
        return this.token;
    }

    /* JADX INFO: renamed from: component10, reason: from getter */
    public final String getPostVipEnd() {
        return this.postVipEnd;
    }

    /* JADX INFO: renamed from: component11, reason: from getter */
    public final Integer getDownloads() {
        return this.downloads;
    }

    /* JADX INFO: renamed from: component12, reason: from getter */
    public final Integer getVipDownloads() {
        return this.vipDownloads;
    }

    /* JADX INFO: renamed from: component13, reason: from getter */
    public final Integer getRewardDownloads() {
        return this.rewardDownloads;
    }

    /* JADX INFO: renamed from: component14, reason: from getter */
    public final String getInviteCode() {
        return this.inviteCode;
    }

    /* JADX INFO: renamed from: component15, reason: from getter */
    public final String getInvited() {
        return this.invited;
    }

    /* JADX INFO: renamed from: component16, reason: from getter */
    public final Boolean getScyAnswer() {
        return this.scyAnswer;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getUserId() {
        return this.userId;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getUsername() {
        return this.username;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getNickname() {
        return this.nickname;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final String getAvatar() {
        return this.avatar;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final String getDatetimeCreated() {
        return this.datetimeCreated;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final Double getTicket() {
        return this.ticket;
    }

    /* JADX INFO: renamed from: component8, reason: from getter */
    public final Double getRewardTicket() {
        return this.rewardTicket;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final String getAdsVipEnd() {
        return this.adsVipEnd;
    }

    public final LoginResult copy(String token, String userId, String username, String nickname, String avatar, String datetimeCreated, Double ticket, Double rewardTicket, String adsVipEnd, String postVipEnd, Integer downloads, Integer vipDownloads, Integer rewardDownloads, String inviteCode, String invited, Boolean scyAnswer) {
        Intrinsics.checkNotNullParameter(token, "token");
        Intrinsics.checkNotNullParameter(userId, "userId");
        Intrinsics.checkNotNullParameter(username, "username");
        Intrinsics.checkNotNullParameter(nickname, "nickname");
        Intrinsics.checkNotNullParameter(avatar, "avatar");
        Intrinsics.checkNotNullParameter(datetimeCreated, "datetimeCreated");
        return new LoginResult(token, userId, username, nickname, avatar, datetimeCreated, ticket, rewardTicket, adsVipEnd, postVipEnd, downloads, vipDownloads, rewardDownloads, inviteCode, invited, scyAnswer);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof LoginResult)) {
            return false;
        }
        LoginResult loginResult = (LoginResult) other;
        return Intrinsics.areEqual(this.token, loginResult.token) && Intrinsics.areEqual(this.userId, loginResult.userId) && Intrinsics.areEqual(this.username, loginResult.username) && Intrinsics.areEqual(this.nickname, loginResult.nickname) && Intrinsics.areEqual(this.avatar, loginResult.avatar) && Intrinsics.areEqual(this.datetimeCreated, loginResult.datetimeCreated) && Intrinsics.areEqual(this.ticket, loginResult.ticket) && Intrinsics.areEqual(this.rewardTicket, loginResult.rewardTicket) && Intrinsics.areEqual(this.adsVipEnd, loginResult.adsVipEnd) && Intrinsics.areEqual(this.postVipEnd, loginResult.postVipEnd) && Intrinsics.areEqual(this.downloads, loginResult.downloads) && Intrinsics.areEqual(this.vipDownloads, loginResult.vipDownloads) && Intrinsics.areEqual(this.rewardDownloads, loginResult.rewardDownloads) && Intrinsics.areEqual(this.inviteCode, loginResult.inviteCode) && Intrinsics.areEqual(this.invited, loginResult.invited) && Intrinsics.areEqual(this.scyAnswer, loginResult.scyAnswer);
    }

    public int hashCode() {
        int iHashCode = ((((((((((this.token.hashCode() * 31) + this.userId.hashCode()) * 31) + this.username.hashCode()) * 31) + this.nickname.hashCode()) * 31) + this.avatar.hashCode()) * 31) + this.datetimeCreated.hashCode()) * 31;
        Double d = this.ticket;
        int iHashCode2 = (iHashCode + (d == null ? 0 : d.hashCode())) * 31;
        Double d2 = this.rewardTicket;
        int iHashCode3 = (iHashCode2 + (d2 == null ? 0 : d2.hashCode())) * 31;
        String str = this.adsVipEnd;
        int iHashCode4 = (iHashCode3 + (str == null ? 0 : str.hashCode())) * 31;
        String str2 = this.postVipEnd;
        int iHashCode5 = (iHashCode4 + (str2 == null ? 0 : str2.hashCode())) * 31;
        Integer num = this.downloads;
        int iHashCode6 = (iHashCode5 + (num == null ? 0 : num.hashCode())) * 31;
        Integer num2 = this.vipDownloads;
        int iHashCode7 = (iHashCode6 + (num2 == null ? 0 : num2.hashCode())) * 31;
        Integer num3 = this.rewardDownloads;
        int iHashCode8 = (iHashCode7 + (num3 == null ? 0 : num3.hashCode())) * 31;
        String str3 = this.inviteCode;
        int iHashCode9 = (iHashCode8 + (str3 == null ? 0 : str3.hashCode())) * 31;
        String str4 = this.invited;
        int iHashCode10 = (iHashCode9 + (str4 == null ? 0 : str4.hashCode())) * 31;
        Boolean bool = this.scyAnswer;
        return iHashCode10 + (bool != null ? bool.hashCode() : 0);
    }

    public String toString() {
        return "LoginResult(token=" + this.token + ", userId=" + this.userId + ", username=" + this.username + ", nickname=" + this.nickname + ", avatar=" + this.avatar + ", datetimeCreated=" + this.datetimeCreated + ", ticket=" + this.ticket + ", rewardTicket=" + this.rewardTicket + ", adsVipEnd=" + this.adsVipEnd + ", postVipEnd=" + this.postVipEnd + ", downloads=" + this.downloads + ", vipDownloads=" + this.vipDownloads + ", rewardDownloads=" + this.rewardDownloads + ", inviteCode=" + this.inviteCode + ", invited=" + this.invited + ", scyAnswer=" + this.scyAnswer + ')';
    }

    /* JADX INFO: compiled from: LoginResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/LoginResult$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/LoginResult;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<LoginResult> serializer() {
            return LoginResult$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ LoginResult(int i, String str, @SerialName("user_id") String str2, String str3, String str4, String str5, @SerialName("datetime_created") String str6, Double d, @SerialName("reward_ticket") Double d2, @SerialName("ads_vip_end") String str7, @SerialName("post_vip_end") String str8, Integer num, @SerialName("vip_downloads") Integer num2, @SerialName("reward_downloads") Integer num3, @SerialName("invite_code") String str9, String str10, @SerialName("scy_answer") Boolean bool, SerializationConstructorMarker serializationConstructorMarker) {
        if (63 != (i & 63)) {
            PluginExceptionsKt.throwMissingFieldException(i, 63, LoginResult$$serializer.INSTANCE.getDescriptor());
        }
        this.token = str;
        this.userId = str2;
        this.username = str3;
        this.nickname = str4;
        this.avatar = str5;
        this.datetimeCreated = str6;
        if ((i & 64) == 0) {
            this.ticket = null;
        } else {
            this.ticket = d;
        }
        if ((i & 128) == 0) {
            this.rewardTicket = null;
        } else {
            this.rewardTicket = d2;
        }
        if ((i & 256) == 0) {
            this.adsVipEnd = null;
        } else {
            this.adsVipEnd = str7;
        }
        if ((i & 512) == 0) {
            this.postVipEnd = null;
        } else {
            this.postVipEnd = str8;
        }
        if ((i & 1024) == 0) {
            this.downloads = null;
        } else {
            this.downloads = num;
        }
        if ((i & 2048) == 0) {
            this.vipDownloads = null;
        } else {
            this.vipDownloads = num2;
        }
        if ((i & 4096) == 0) {
            this.rewardDownloads = null;
        } else {
            this.rewardDownloads = num3;
        }
        if ((i & 8192) == 0) {
            this.inviteCode = null;
        } else {
            this.inviteCode = str9;
        }
        if ((i & 16384) == 0) {
            this.invited = null;
        } else {
            this.invited = str10;
        }
        if ((i & 32768) == 0) {
            this.scyAnswer = null;
        } else {
            this.scyAnswer = bool;
        }
    }

    public LoginResult(String str, String str2, String str3, String str4, String str5, String str6, Double d, Double d2, String str7, String str8, Integer num, Integer num2, Integer num3, String str9, String str10, Boolean bool) {
        Intrinsics.checkNotNullParameter(str, "token");
        Intrinsics.checkNotNullParameter(str2, "userId");
        Intrinsics.checkNotNullParameter(str3, "username");
        Intrinsics.checkNotNullParameter(str4, "nickname");
        Intrinsics.checkNotNullParameter(str5, "avatar");
        Intrinsics.checkNotNullParameter(str6, "datetimeCreated");
        this.token = str;
        this.userId = str2;
        this.username = str3;
        this.nickname = str4;
        this.avatar = str5;
        this.datetimeCreated = str6;
        this.ticket = d;
        this.rewardTicket = d2;
        this.adsVipEnd = str7;
        this.postVipEnd = str8;
        this.downloads = num;
        this.vipDownloads = num2;
        this.rewardDownloads = num3;
        this.inviteCode = str9;
        this.invited = str10;
        this.scyAnswer = bool;
    }

    @JvmStatic
    public static final void write$Self(LoginResult self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeStringElement(serialDesc, 0, self.token);
        output.encodeStringElement(serialDesc, 1, self.userId);
        output.encodeStringElement(serialDesc, 2, self.username);
        output.encodeStringElement(serialDesc, 3, self.nickname);
        output.encodeStringElement(serialDesc, 4, self.avatar);
        output.encodeStringElement(serialDesc, 5, self.datetimeCreated);
        if (output.shouldEncodeElementDefault(serialDesc, 6) || self.ticket != null) {
            output.encodeNullableSerializableElement(serialDesc, 6, DoubleSerializer.INSTANCE, self.ticket);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 7) || self.rewardTicket != null) {
            output.encodeNullableSerializableElement(serialDesc, 7, DoubleSerializer.INSTANCE, self.rewardTicket);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 8) || self.adsVipEnd != null) {
            output.encodeNullableSerializableElement(serialDesc, 8, StringSerializer.INSTANCE, self.adsVipEnd);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 9) || self.postVipEnd != null) {
            output.encodeNullableSerializableElement(serialDesc, 9, StringSerializer.INSTANCE, self.postVipEnd);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 10) || self.downloads != null) {
            output.encodeNullableSerializableElement(serialDesc, 10, IntSerializer.INSTANCE, self.downloads);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 11) || self.vipDownloads != null) {
            output.encodeNullableSerializableElement(serialDesc, 11, IntSerializer.INSTANCE, self.vipDownloads);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 12) || self.rewardDownloads != null) {
            output.encodeNullableSerializableElement(serialDesc, 12, IntSerializer.INSTANCE, self.rewardDownloads);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 13) || self.inviteCode != null) {
            output.encodeNullableSerializableElement(serialDesc, 13, StringSerializer.INSTANCE, self.inviteCode);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 14) || self.invited != null) {
            output.encodeNullableSerializableElement(serialDesc, 14, StringSerializer.INSTANCE, self.invited);
        }
        if (!output.shouldEncodeElementDefault(serialDesc, 15) && self.scyAnswer == null) {
            return;
        }
        output.encodeNullableSerializableElement(serialDesc, 15, BooleanSerializer.INSTANCE, self.scyAnswer);
    }

    public /* synthetic */ LoginResult(String str, String str2, String str3, String str4, String str5, String str6, Double d, Double d2, String str7, String str8, Integer num, Integer num2, Integer num3, String str9, String str10, Boolean bool, int i, DefaultConstructorMarker defaultConstructorMarker) {
        this(str, str2, str3, str4, str5, str6, (i & 64) != 0 ? null : d, (i & 128) != 0 ? null : d2, (i & 256) != 0 ? null : str7, (i & 512) != 0 ? null : str8, (i & 1024) != 0 ? null : num, (i & 2048) != 0 ? null : num2, (i & 4096) != 0 ? null : num3, (i & 8192) != 0 ? null : str9, (i & 16384) != 0 ? null : str10, (i & 32768) != 0 ? null : bool);
    }

    public final String getToken() {
        return this.token;
    }

    public final String getUserId() {
        return this.userId;
    }

    public final String getUsername() {
        return this.username;
    }

    public final String getNickname() {
        return this.nickname;
    }

    public final String getAvatar() {
        return this.avatar;
    }

    public final String getDatetimeCreated() {
        return this.datetimeCreated;
    }

    public final Double getTicket() {
        return this.ticket;
    }

    public final Double getRewardTicket() {
        return this.rewardTicket;
    }

    public final String getAdsVipEnd() {
        return this.adsVipEnd;
    }

    public final String getPostVipEnd() {
        return this.postVipEnd;
    }

    public final Integer getDownloads() {
        return this.downloads;
    }

    public final Integer getVipDownloads() {
        return this.vipDownloads;
    }

    public final Integer getRewardDownloads() {
        return this.rewardDownloads;
    }

    public final String getInviteCode() {
        return this.inviteCode;
    }

    public final String getInvited() {
        return this.invited;
    }

    public final Boolean getScyAnswer() {
        return this.scyAnswer;
    }
}
