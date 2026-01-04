package keiyoushi.utils;

import java.io.Closeable;
import java.io.InputStream;
import kotlin.Lazy;
import kotlin.LazyKt;
import kotlin.Metadata;
import kotlin.io.CloseableKt;
import kotlin.jvm.functions.Function0;
import kotlin.jvm.functions.Function1;
import kotlin.jvm.internal.Intrinsics;
import kotlin.reflect.KType;
import kotlinx.serialization.DeserializationStrategy;
import kotlinx.serialization.KSerializer;
import kotlinx.serialization.SerializationStrategy;
import kotlinx.serialization.SerializersKt;
import kotlinx.serialization.StringFormat;
import kotlinx.serialization.json.Json;
import kotlinx.serialization.json.JvmStreamsKt;
import kotlinx.serialization.modules.SerializersModule;
import okhttp3.Response;
import uy.kohesive.injekt.InjektKt;
import uy.kohesive.injekt.api.FullTypeReference;
import uy.kohesive.injekt.api.InjektFactory;
import uy.kohesive.injekt.api.TypeReference;

/* compiled from: Json.kt */
@Metadata(d1 = {"\u0000 \n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0006\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0005\u001a$\u0010\u0006\u001a\u0002H\u0007\"\u0006\b\u0000\u0010\u0007\u0018\u0001*\u00020\b2\b\b\u0002\u0010\t\u001a\u00020\u0001H\u0086\b¢\u0006\u0002\u0010\n\u001a;\u0010\u0006\u001a\u0002H\u0007\"\u0006\b\u0000\u0010\u0007\u0018\u0001*\u00020\b2\b\b\u0002\u0010\t\u001a\u00020\u00012\u0012\u0010\u000b\u001a\u000e\u0012\u0004\u0012\u00020\b\u0012\u0004\u0012\u00020\b0\fH\u0086\bø\u0001\u0000¢\u0006\u0002\u0010\r\u001a$\u0010\u0006\u001a\u0002H\u0007\"\u0006\b\u0000\u0010\u0007\u0018\u0001*\u00020\u000e2\b\b\u0002\u0010\t\u001a\u00020\u0001H\u0086\b¢\u0006\u0002\u0010\u000f\u001a;\u0010\u0006\u001a\u0002H\u0007\"\u0006\b\u0000\u0010\u0007\u0018\u0001*\u00020\u000e2\b\b\u0002\u0010\t\u001a\u00020\u00012\u0012\u0010\u000b\u001a\u000e\u0012\u0004\u0012\u00020\b\u0012\u0004\u0012\u00020\b0\fH\u0086\bø\u0001\u0000¢\u0006\u0002\u0010\u0010\u001a$\u0010\u0011\u001a\u00020\b\"\u0006\b\u0000\u0010\u0007\u0018\u0001*\u0002H\u00072\b\b\u0002\u0010\t\u001a\u00020\u0001H\u0086\b¢\u0006\u0002\u0010\u0012\"\u001b\u0010\u0000\u001a\u00020\u00018FX\u0086\u0084\u0002¢\u0006\f\n\u0004\b\u0004\u0010\u0005\u001a\u0004\b\u0002\u0010\u0003\u0082\u0002\u0007\n\u0005\b\u009920\u0001¨\u0006\u0013"}, d2 = {"jsonInstance", "Lkotlinx/serialization/json/Json;", "getJsonInstance", "()Lkotlinx/serialization/json/Json;", "jsonInstance$delegate", "Lkotlin/Lazy;", "parseAs", "T", "", "json", "(Ljava/lang/String;Lkotlinx/serialization/json/Json;)Ljava/lang/Object;", "transform", "Lkotlin/Function1;", "(Ljava/lang/String;Lkotlinx/serialization/json/Json;Lkotlin/jvm/functions/Function1;)Ljava/lang/Object;", "Lokhttp3/Response;", "(Lokhttp3/Response;Lkotlinx/serialization/json/Json;)Ljava/lang/Object;", "(Lokhttp3/Response;Lkotlinx/serialization/json/Json;Lkotlin/jvm/functions/Function1;)Ljava/lang/Object;", "toJsonString", "(Ljava/lang/Object;Lkotlinx/serialization/json/Json;)Ljava/lang/String;", "core_debug"}, k = 2, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class JsonKt {
    private static final Lazy jsonInstance$delegate = LazyKt.lazy(new Function0<Json>() { // from class: keiyoushi.utils.JsonKt$special$$inlined$injectLazy$1
        /* JADX WARN: Type inference failed for: r0v2, types: [java.lang.Object, kotlinx.serialization.json.Json] */
        public final Json invoke() {
            InjektFactory $receiver$iv = InjektKt.getInjekt();
            TypeReference forType$iv = (FullTypeReference) new FullTypeReference<Json>() { // from class: keiyoushi.utils.JsonKt$special$$inlined$injectLazy$1.1
            };
            return $receiver$iv.getInstance(forType$iv.getType());
        }
    });

    public static final Json getJsonInstance() {
        return (Json) jsonInstance$delegate.getValue();
    }

    public static /* synthetic */ Object parseAs$default(String $this$parseAs_u24default, Json json, int i, Object obj) {
        if ((i & 1) != 0) {
            json = getJsonInstance();
        }
        Intrinsics.checkNotNullParameter($this$parseAs_u24default, "<this>");
        Intrinsics.checkNotNullParameter(json, "json");
        StringFormat $this$decodeFromString$iv = (StringFormat) json;
        SerializersModule $this$serializer$iv$iv = $this$decodeFromString$iv.getSerializersModule();
        Intrinsics.reifiedOperationMarker(6, "T");
        DeserializationStrategy deserializationStrategySerializer = SerializersKt.serializer($this$serializer$iv$iv, (KType) null);
        Intrinsics.checkNotNull(deserializationStrategySerializer, "null cannot be cast to non-null type kotlinx.serialization.KSerializer<T of kotlinx.serialization.internal.Platform_commonKt.cast>");
        return $this$decodeFromString$iv.decodeFromString((KSerializer) deserializationStrategySerializer, $this$parseAs_u24default);
    }

    public static final /* synthetic */ <T> T parseAs(String str, Json json) {
        Intrinsics.checkNotNullParameter(str, "<this>");
        Intrinsics.checkNotNullParameter(json, "json");
        StringFormat stringFormat = (StringFormat) json;
        SerializersModule serializersModule = stringFormat.getSerializersModule();
        Intrinsics.reifiedOperationMarker(6, "T");
        DeserializationStrategy deserializationStrategySerializer = SerializersKt.serializer(serializersModule, (KType) null);
        Intrinsics.checkNotNull(deserializationStrategySerializer, "null cannot be cast to non-null type kotlinx.serialization.KSerializer<T of kotlinx.serialization.internal.Platform_commonKt.cast>");
        return (T) stringFormat.decodeFromString((KSerializer) deserializationStrategySerializer, str);
    }

    public static /* synthetic */ Object parseAs$default(String $this$parseAs_u24default, Json json, Function1 transform, int i, Object obj) {
        if ((i & 1) != 0) {
            json = getJsonInstance();
        }
        Intrinsics.checkNotNullParameter($this$parseAs_u24default, "<this>");
        Intrinsics.checkNotNullParameter(json, "json");
        Intrinsics.checkNotNullParameter(transform, "transform");
        String $this$parseAs$iv = (String) transform.invoke($this$parseAs_u24default);
        StringFormat $this$decodeFromString$iv$iv = (StringFormat) json;
        SerializersModule $this$serializer$iv$iv$iv = $this$decodeFromString$iv$iv.getSerializersModule();
        Intrinsics.reifiedOperationMarker(6, "T");
        DeserializationStrategy deserializationStrategySerializer = SerializersKt.serializer($this$serializer$iv$iv$iv, (KType) null);
        Intrinsics.checkNotNull(deserializationStrategySerializer, "null cannot be cast to non-null type kotlinx.serialization.KSerializer<T of kotlinx.serialization.internal.Platform_commonKt.cast>");
        return $this$decodeFromString$iv$iv.decodeFromString((KSerializer) deserializationStrategySerializer, $this$parseAs$iv);
    }

    public static final /* synthetic */ <T> T parseAs(String str, Json json, Function1<? super String, String> function1) {
        Intrinsics.checkNotNullParameter(str, "<this>");
        Intrinsics.checkNotNullParameter(json, "json");
        Intrinsics.checkNotNullParameter(function1, "transform");
        String str2 = (String) function1.invoke(str);
        StringFormat stringFormat = (StringFormat) json;
        SerializersModule serializersModule = stringFormat.getSerializersModule();
        Intrinsics.reifiedOperationMarker(6, "T");
        DeserializationStrategy deserializationStrategySerializer = SerializersKt.serializer(serializersModule, (KType) null);
        Intrinsics.checkNotNull(deserializationStrategySerializer, "null cannot be cast to non-null type kotlinx.serialization.KSerializer<T of kotlinx.serialization.internal.Platform_commonKt.cast>");
        return (T) stringFormat.decodeFromString((KSerializer) deserializationStrategySerializer, str2);
    }

    public static /* synthetic */ Object parseAs$default(Response $this$parseAs_u24default, Json json, int i, Object obj) {
        if ((i & 1) != 0) {
            json = getJsonInstance();
        }
        Intrinsics.checkNotNullParameter($this$parseAs_u24default, "<this>");
        Intrinsics.checkNotNullParameter(json, "json");
        Response response = (Closeable) $this$parseAs_u24default;
        try {
            InputStream stream$iv = $this$parseAs_u24default.body().byteStream();
            Json $this$decodeFromStream$iv = json;
            SerializersModule $this$serializer$iv$iv = $this$decodeFromStream$iv.getSerializersModule();
            Intrinsics.reifiedOperationMarker(6, "T");
            DeserializationStrategy deserializationStrategySerializer = SerializersKt.serializer($this$serializer$iv$iv, (KType) null);
            Intrinsics.checkNotNull(deserializationStrategySerializer, "null cannot be cast to non-null type kotlinx.serialization.KSerializer<T of kotlinx.serialization.internal.Platform_commonKt.cast>");
            Object objDecodeFromStream = JvmStreamsKt.decodeFromStream($this$decodeFromStream$iv, (KSerializer) deserializationStrategySerializer, stream$iv);
            CloseableKt.closeFinally(response, (Throwable) null);
            return objDecodeFromStream;
        } finally {
        }
    }

    public static final /* synthetic */ <T> T parseAs(Response response, Json json) {
        Intrinsics.checkNotNullParameter(response, "<this>");
        Intrinsics.checkNotNullParameter(json, "json");
        Response response2 = (Closeable) response;
        try {
            InputStream inputStreamByteStream = response.body().byteStream();
            SerializersModule serializersModule = json.getSerializersModule();
            Intrinsics.reifiedOperationMarker(6, "T");
            DeserializationStrategy deserializationStrategySerializer = SerializersKt.serializer(serializersModule, (KType) null);
            Intrinsics.checkNotNull(deserializationStrategySerializer, "null cannot be cast to non-null type kotlinx.serialization.KSerializer<T of kotlinx.serialization.internal.Platform_commonKt.cast>");
            T t = (T) JvmStreamsKt.decodeFromStream(json, (KSerializer) deserializationStrategySerializer, inputStreamByteStream);
            CloseableKt.closeFinally(response2, (Throwable) null);
            return t;
        } finally {
        }
    }

    public static /* synthetic */ Object parseAs$default(Response $this$parseAs_u24default, Json json, Function1 transform, int i, Object obj) {
        if ((i & 1) != 0) {
            json = getJsonInstance();
        }
        Intrinsics.checkNotNullParameter($this$parseAs_u24default, "<this>");
        Intrinsics.checkNotNullParameter(json, "json");
        Intrinsics.checkNotNullParameter(transform, "transform");
        String $this$parseAs$iv = $this$parseAs_u24default.body().string();
        String $this$parseAs$iv$iv = (String) transform.invoke($this$parseAs$iv);
        StringFormat $this$decodeFromString$iv$iv$iv = (StringFormat) json;
        SerializersModule $this$serializer$iv$iv$iv$iv = $this$decodeFromString$iv$iv$iv.getSerializersModule();
        Intrinsics.reifiedOperationMarker(6, "T");
        DeserializationStrategy deserializationStrategySerializer = SerializersKt.serializer($this$serializer$iv$iv$iv$iv, (KType) null);
        Intrinsics.checkNotNull(deserializationStrategySerializer, "null cannot be cast to non-null type kotlinx.serialization.KSerializer<T of kotlinx.serialization.internal.Platform_commonKt.cast>");
        return $this$decodeFromString$iv$iv$iv.decodeFromString((KSerializer) deserializationStrategySerializer, $this$parseAs$iv$iv);
    }

    public static final /* synthetic */ <T> T parseAs(Response response, Json json, Function1<? super String, String> function1) {
        Intrinsics.checkNotNullParameter(response, "<this>");
        Intrinsics.checkNotNullParameter(json, "json");
        Intrinsics.checkNotNullParameter(function1, "transform");
        String str = (String) function1.invoke(response.body().string());
        StringFormat stringFormat = (StringFormat) json;
        SerializersModule serializersModule = stringFormat.getSerializersModule();
        Intrinsics.reifiedOperationMarker(6, "T");
        DeserializationStrategy deserializationStrategySerializer = SerializersKt.serializer(serializersModule, (KType) null);
        Intrinsics.checkNotNull(deserializationStrategySerializer, "null cannot be cast to non-null type kotlinx.serialization.KSerializer<T of kotlinx.serialization.internal.Platform_commonKt.cast>");
        return (T) stringFormat.decodeFromString((KSerializer) deserializationStrategySerializer, str);
    }

    public static /* synthetic */ String toJsonString$default(Object $this$toJsonString_u24default, Json json, int i, Object obj) {
        if ((i & 1) != 0) {
            json = getJsonInstance();
        }
        Intrinsics.checkNotNullParameter(json, "json");
        StringFormat $this$encodeToString$iv = (StringFormat) json;
        SerializersModule $this$serializer$iv$iv = $this$encodeToString$iv.getSerializersModule();
        Intrinsics.reifiedOperationMarker(6, "T");
        SerializationStrategy serializationStrategySerializer = SerializersKt.serializer($this$serializer$iv$iv, (KType) null);
        Intrinsics.checkNotNull(serializationStrategySerializer, "null cannot be cast to non-null type kotlinx.serialization.KSerializer<T of kotlinx.serialization.internal.Platform_commonKt.cast>");
        return $this$encodeToString$iv.encodeToString((KSerializer) serializationStrategySerializer, $this$toJsonString_u24default);
    }

    public static final /* synthetic */ <T> String toJsonString(T t, Json json) {
        Intrinsics.checkNotNullParameter(json, "json");
        StringFormat $this$encodeToString$iv = (StringFormat) json;
        SerializersModule $this$serializer$iv$iv = $this$encodeToString$iv.getSerializersModule();
        Intrinsics.reifiedOperationMarker(6, "T");
        SerializationStrategy serializationStrategySerializer = SerializersKt.serializer($this$serializer$iv$iv, (KType) null);
        Intrinsics.checkNotNull(serializationStrategySerializer, "null cannot be cast to non-null type kotlinx.serialization.KSerializer<T of kotlinx.serialization.internal.Platform_commonKt.cast>");
        return $this$encodeToString$iv.encodeToString((KSerializer) serializationStrategySerializer, t);
    }
}
