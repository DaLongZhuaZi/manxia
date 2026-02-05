package eu.kanade.tachiyomi.extension.zh.copymanga.api.dto;

import eu.kanade.tachiyomi.extension.zh.copymanga.CCOption;
import eu.kanade.tachiyomi.extension.zh.copymanga.MangaStatusManager;
import eu.kanade.tachiyomi.extension.zh.copymanga.ResolutionOption;
import eu.kanade.tachiyomi.extension.zh.copymanga.language.TranslateKt;
import eu.kanade.tachiyomi.source.model.SManga;
import java.util.List;
import kotlin.Deprecated;
import kotlin.DeprecationLevel;
import kotlin.Metadata;
import kotlin.ReplaceWith;
import kotlin.collections.CollectionsKt;
import kotlin.jvm.JvmStatic;
import kotlin.jvm.functions.Function1;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlin.jvm.internal.Reflection;
import kotlinx.serialization.ContextualSerializer;
import kotlinx.serialization.KSerializer;
import kotlinx.serialization.SerialName;
import kotlinx.serialization.Serializable;
import kotlinx.serialization.descriptors.SerialDescriptor;
import kotlinx.serialization.encoding.CompositeEncoder;
import kotlinx.serialization.internal.ArrayListSerializer;
import kotlinx.serialization.internal.PluginExceptionsKt;
import kotlinx.serialization.internal.SerializationConstructorMarker;
import kotlinx.serialization.internal.StringSerializer;
import kotlinx.serialization.json.JsonElement;
import kotlinx.serialization.json.JsonElementSerializer;

