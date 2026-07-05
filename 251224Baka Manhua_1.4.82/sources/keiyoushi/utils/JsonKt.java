package keiyoushi.utils;

import java.io.InputStream;
import kotlin.Lazy;
import kotlin.LazyKt;
import kotlin.Metadata;
import kotlin.jvm.functions.Function0;
import kotlin.jvm.internal.Intrinsics;
import kotlin.jvm.internal.MagicApiIntrinsics;
import kotlin.reflect.KType;
import kotlinx.serialization.SerializersKt;
import kotlinx.serialization.StringFormat;
import kotlinx.serialization.json.Json;
import kotlinx.serialization.json.JvmStreamsKt;
import kotlinx.serialization.modules.SerializersModule;
import okhttp3.Response;
import uy.kohesive.injekt.InjektKt;
import uy.kohesive.injekt.api.FullTypeReference;

/* JADX INFO: compiled from: Json.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000\u001a\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0006\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0004\u001a$\u0010\u0006\u001a\u0002H\u0007\"\u0006\b\u0000\u0010\u0007\u0018\u0001*\u00020\b2\b\b\u0002\u0010\t\u001a\u00020\u0001H\u0086\b¢\u0006\u0002\u0010\n\u001a$\u0010\u0006\u001a\u0002H\u0007\"\u0006\b\u0000\u0010\u0007\u0018\u0001*\u00020\u000b2\b\b\u0002\u0010\t\u001a\u00020\u0001H\u0086\b¢\u0006\u0002\u0010\f\u001a$\u0010\r\u001a\u00020\b\"\u0006\b\u0000\u0010\u0007\u0018\u0001*\u0002H\u00072\b\b\u0002\u0010\t\u001a\u00020\u0001H\u0086\b¢\u0006\u0002\u0010\u000e\"\u001b\u0010\u0000\u001a\u00020\u00018FX\u0086\u0084\u0002¢\u0006\f\n\u0004\b\u0004\u0010\u0005\u001a\u0004\b\u0002\u0010\u0003¨\u0006\u000f"}, d2 = {"jsonInstance", "Lkotlinx/serialization/json/Json;", "getJsonInstance", "()Lkotlinx/serialization/json/Json;", "jsonInstance$delegate", "Lkotlin/Lazy;", "parseAs", "T", "", "json", "(Ljava/lang/String;Lkotlinx/serialization/json/Json;)Ljava/lang/Object;", "Lokhttp3/Response;", "(Lokhttp3/Response;Lkotlinx/serialization/json/Json;)Ljava/lang/Object;", "toJsonString", "(Ljava/lang/Object;Lkotlinx/serialization/json/Json;)Ljava/lang/String;", "core_release"}, k = 2, mv = {1, 7, 1}, xi = 48)
public final class JsonKt {
    private static final Lazy jsonInstance$delegate = LazyKt.lazy(new Function0<Json>() { // from class: keiyoushi.utils.JsonKt$special$$inlined$injectLazy$1
        /* JADX WARN: Type inference failed for: r0v2, types: [java.lang.Object, kotlinx.serialization.json.Json] */
        public final Json invoke() {
            return InjektKt.getInjekt().getInstance(((FullTypeReference) new FullTypeReference<Json>() { // from class: keiyoushi.utils.JsonKt$special$$inlined$injectLazy$1.1
            }).getType());
        }
    });

    public static final Json getJsonInstance() {
        return (Json) jsonInstance$delegate.getValue();
    }

    public static /* synthetic */ Object parseAs$default(String str, Json json, int i, Object obj) {
        if ((i & 1) != 0) {
            json = getJsonInstance();
        }
        Intrinsics.checkNotNullParameter(str, "<this>");
        Intrinsics.checkNotNullParameter(json, "json");
        StringFormat stringFormat = (StringFormat) json;
        SerializersModule serializersModule = stringFormat.getSerializersModule();
        Intrinsics.reifiedOperationMarker(6, "T");
        MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
        return stringFormat.decodeFromString(SerializersKt.serializer(serializersModule, (KType) null), str);
    }

    public static final /* synthetic */ <T> T parseAs(String str, Json json) {
        Intrinsics.checkNotNullParameter(str, "<this>");
        Intrinsics.checkNotNullParameter(json, "json");
        StringFormat stringFormat = (StringFormat) json;
        SerializersModule serializersModule = stringFormat.getSerializersModule();
        Intrinsics.reifiedOperationMarker(6, "T");
        MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
        return (T) stringFormat.decodeFromString(SerializersKt.serializer(serializersModule, (KType) null), str);
    }

    public static /* synthetic */ Object parseAs$default(Response response, Json json, int i, Object obj) {
        if ((i & 1) != 0) {
            json = getJsonInstance();
        }
        Intrinsics.checkNotNullParameter(response, "<this>");
        Intrinsics.checkNotNullParameter(json, "json");
        InputStream inputStreamByteStream = response.body().byteStream();
        SerializersModule serializersModule = json.getSerializersModule();
        Intrinsics.reifiedOperationMarker(6, "T");
        MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
        return JvmStreamsKt.decodeFromStream(json, SerializersKt.serializer(serializersModule, (KType) null), inputStreamByteStream);
    }

    public static final /* synthetic */ <T> T parseAs(Response response, Json json) {
        Intrinsics.checkNotNullParameter(response, "<this>");
        Intrinsics.checkNotNullParameter(json, "json");
        InputStream inputStreamByteStream = response.body().byteStream();
        SerializersModule serializersModule = json.getSerializersModule();
        Intrinsics.reifiedOperationMarker(6, "T");
        MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
        return (T) JvmStreamsKt.decodeFromStream(json, SerializersKt.serializer(serializersModule, (KType) null), inputStreamByteStream);
    }

    public static /* synthetic */ String toJsonString$default(Object obj, Json json, int i, Object obj2) {
        if ((i & 1) != 0) {
            json = getJsonInstance();
        }
        Intrinsics.checkNotNullParameter(json, "json");
        StringFormat stringFormat = (StringFormat) json;
        SerializersModule serializersModule = stringFormat.getSerializersModule();
        Intrinsics.reifiedOperationMarker(6, "T");
        MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
        return stringFormat.encodeToString(SerializersKt.serializer(serializersModule, (KType) null), obj);
    }

    public static final /* synthetic */ <T> String toJsonString(T t, Json json) {
        Intrinsics.checkNotNullParameter(json, "json");
        StringFormat stringFormat = (StringFormat) json;
        SerializersModule serializersModule = stringFormat.getSerializersModule();
        Intrinsics.reifiedOperationMarker(6, "T");
        MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
        return stringFormat.encodeToString(SerializersKt.serializer(serializersModule, (KType) null), t);
    }
}
