package eu.kanade.tachiyomi.extension.zh.copymanga.api;

import kotlin.Metadata;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;
import kotlin.jvm.internal.Intrinsics;
import kotlin.jvm.internal.MagicApiIntrinsics;
import kotlin.jvm.internal.Reflection;
import kotlin.reflect.KType;
import kotlin.reflect.KTypeProjection;
import kotlinx.serialization.SerializersKt;
import kotlinx.serialization.StringFormat;
import kotlinx.serialization.json.Json;
import kotlinx.serialization.json.JsonBuilder;
import kotlinx.serialization.json.JsonKt;
import kotlinx.serialization.modules.SerializersModule;
import okhttp3.Response;

/* compiled from: ApiResponse.kt */
@Metadata(d1 = {"\u0000\u0018\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\u001a\u001e\u0010\u0004\u001a\u0002H\u0005\"\u0006\b\u0000\u0010\u0005\u0018\u00012\u0006\u0010\u0006\u001a\u00020\u0007H\u0087\b¢\u0006\u0002\u0010\b\u001a\n\u0010\t\u001a\u00020\u0007*\u00020\u0007\u001a\n\u0010\n\u001a\u00020\u000b*\u00020\u0007\"\u0011\u0010\u0000\u001a\u00020\u0001¢\u0006\b\n\u0000\u001a\u0004\b\u0002\u0010\u0003¨\u0006\f"}, d2 = {"json", "Lkotlinx/serialization/json/Json;", "getJson", "()Lkotlinx/serialization/json/Json;", "parseResult", "T", "response", "Lokhttp3/Response;", "(Lokhttp3/Response;)Ljava/lang/Object;", "newResponse", "peek", "", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 2, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class ApiResponseKt {
    private static final Json json = JsonKt.Json$default((Json) null, new Function1<JsonBuilder, Unit>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiResponseKt$json$1
        public /* bridge */ /* synthetic */ Object invoke(Object obj) {
            invoke((JsonBuilder) obj);
            return Unit.INSTANCE;
        }

        public final void invoke(JsonBuilder jsonBuilder) {
            Intrinsics.checkNotNullParameter(jsonBuilder, "$this$Json");
            jsonBuilder.setIgnoreUnknownKeys(true);
            jsonBuilder.setCoerceInputValues(true);
            jsonBuilder.setLenient(true);
            jsonBuilder.setExplicitNulls(false);
        }
    }, 1, (Object) null);

    public static final Json getJson() {
        return json;
    }

    public static final String peek(Response response) {
        Intrinsics.checkNotNullParameter(response, "<this>");
        return response.peekBody(2048L).string();
    }

    public static final Response newResponse(Response response) {
        Intrinsics.checkNotNullParameter(response, "<this>");
        return response.newBuilder().body(response.body()).build();
    }

    public static final /* synthetic */ <T> T parseResult(Response response) throws Exception {
        Intrinsics.checkNotNullParameter(response, "response");
        try {
            if (response.isSuccessful()) {
                StringFormat json2 = getJson();
                String strString = response.body().string();
                SerializersModule serializersModule = json2.getSerializersModule();
                KTypeProjection.Companion companion = KTypeProjection.Companion;
                Intrinsics.reifiedOperationMarker(6, "T");
                KType kTypeTypeOf = Reflection.typeOf(ApiResponse.class, companion.invariant((KType) null));
                MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                return (T) ((ApiResponse) json2.decodeFromString(SerializersKt.serializer(serializersModule, kTypeTypeOf), strString)).getResults();
            }
            throw new Exception("Error: " + response.code() + " - " + response.message());
        } catch (Exception e) {
            throw new Exception("解析失敗，請嘗試更換域名或參數，並在Github Issue聯繫開發者\n" + e.getMessage(), e);
        }
    }
}