/* compiled from: ComicDetailResult.kt */
@Metadata(d1 = {"\u0000\u0090\u0001\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u000b\n\u0002\b\b\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0004\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\bO\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 \u0089\u00012\u00020\u0001:\u0004\u0088\u0001\u0089\u0001BÛ\u0002\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\b\u0001\u0010\u0006\u001a\u00020\u0007\u0012\b\b\u0001\u0010\b\u001a\u00020\u0007\u0012\u0006\u0010\t\u001a\u00020\u0003\u0012\b\u0010\n\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u000b\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\f\u001a\u0004\u0018\u00010\u0005\u0012\b\b\u0001\u0010\r\u001a\u00020\u0007\u0012\b\b\u0001\u0010\u000e\u001a\u00020\u0007\u0012\n\b\u0001\u0010\u000f\u001a\u0004\u0018\u00010\u0010\u0012\b\u0010\u0011\u001a\u0004\u0018\u00010\u0012\u0012\b\u0010\u0013\u001a\u0004\u0018\u00010\u0014\u0012\u0013\u0010\u0015\u001a\u000f\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u0018\u0018\u00010\u0016\u0012\u0013\u0010\u0019\u001a\u000f\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u0018\u0018\u00010\u0016\u0012\u0013\u0010\u001a\u001a\u000f\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u0018\u0018\u00010\u0016\u0012\n\b\u0001\u0010\u001b\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u001c\u001a\u0004\u0018\u00010\u001d\u0012\b\u0010\u001e\u001a\u0004\u0018\u00010\u001f\u0012\u000e\u0010 \u001a\n\u0012\u0004\u0012\u00020!\u0018\u00010\u0016\u0012\u000e\u0010\"\u001a\n\u0012\u0004\u0012\u00020#\u0018\u00010\u0016\u0012\u0013\u0010$\u001a\u000f\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u0018\u0018\u00010\u0016\u0012\b\u0010%\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010&\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010'\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010(\u001a\u0004\u0018\u00010)\u0012\u0006\u0010*\u001a\u00020\u0003\u0012\b\u0010+\u001a\u0004\u0018\u00010,¢\u0006\u0002\u0010-B¡\u0002\u0012\u0006\u0010\u0004\u001a\u00020\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0007\u0012\u0006\u0010\b\u001a\u00020\u0007\u0012\u0006\u0010\t\u001a\u00020\u0003\u0012\u0006\u0010\n\u001a\u00020\u0005\u0012\b\b\u0002\u0010\u000b\u001a\u00020\u0005\u0012\u0006\u0010\f\u001a\u00020\u0005\u0012\u0006\u0010\r\u001a\u00020\u0007\u0012\u0006\u0010\u000e\u001a\u00020\u0007\u0012\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u0010\u0012\u0006\u0010\u0011\u001a\u00020\u0012\u0012\u0006\u0010\u0013\u001a\u00020\u0014\u0012\u0013\b\u0002\u0010\u0015\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u0016\u0012\u0013\b\u0002\u0010\u0019\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u0016\u0012\u0013\b\u0002\u0010\u001a\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u0016\u0012\u0006\u0010\u001b\u001a\u00020\u0005\u0012\u0006\u0010\u001c\u001a\u00020\u001d\u0012\u0006\u0010\u001e\u001a\u00020\u001f\u0012\f\u0010 \u001a\b\u0012\u0004\u0012\u00020!0\u0016\u0012\u000e\b\u0002\u0010\"\u001a\b\u0012\u0004\u0012\u00020#0\u0016\u0012\u0013\b\u0002\u0010$\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u0016\u0012\u0006\u0010%\u001a\u00020\u0005\u0012\n\b\u0002\u0010&\u001a\u0004\u0018\u00010\u0005\u0012\u0006\u0010'\u001a\u00020\u0005\u0012\u0006\u0010(\u001a\u00020)\u0012\u0006\u0010*\u001a\u00020\u0003¢\u0006\u0002\u0010.J\t\u0010]\u001a\u00020\u0005HÆ\u0003J\u000b\u0010^\u001a\u0004\u0018\u00010\u0010HÆ\u0003J\t\u0010_\u001a\u00020\u0012HÆ\u0003J\t\u0010`\u001a\u00020\u0014HÆ\u0003J\u0014\u0010a\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u0016HÆ\u0003J\u0014\u0010b\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u0016HÆ\u0003J\u0014\u0010c\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u0016HÆ\u0003J\t\u0010d\u001a\u00020\u0005HÆ\u0003J\t\u0010e\u001a\u00020\u001dHÆ\u0003J\t\u0010f\u001a\u00020\u001fHÆ\u0003J\u000f\u0010g\u001a\b\u0012\u0004\u0012\u00020!0\u0016HÆ\u0003J\t\u0010h\u001a\u00020\u0007HÆ\u0003J\u000f\u0010i\u001a\b\u0012\u0004\u0012\u00020#0\u0016HÆ\u0003J\u0014\u0010j\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u0016HÆ\u0003J\t\u0010k\u001a\u00020\u0005HÆ\u0003J\u000b\u0010l\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\t\u0010m\u001a\u00020\u0005HÆ\u0003J\t\u0010n\u001a\u00020)HÆ\u0003J\t\u0010o\u001a\u00020\u0003HÆ\u0003J\t\u0010p\u001a\u00020\u0007HÆ\u0003J\t\u0010q\u001a\u00020\u0003HÆ\u0003J\t\u0010r\u001a\u00020\u0005HÆ\u0003J\t\u0010s\u001a\u00020\u0005HÆ\u0003J\t\u0010t\u001a\u00020\u0005HÆ\u0003J\t\u0010u\u001a\u00020\u0007HÆ\u0003J\t\u0010v\u001a\u00020\u0007HÆ\u0003JÉ\u0002\u0010w\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00052\b\b\u0002\u0010\u0006\u001a\u00020\u00072\b\b\u0002\u0010\b\u001a\u00020\u00072\b\b\u0002\u0010\t\u001a\u00020\u00032\b\b\u0002\u0010\n\u001a\u00020\u00052\b\b\u0002\u0010\u000b\u001a\u00020\u00052\b\b\u0002\u0010\f\u001a\u00020\u00052\b\b\u0002\u0010\r\u001a\u00020\u00072\b\b\u0002\u0010\u000e\u001a\u00020\u00072\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u00102\b\b\u0002\u0010\u0011\u001a\u00020\u00122\b\b\u0002\u0010\u0013\u001a\u00020\u00142\u0013\b\u0002\u0010\u0015\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u00162\u0013\b\u0002\u0010\u0019\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u00162\u0013\b\u0002\u0010\u001a\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u00162\b\b\u0002\u0010\u001b\u001a\u00020\u00052\b\b\u0002\u0010\u001c\u001a\u00020\u001d2\b\b\u0002\u0010\u001e\u001a\u00020\u001f2\u000e\b\u0002\u0010 \u001a\b\u0012\u0004\u0012\u00020!0\u00162\u000e\b\u0002\u0010\"\u001a\b\u0012\u0004\u0012\u00020#0\u00162\u0013\b\u0002\u0010$\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u00162\b\b\u0002\u0010%\u001a\u00020\u00052\n\b\u0002\u0010&\u001a\u0004\u0018\u00010\u00052\b\b\u0002\u0010'\u001a\u00020\u00052\b\b\u0002\u0010(\u001a\u00020)2\b\b\u0002\u0010*\u001a\u00020\u0003HÆ\u0001J\u0013\u0010x\u001a\u00020\u00072\b\u0010y\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010z\u001a\u00020\u0003HÖ\u0001J\u0016\u0010{\u001a\u00020|2\u0006\u0010}\u001a\u00020\u00052\u0006\u0010~\u001a\u00020\u007fJ\n\u0010\u0080\u0001\u001a\u00020\u0005HÖ\u0001J(\u0010\u0081\u0001\u001a\u00030\u0082\u00012\u0007\u0010\u0083\u0001\u001a\u00020\u00002\b\u0010\u0084\u0001\u001a\u00030\u0085\u00012\b\u0010\u0086\u0001\u001a\u00030\u0087\u0001HÇ\u0001R\u0011\u0010\u000b\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b/\u00100R\u0017\u0010 \u001a\b\u0012\u0004\u0012\u00020!0\u0016¢\u0006\b\n\u0000\u001a\u0004\b1\u00102R\u001c\u0010\u0006\u001a\u00020\u00078\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b3\u00104\u001a\u0004\b5\u00106R\u001c\u0010\b\u001a\u00020\u00078\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b7\u00104\u001a\u0004\b8\u00106R\u0011\u0010\t\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b9\u0010:R\u0011\u0010%\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b;\u00100R\u001c\u0010\r\u001a\u00020\u00078\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b<\u00104\u001a\u0004\b=\u00106R\u001c\u0010\u000e\u001a\u00020\u00078\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b>\u00104\u001a\u0004\b?\u00106R\u001c\u0010\u001a\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u0016¢\u0006\b\n\u0000\u001a\u0004\b@\u00102R\u0011\u0010'\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\bA\u00100R\u001e\u0010&\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\bB\u00104\u001a\u0004\bC\u00100R\u001c\u0010\u0015\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u0016¢\u0006\b\n\u0000\u001a\u0004\bD\u00102R\u001e\u0010\u000f\u001a\u0004\u0018\u00010\u00108\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\bE\u00104\u001a\u0004\bF\u0010GR\u001c\u0010(\u001a\u00020)8\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\bH\u00104\u001a\u0004\bI\u0010JR\u001c\u0010\u0019\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u0016¢\u0006\b\n\u0000\u001a\u0004\bK\u00102R\u0011\u0010\n\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\bL\u00100R\u001c\u0010$\u001a\r\u0012\t\u0012\u00070\u0017¢\u0006\u0002\b\u00180\u0016¢\u0006\b\n\u0000\u001a\u0004\bM\u00102R\u001c\u0010\f\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\bN\u00104\u001a\u0004\bO\u00100R\u0011\u0010*\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\bP\u0010:R\u0011\u0010\u0013\u001a\u00020\u0014¢\u0006\b\n\u0000\u001a\u0004\bQ\u0010RR\u0011\u0010\u001c\u001a\u00020\u001d¢\u0006\b\n\u0000\u001a\u0004\bS\u0010TR\u0011\u0010\u0011\u001a\u00020\u0012¢\u0006\b\n\u0000\u001a\u0004\bU\u0010VR\u001c\u0010\u001b\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\bW\u00104\u001a\u0004\bX\u00100R\u0011\u0010\u001e\u001a\u00020\u001f¢\u0006\b\n\u0000\u001a\u0004\bY\u0010ZR\u0017\u0010\"\u001a\b\u0012\u0004\u0012\u00020#0\u0016¢\u0006\b\n\u0000\u001a\u0004\b[\u00102R\u0011\u0010\u0004\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\\\u00100¨\u0006\u008a\u0001"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicDetail;", "", "seen1", "", "uuid", "", "b404", "", "bHidden", "ban", "name", "alias", "pathWord", "closeComment", "closeRoast", "freeType", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/FreeType;", "restrict", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Restrict;", "reclass", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Reclass;", "females", "", "Lkotlinx/serialization/json/JsonElement;", "Lkotlinx/serialization/Contextual;", "males", "clubs", "seoBaidu", "region", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Region;", "status", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Status;", "author", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/AuthorInfo;", "theme", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ThemeInfo;", "parodies", "brief", "datetimeUpdated", "cover", "lastChapter", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/LastChapter;", "popular", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(ILjava/lang/String;ZZILjava/lang/String;Ljava/lang/String;Ljava/lang/String;ZZLeu/kanade/tachiyomi/extension/zh/copymanga/api/dto/FreeType;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Restrict;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Reclass;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/String;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Region;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Status;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/LastChapter;ILkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(Ljava/lang/String;ZZILjava/lang/String;Ljava/lang/String;Ljava/lang/String;ZZLeu/kanade/tachiyomi/extension/zh/copymanga/api/dto/FreeType;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Restrict;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Reclass;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/String;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Region;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Status;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/LastChapter;I)V", "getAlias", "()Ljava/lang/String;", "getAuthor", "()Ljava/util/List;", "getB404$annotations", "()V", "getB404", "()Z", "getBHidden$annotations", "getBHidden", "getBan", "()I", "getBrief", "getCloseComment$annotations", "getCloseComment", "getCloseRoast$annotations", "getCloseRoast", "getClubs", "getCover", "getDatetimeUpdated$annotations", "getDatetimeUpdated", "getFemales", "getFreeType$annotations", "getFreeType", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/FreeType;", "getLastChapter$annotations", "getLastChapter", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/LastChapter;", "getMales", "getName", "getParodies", "getPathWord$annotations", "getPathWord", "getPopular", "getReclass", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Reclass;", "getRegion", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Region;", "getRestrict", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Restrict;", "getSeoBaidu$annotations", "getSeoBaidu", "getStatus", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Status;", "getTheme", "getUuid", "component1", "component10", "component11", "component12", "component13", "component14", "component15", "component16", "component17", "component18", "component19", "component2", "component20", "component21", "component22", "component23", "component24", "component25", "component26", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "copy", "equals", "other", "hashCode", "toSManga", "Leu/kanade/tachiyomi/source/model/SManga;", "resolution", "language", "Leu/kanade/tachiyomi/extension/zh/copymanga/CCOption;", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
/* loaded from: classes.dex */
public final /* data */ class ComicDetail {

    /* renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final String alias;
    private final List<AuthorInfo> author;
    private final boolean b404;
    private final boolean bHidden;
    private final int ban;
    private final String brief;
    private final boolean closeComment;
    private final boolean closeRoast;
    private final List<JsonElement> clubs;
    private final String cover;
    private final String datetimeUpdated;
    private final List<JsonElement> females;
    private final FreeType freeType;
    private final LastChapter lastChapter;
    private final List<JsonElement> males;
    private final String name;
    private final List<JsonElement> parodies;
    private final String pathWord;
    private final int popular;
    private final Reclass reclass;
    private final Region region;
    private final Restrict restrict;
    private final String seoBaidu;
    private final Status status;
    private final List<ThemeInfo> theme;
    private final String uuid;

    @SerialName("b_404")
    public static /* synthetic */ void getB404$annotations() {
    }

    @SerialName("b_hidden")
    public static /* synthetic */ void getBHidden$annotations() {
    }

    @SerialName("close_comment")
    public static /* synthetic */ void getCloseComment$annotations() {
    }

    @SerialName("close_roast")
    public static /* synthetic */ void getCloseRoast$annotations() {
    }

    @SerialName("datetime_updated")
    public static /* synthetic */ void getDatetimeUpdated$annotations() {
    }

    @SerialName("free_type")
    public static /* synthetic */ void getFreeType$annotations() {
    }

    @SerialName("last_chapter")
    public static /* synthetic */ void getLastChapter$annotations() {
    }

    @SerialName("path_word")
    public static /* synthetic */ void getPathWord$annotations() {
    }

    @SerialName("seo_baidu")
    public static /* synthetic */ void getSeoBaidu$annotations() {
    }

    /* renamed from: component1, reason: from getter */
    public final String getUuid() {
        return this.uuid;
    }

    /* renamed from: component10, reason: from getter */
    public final FreeType getFreeType() {
        return this.freeType;
    }

    /* renamed from: component11, reason: from getter */
    public final Restrict getRestrict() {
        return this.restrict;
    }

    /* renamed from: component12, reason: from getter */
    public final Reclass getReclass() {
        return this.reclass;
    }

    public final List<JsonElement> component13() {
        return this.females;
    }

    public final List<JsonElement> component14() {
        return this.males;
    }

    public final List<JsonElement> component15() {
        return this.clubs;
    }

    /* renamed from: component16, reason: from getter */
    public final String getSeoBaidu() {
        return this.seoBaidu;
    }

    /* renamed from: component17, reason: from getter */
    public final Region getRegion() {
        return this.region;
    }

    /* renamed from: component18, reason: from getter */
    public final Status getStatus() {
        return this.status;
    }

    public final List<AuthorInfo> component19() {
        return this.author;
    }

    /* renamed from: component2, reason: from getter */
    public final boolean getB404() {
        return this.b404;
    }

    public final List<ThemeInfo> component20() {
        return this.theme;
    }

    public final List<JsonElement> component21() {
        return this.parodies;
    }

    /* renamed from: component22, reason: from getter */
    public final String getBrief() {
        return this.brief;
    }

    /* renamed from: component23, reason: from getter */
    public final String getDatetimeUpdated() {
        return this.datetimeUpdated;
    }

    /* renamed from: component24, reason: from getter */
    public final String getCover() {
        return this.cover;
    }

    /* renamed from: component25, reason: from getter */
    public final LastChapter getLastChapter() {
        return this.lastChapter;
    }

    /* renamed from: component26, reason: from getter */
    public final int getPopular() {
        return this.popular;
    }

    /* renamed from: component3, reason: from getter */
    public final boolean getBHidden() {
        return this.bHidden;
    }

    /* renamed from: component4, reason: from getter */
    public final int getBan() {
        return this.ban;
    }

    /* renamed from: component5, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* renamed from: component6, reason: from getter */
    public final String getAlias() {
        return this.alias;
    }

    /* renamed from: component7, reason: from getter */
    public final String getPathWord() {
        return this.pathWord;
    }

    /* renamed from: component8, reason: from getter */
    public final boolean getCloseComment() {
        return this.closeComment;
    }

    /* renamed from: component9, reason: from getter */
    public final boolean getCloseRoast() {
        return this.closeRoast;
    }

    public final ComicDetail copy(String uuid, boolean b404, boolean bHidden, int ban, String name, String alias, String pathWord, boolean closeComment, boolean closeRoast, FreeType freeType, Restrict restrict, Reclass reclass, List<? extends JsonElement> females, List<? extends JsonElement> males, List<? extends JsonElement> clubs, String seoBaidu, Region region, Status status, List<AuthorInfo> author, List<ThemeInfo> theme, List<? extends JsonElement> parodies, String brief, String datetimeUpdated, String cover, LastChapter lastChapter, int popular) {
        Intrinsics.checkNotNullParameter(uuid, "uuid");
        Intrinsics.checkNotNullParameter(name, "name");
        Intrinsics.checkNotNullParameter(alias, "alias");
        Intrinsics.checkNotNullParameter(pathWord, "pathWord");
        Intrinsics.checkNotNullParameter(restrict, "restrict");
        Intrinsics.checkNotNullParameter(reclass, "reclass");
        Intrinsics.checkNotNullParameter(females, "females");
        Intrinsics.checkNotNullParameter(males, "males");
        Intrinsics.checkNotNullParameter(clubs, "clubs");
        Intrinsics.checkNotNullParameter(seoBaidu, "seoBaidu");
        Intrinsics.checkNotNullParameter(region, "region");
        Intrinsics.checkNotNullParameter(status, "status");
        Intrinsics.checkNotNullParameter(author, "author");
        Intrinsics.checkNotNullParameter(theme, "theme");
        Intrinsics.checkNotNullParameter(parodies, "parodies");
        Intrinsics.checkNotNullParameter(brief, "brief");
        Intrinsics.checkNotNullParameter(cover, "cover");
        Intrinsics.checkNotNullParameter(lastChapter, "lastChapter");
        return new ComicDetail(uuid, b404, bHidden, ban, name, alias, pathWord, closeComment, closeRoast, freeType, restrict, reclass, females, males, clubs, seoBaidu, region, status, author, theme, parodies, brief, datetimeUpdated, cover, lastChapter, popular);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ComicDetail)) {
            return false;
        }
        ComicDetail comicDetail = (ComicDetail) other;
        return Intrinsics.areEqual(this.uuid, comicDetail.uuid) && this.b404 == comicDetail.b404 && this.bHidden == comicDetail.bHidden && this.ban == comicDetail.ban && Intrinsics.areEqual(this.name, comicDetail.name) && Intrinsics.areEqual(this.alias, comicDetail.alias) && Intrinsics.areEqual(this.pathWord, comicDetail.pathWord) && this.closeComment == comicDetail.closeComment && this.closeRoast == comicDetail.closeRoast && Intrinsics.areEqual(this.freeType, comicDetail.freeType) && Intrinsics.areEqual(this.restrict, comicDetail.restrict) && Intrinsics.areEqual(this.reclass, comicDetail.reclass) && Intrinsics.areEqual(this.females, comicDetail.females) && Intrinsics.areEqual(this.males, comicDetail.males) && Intrinsics.areEqual(this.clubs, comicDetail.clubs) && Intrinsics.areEqual(this.seoBaidu, comicDetail.seoBaidu) && Intrinsics.areEqual(this.region, comicDetail.region) && Intrinsics.areEqual(this.status, comicDetail.status) && Intrinsics.areEqual(this.author, comicDetail.author) && Intrinsics.areEqual(this.theme, comicDetail.theme) && Intrinsics.areEqual(this.parodies, comicDetail.parodies) && Intrinsics.areEqual(this.brief, comicDetail.brief) && Intrinsics.areEqual(this.datetimeUpdated, comicDetail.datetimeUpdated) && Intrinsics.areEqual(this.cover, comicDetail.cover) && Intrinsics.areEqual(this.lastChapter, comicDetail.lastChapter) && this.popular == comicDetail.popular;
    }

    /* JADX WARN: Multi-variable type inference failed */
    public int hashCode() {
        int iHashCode = this.uuid.hashCode() * 31;
        boolean z = this.b404;
        int i = z;
        if (z != 0) {
            i = 1;
        }
        int i2 = (iHashCode + i) * 31;
        boolean z2 = this.bHidden;
        int i3 = z2;
        if (z2 != 0) {
            i3 = 1;
        }
        int iHashCode2 = (((((((((i2 + i3) * 31) + this.ban) * 31) + this.name.hashCode()) * 31) + this.alias.hashCode()) * 31) + this.pathWord.hashCode()) * 31;
        boolean z3 = this.closeComment;
        int i4 = z3;
        if (z3 != 0) {
            i4 = 1;
        }
        int i5 = (iHashCode2 + i4) * 31;
        boolean z4 = this.closeRoast;
        int i6 = (i5 + (z4 ? 1 : z4 ? 1 : 0)) * 31;
        FreeType freeType = this.freeType;
        int iHashCode3 = (((((((((((((((((((((((((i6 + (freeType == null ? 0 : freeType.hashCode())) * 31) + this.restrict.hashCode()) * 31) + this.reclass.hashCode()) * 31) + this.females.hashCode()) * 31) + this.males.hashCode()) * 31) + this.clubs.hashCode()) * 31) + this.seoBaidu.hashCode()) * 31) + this.region.hashCode()) * 31) + this.status.hashCode()) * 31) + this.author.hashCode()) * 31) + this.theme.hashCode()) * 31) + this.parodies.hashCode()) * 31) + this.brief.hashCode()) * 31;
        String str = this.datetimeUpdated;
        return ((((((iHashCode3 + (str != null ? str.hashCode() : 0)) * 31) + this.cover.hashCode()) * 31) + this.lastChapter.hashCode()) * 31) + this.popular;
    }

    public String toString() {
        return "ComicDetail(uuid=" + this.uuid + ", b404=" + this.b404 + ", bHidden=" + this.bHidden + ", ban=" + this.ban + ", name=" + this.name + ", alias=" + this.alias + ", pathWord=" + this.pathWord + ", closeComment=" + this.closeComment + ", closeRoast=" + this.closeRoast + ", freeType=" + this.freeType + ", restrict=" + this.restrict + ", reclass=" + this.reclass + ", females=" + this.females + ", males=" + this.males + ", clubs=" + this.clubs + ", seoBaidu=" + this.seoBaidu + ", region=" + this.region + ", status=" + this.status + ", author=" + this.author + ", theme=" + this.theme + ", parodies=" + this.parodies + ", brief=" + this.brief + ", datetimeUpdated=" + this.datetimeUpdated + ", cover=" + this.cover + ", lastChapter=" + this.lastChapter + ", popular=" + this.popular + ')';
    }

    /* compiled from: ComicDetailResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicDetail$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicDetail;", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<ComicDetail> serializer() {
            return ComicDetail$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ ComicDetail(int i, String str, @SerialName("b_404") boolean z, @SerialName("b_hidden") boolean z2, int i2, String str2, String str3, @SerialName("path_word") String str4, @SerialName("close_comment") boolean z3, @SerialName("close_roast") boolean z4, @SerialName("free_type") FreeType freeType, Restrict restrict, Reclass reclass, List list, List list2, List list3, @SerialName("seo_baidu") String str5, Region region, Status status, List list4, List list5, List list6, String str6, @SerialName("datetime_updated") String str7, String str8, @SerialName("last_chapter") LastChapter lastChapter, int i3, SerializationConstructorMarker serializationConstructorMarker) {
        if (61312479 != (i & 61312479)) {
            PluginExceptionsKt.throwMissingFieldException(i, 61312479, ComicDetail$$serializer.INSTANCE.getDescriptor());
        }
        this.uuid = str;
        this.b404 = z;
        this.bHidden = z2;
        this.ban = i2;
        this.name = str2;
        this.alias = (i & 32) == 0 ? "" : str3;
        this.pathWord = str4;
        this.closeComment = z3;
        this.closeRoast = z4;
        if ((i & 512) == 0) {
            this.freeType = null;
        } else {
            this.freeType = freeType;
        }
        this.restrict = restrict;
        this.reclass = reclass;
        this.females = (i & 4096) == 0 ? CollectionsKt.emptyList() : list;
        this.males = (i & 8192) == 0 ? CollectionsKt.emptyList() : list2;
        this.clubs = (i & 16384) == 0 ? CollectionsKt.emptyList() : list3;
        this.seoBaidu = str5;
        this.region = region;
        this.status = status;
        this.author = list4;
        this.theme = (524288 & i) == 0 ? CollectionsKt.emptyList() : list5;
        this.parodies = (1048576 & i) == 0 ? CollectionsKt.emptyList() : list6;
        this.brief = str6;
        if ((i & 4194304) == 0) {
            this.datetimeUpdated = null;
        } else {
            this.datetimeUpdated = str7;
        }
        this.cover = str8;
        this.lastChapter = lastChapter;
        this.popular = i3;
    }

    public ComicDetail(String str, boolean z, boolean z2, int i, String str2, String str3, String str4, boolean z3, boolean z4, FreeType freeType, Restrict restrict, Reclass reclass, List<? extends JsonElement> list, List<? extends JsonElement> list2, List<? extends JsonElement> list3, String str5, Region region, Status status, List<AuthorInfo> list4, List<ThemeInfo> list5, List<? extends JsonElement> list6, String str6, String str7, String str8, LastChapter lastChapter, int i2) {
        Intrinsics.checkNotNullParameter(str, "uuid");
        Intrinsics.checkNotNullParameter(str2, "name");
        Intrinsics.checkNotNullParameter(str3, "alias");
        Intrinsics.checkNotNullParameter(str4, "pathWord");
        Intrinsics.checkNotNullParameter(restrict, "restrict");
        Intrinsics.checkNotNullParameter(reclass, "reclass");
        Intrinsics.checkNotNullParameter(list, "females");
        Intrinsics.checkNotNullParameter(list2, "males");
        Intrinsics.checkNotNullParameter(list3, "clubs");
        Intrinsics.checkNotNullParameter(str5, "seoBaidu");
        Intrinsics.checkNotNullParameter(region, "region");
        Intrinsics.checkNotNullParameter(status, "status");
        Intrinsics.checkNotNullParameter(list4, "author");
        Intrinsics.checkNotNullParameter(list5, "theme");
        Intrinsics.checkNotNullParameter(list6, "parodies");
        Intrinsics.checkNotNullParameter(str6, "brief");
        Intrinsics.checkNotNullParameter(str8, "cover");
        Intrinsics.checkNotNullParameter(lastChapter, "lastChapter");
        this.uuid = str;
        this.b404 = z;
        this.bHidden = z2;
        this.ban = i;
        this.name = str2;
        this.alias = str3;
        this.pathWord = str4;
        this.closeComment = z3;
        this.closeRoast = z4;
        this.freeType = freeType;
        this.restrict = restrict;
        this.reclass = reclass;
        this.females = list;
        this.males = list2;
        this.clubs = list3;
        this.seoBaidu = str5;
        this.region = region;
        this.status = status;
        this.author = list4;
        this.theme = list5;
        this.parodies = list6;
        this.brief = str6;
        this.datetimeUpdated = str7;
        this.cover = str8;
        this.lastChapter = lastChapter;
        this.popular = i2;
    }

    @JvmStatic
    public static final void write$Self(ComicDetail self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeStringElement(serialDesc, 0, self.uuid);
        output.encodeBooleanElement(serialDesc, 1, self.b404);
        output.encodeBooleanElement(serialDesc, 2, self.bHidden);
        output.encodeIntElement(serialDesc, 3, self.ban);
        output.encodeStringElement(serialDesc, 4, self.name);
        if (output.shouldEncodeElementDefault(serialDesc, 5) || !Intrinsics.areEqual(self.alias, "")) {
            output.encodeStringElement(serialDesc, 5, self.alias);
        }
        output.encodeStringElement(serialDesc, 6, self.pathWord);
        output.encodeBooleanElement(serialDesc, 7, self.closeComment);
        output.encodeBooleanElement(serialDesc, 8, self.closeRoast);
        if (output.shouldEncodeElementDefault(serialDesc, 9) || self.freeType != null) {
            output.encodeNullableSerializableElement(serialDesc, 9, FreeType$$serializer.INSTANCE, self.freeType);
        }
        output.encodeSerializableElement(serialDesc, 10, Restrict$$serializer.INSTANCE, self.restrict);
        output.encodeSerializableElement(serialDesc, 11, Reclass$$serializer.INSTANCE, self.reclass);
        if (output.shouldEncodeElementDefault(serialDesc, 12) || !Intrinsics.areEqual(self.females, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 12, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), self.females);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 13) || !Intrinsics.areEqual(self.males, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 13, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), self.males);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 14) || !Intrinsics.areEqual(self.clubs, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 14, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), self.clubs);
        }
        output.encodeStringElement(serialDesc, 15, self.seoBaidu);
        output.encodeSerializableElement(serialDesc, 16, Region$$serializer.INSTANCE, self.region);
        output.encodeSerializableElement(serialDesc, 17, Status$$serializer.INSTANCE, self.status);
        output.encodeSerializableElement(serialDesc, 18, new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), self.author);
        if (output.shouldEncodeElementDefault(serialDesc, 19) || !Intrinsics.areEqual(self.theme, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 19, new ArrayListSerializer(ThemeInfo$$serializer.INSTANCE), self.theme);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 20) || !Intrinsics.areEqual(self.parodies, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 20, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), self.parodies);
        }
        output.encodeStringElement(serialDesc, 21, self.brief);
        if (output.shouldEncodeElementDefault(serialDesc, 22) || self.datetimeUpdated != null) {
            output.encodeNullableSerializableElement(serialDesc, 22, StringSerializer.INSTANCE, self.datetimeUpdated);
        }
        output.encodeStringElement(serialDesc, 23, self.cover);
        output.encodeSerializableElement(serialDesc, 24, LastChapter$$serializer.INSTANCE, self.lastChapter);
        output.encodeIntElement(serialDesc, 25, self.popular);
    }

    public final String getUuid() {
        return this.uuid;
    }

    public final boolean getB404() {
        return this.b404;
    }

    public final boolean getBHidden() {
        return this.bHidden;
    }

    public final int getBan() {
        return this.ban;
    }

    public final String getName() {
        return this.name;
    }

    public /* synthetic */ ComicDetail(String str, boolean z, boolean z2, int i, String str2, String str3, String str4, boolean z3, boolean z4, FreeType freeType, Restrict restrict, Reclass reclass, List list, List list2, List list3, String str5, Region region, Status status, List list4, List list5, List list6, String str6, String str7, String str8, LastChapter lastChapter, int i2, int i3, DefaultConstructorMarker defaultConstructorMarker) {
        this(str, z, z2, i, str2, (i3 & 32) != 0 ? "" : str3, str4, z3, z4, (i3 & 512) != 0 ? null : freeType, restrict, reclass, (i3 & 4096) != 0 ? CollectionsKt.emptyList() : list, (i3 & 8192) != 0 ? CollectionsKt.emptyList() : list2, (i3 & 16384) != 0 ? CollectionsKt.emptyList() : list3, str5, region, status, list4, (524288 & i3) != 0 ? CollectionsKt.emptyList() : list5, (1048576 & i3) != 0 ? CollectionsKt.emptyList() : list6, str6, (i3 & 4194304) != 0 ? null : str7, str8, lastChapter, i2);
    }

    public final String getAlias() {
        return this.alias;
    }

    public final String getPathWord() {
        return this.pathWord;
    }

    public final boolean getCloseComment() {
        return this.closeComment;
    }

    public final boolean getCloseRoast() {
        return this.closeRoast;
    }

    public final FreeType getFreeType() {
        return this.freeType;
    }

    public final Restrict getRestrict() {
        return this.restrict;
    }

    public final Reclass getReclass() {
        return this.reclass;
    }

    public final List<JsonElement> getFemales() {
        return this.females;
    }

    public final List<JsonElement> getMales() {
        return this.males;
    }

    public final List<JsonElement> getClubs() {
        return this.clubs;
    }

    public final String getSeoBaidu() {
        return this.seoBaidu;
    }

    public final Region getRegion() {
        return this.region;
    }

    public final Status getStatus() {
        return this.status;
    }

    public final List<AuthorInfo> getAuthor() {
        return this.author;
    }

    public final List<ThemeInfo> getTheme() {
        return this.theme;
    }

    public final List<JsonElement> getParodies() {
        return this.parodies;
    }

    public final String getBrief() {
        return this.brief;
    }

    public final String getDatetimeUpdated() {
        return this.datetimeUpdated;
    }

    public final String getCover() {
        return this.cover;
    }

    public final LastChapter getLastChapter() {
        return this.lastChapter;
    }

    public final int getPopular() {
        return this.popular;
    }

    public final SManga toSManga(String resolution, CCOption language) {
        Intrinsics.checkNotNullParameter(resolution, "resolution");
        Intrinsics.checkNotNullParameter(language, "language");
        SManga sMangaCreate = SManga.Companion.create();
        sMangaCreate.setUrl("/comic/" + this.pathWord);
        sMangaCreate.setTitle(TranslateKt.translate(this.name, language));
        sMangaCreate.setAuthor(CollectionsKt.joinToString$default(this.author, (CharSequence) null, (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, new Function1<AuthorInfo, CharSequence>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ComicDetail$toSManga$1$1
            public final CharSequence invoke(AuthorInfo authorInfo) {
                Intrinsics.checkNotNullParameter(authorInfo, "it");
                return authorInfo.getName();
            }
        }, 31, (Object) null));
        sMangaCreate.setDescription(TranslateKt.translate(this.brief, language));
        sMangaCreate.setGenre(TranslateKt.translate(this.region.getDisplay() + ", " + CollectionsKt.joinToString$default(this.theme, (CharSequence) null, (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, new Function1<ThemeInfo, CharSequence>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ComicDetail$toSManga$1$2
            public final CharSequence invoke(ThemeInfo themeInfo) {
                Intrinsics.checkNotNullParameter(themeInfo, "it");
                return themeInfo.getName();
            }
        }, 31, (Object) null), language));
        sMangaCreate.setStatus(MangaStatusManager.INSTANCE.parseStatus(this.status.getValue()));
        sMangaCreate.setThumbnail_url(ResolutionOption.INSTANCE.translate(this.cover, resolution));
        sMangaCreate.setInitialized(true);
        return sMangaCreate;
    }
}
