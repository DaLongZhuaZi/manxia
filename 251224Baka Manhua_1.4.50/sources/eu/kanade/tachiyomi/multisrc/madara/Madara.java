package eu.kanade.tachiyomi.multisrc.madara;

import android.net.Uri;
import android.util.Base64;
import eu.kanade.tachiyomi.lib.cryptoaes.CryptoAES;
import eu.kanade.tachiyomi.lib.i18n.Intl;
import eu.kanade.tachiyomi.network.OkHttpExtensionsKt;
import eu.kanade.tachiyomi.network.RequestsKt;
import eu.kanade.tachiyomi.source.model.Filter;
import eu.kanade.tachiyomi.source.model.FilterList;
import eu.kanade.tachiyomi.source.model.MangasPage;
import eu.kanade.tachiyomi.source.model.Page;
import eu.kanade.tachiyomi.source.model.SChapter;
import eu.kanade.tachiyomi.source.model.SManga;
import eu.kanade.tachiyomi.source.online.ParsedHttpSource;
import eu.kanade.tachiyomi.util.JsoupExtensionsKt;
import java.io.Closeable;
import java.io.IOException;
import java.nio.charset.Charset;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collection;
import java.util.Date;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import kotlin.Lazy;
import kotlin.LazyKt;
import kotlin.Metadata;
import kotlin.NoWhenBranchMatchedException;
import kotlin.Pair;
import kotlin.ResultKt;
import kotlin.TuplesKt;
import kotlin.Unit;
import kotlin.collections.ArraysKt;
import kotlin.collections.CollectionsKt;
import kotlin.collections.MapsKt;
import kotlin.collections.SetsKt;
import kotlin.coroutines.Continuation;
import kotlin.coroutines.CoroutineContext;
import kotlin.coroutines.intrinsics.IntrinsicsKt;
import kotlin.coroutines.jvm.internal.DebugMetadata;
import kotlin.coroutines.jvm.internal.SuspendLambda;
import kotlin.io.CloseableKt;
import kotlin.jvm.functions.Function0;
import kotlin.jvm.functions.Function1;
import kotlin.jvm.functions.Function2;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlin.text.CharsKt;
import kotlin.text.Charsets;
import kotlin.text.MatchResult;
import kotlin.text.Regex;
import kotlin.text.RegexOption;
import kotlin.text.StringsKt;
import kotlinx.coroutines.BuildersKt;
import kotlinx.coroutines.CoroutineScope;
import kotlinx.coroutines.CoroutineScopeKt;
import kotlinx.coroutines.CoroutineStart;
import kotlinx.coroutines.Dispatchers;
import kotlinx.coroutines.Job;
import kotlinx.serialization.json.Json;
import kotlinx.serialization.json.JsonElement;
import kotlinx.serialization.json.JsonElementKt;
import kotlinx.serialization.json.JsonObject;
import kotlinx.serialization.json.JsonPrimitive;
import okhttp3.CacheControl;
import okhttp3.FormBody;
import okhttp3.Headers;
import okhttp3.HttpUrl;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.jsoup.select.Elements;
import rx.Observable;
import rx.functions.Func1;
import uy.kohesive.injekt.InjektKt;
import uy.kohesive.injekt.api.FullTypeReference;
import uy.kohesive.injekt.api.InjektFactory;
import uy.kohesive.injekt.api.TypeReference;

/* compiled from: Madara.kt */
@Metadata(d1 = {"\u0000ú\u0001\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010$\n\u0002\b\t\n\u0002\u0010\u0011\n\u0002\b\u000e\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\b\n\u0002\b\u0006\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\b\u0007\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0006\n\u0002\u0018\u0002\n\u0002\b\"\n\u0002\u0010\u0012\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u000b\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\t\n\u0002\u0010\t\n\u0002\b(\b&\u0018\u0000 ×\u00012\u00020\u0001:\u001eÔ\u0001Õ\u0001Ö\u0001×\u0001Ø\u0001Ù\u0001Ú\u0001Û\u0001Ü\u0001Ý\u0001Þ\u0001ß\u0001à\u0001á\u0001â\u0001B'\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0006\u001a\u00020\u0007¢\u0006\u0002\u0010\bJ\t\u0010\u0089\u0001\u001a\u00020\u0003H\u0014J\u0014\u0010\u008a\u0001\u001a\u00030\u008b\u00012\b\u0010\u008c\u0001\u001a\u00030\u008d\u0001H\u0014J\u001a\u0010\u008e\u0001\u001a\t\u0012\u0005\u0012\u00030\u008b\u0001042\b\u0010\u008f\u0001\u001a\u00030\u0090\u0001H\u0014J\t\u0010\u0091\u0001\u001a\u00020\u0003H\u0014J\u0014\u0010\u0092\u0001\u001a\u00030\u0093\u00012\b\u0010\u0094\u0001\u001a\u00030\u0095\u0001H\u0004J\u0016\u0010\u0096\u0001\u001a\u0005\u0018\u00010\u0097\u00012\b\u0010\u0094\u0001\u001a\u00030\u0095\u0001H\u0014J\u0014\u0010\u0098\u0001\u001a\u00030\u0093\u00012\b\u0010\u0094\u0001\u001a\u00030\u0095\u0001H\u0004J\t\u0010(\u001a\u00030\u0093\u0001H\u0004J-\u0010\u0099\u0001\u001a\n\u0012\u0005\u0012\u00030\u009b\u00010\u009a\u00012\u0007\u0010\u009c\u0001\u001a\u00020-2\u0007\u0010\u009d\u0001\u001a\u00020\u00032\b\u0010\u009e\u0001\u001a\u00030\u009f\u0001H\u0016J\n\u0010 \u0001\u001a\u00030\u0097\u0001H\u0014J\n\u0010¡\u0001\u001a\u00030\u009f\u0001H\u0016J\n\u0010¢\u0001\u001a\u00030£\u0001H\u0014J\u0015\u0010¤\u0001\u001a\u0004\u0018\u00010\u00032\b\u0010\u008c\u0001\u001a\u00030\u008d\u0001H\u0014J\u0014\u0010¥\u0001\u001a\u00030\u0097\u00012\b\u0010\u009c\u0001\u001a\u00030¦\u0001H\u0014J\u0013\u0010§\u0001\u001a\u00020\u00032\b\u0010\u0094\u0001\u001a\u00030\u0095\u0001H\u0014J\u0014\u0010¨\u0001\u001a\u00030©\u00012\b\u0010\u008c\u0001\u001a\u00030\u008d\u0001H\u0014J\u000b\u0010ª\u0001\u001a\u0004\u0018\u00010\u0003H\u0014J\u0014\u0010«\u0001\u001a\u00030\u009b\u00012\b\u0010\u008f\u0001\u001a\u00030\u0090\u0001H\u0014J\u0013\u0010¬\u0001\u001a\u00030\u0097\u00012\u0007\u0010\u009c\u0001\u001a\u00020-H\u0014J\t\u0010\u00ad\u0001\u001a\u00020\u0003H\u0014J\u001b\u0010®\u0001\u001a\u00030¯\u00012\u000f\u0010°\u0001\u001a\n\u0012\u0005\u0012\u00030\u0093\u00010±\u0001H\u0004J\u001c\u0010²\u0001\u001a\u00030\u0097\u00012\u0007\u0010\u009c\u0001\u001a\u00020-2\u0007\u0010³\u0001\u001a\u00020)H\u0004J\u0014\u0010´\u0001\u001a\u00030©\u00012\b\u0010\u0094\u0001\u001a\u00030\u0095\u0001H\u0014J\u0013\u0010µ\u0001\u001a\u00030\u0097\u00012\u0007\u0010¶\u0001\u001a\u00020\u0003H\u0014J\u001a\u0010·\u0001\u001a\t\u0012\u0005\u0012\u00030¦\u0001042\b\u0010\u0094\u0001\u001a\u00030\u0095\u0001H\u0014J\u0014\u0010¸\u0001\u001a\u00030\u0097\u00012\b\u0010¹\u0001\u001a\u00030\u008b\u0001H\u0014J\u0015\u0010º\u0001\u001a\u00030»\u00012\t\u0010¼\u0001\u001a\u0004\u0018\u00010\u0003H\u0016J\u0019\u0010½\u0001\u001a\b\u0012\u0004\u0012\u000205042\b\u0010\u0094\u0001\u001a\u00030\u0095\u0001H\u0014J\u0013\u0010¾\u0001\u001a\u00030»\u00012\u0007\u0010¼\u0001\u001a\u00020\u0003H\u0014J\u0014\u0010¿\u0001\u001a\u00030©\u00012\b\u0010\u008c\u0001\u001a\u00030\u008d\u0001H\u0014J\u000b\u0010À\u0001\u001a\u0004\u0018\u00010\u0003H\u0014J\u0014\u0010Á\u0001\u001a\u00030\u009b\u00012\b\u0010\u008f\u0001\u001a\u00030\u0090\u0001H\u0014J\u0013\u0010Â\u0001\u001a\u00030\u0097\u00012\u0007\u0010\u009c\u0001\u001a\u00020-H\u0014J\t\u0010Ã\u0001\u001a\u00020\u0003H\u0014J&\u0010Ä\u0001\u001a\u00030\u0097\u00012\u0007\u0010\u009c\u0001\u001a\u00020-2\u0007\u0010\u009d\u0001\u001a\u00020\u00032\b\u0010\u009e\u0001\u001a\u00030\u009f\u0001H\u0014J\u0014\u0010Å\u0001\u001a\u00030©\u00012\b\u0010\u008c\u0001\u001a\u00030\u008d\u0001H\u0014J\u000b\u0010Æ\u0001\u001a\u0004\u0018\u00010\u0003H\u0014J\u0014\u0010Ç\u0001\u001a\u00030\u009b\u00012\b\u0010\u008f\u0001\u001a\u00030\u0090\u0001H\u0014J&\u0010È\u0001\u001a\u00030\u0097\u00012\u0007\u0010\u009c\u0001\u001a\u00020-2\u0007\u0010\u009d\u0001\u001a\u00020\u00032\b\u0010\u009e\u0001\u001a\u00030\u009f\u0001H\u0014J\t\u0010É\u0001\u001a\u00020\u0003H\u0014J\u0012\u0010Ê\u0001\u001a\u00020\u00032\u0007\u0010\u009c\u0001\u001a\u00020-H\u0014J&\u0010Ë\u0001\u001a\u00030\u0097\u00012\u0007\u0010\u009c\u0001\u001a\u00020-2\u0007\u0010\u009d\u0001\u001a\u00020\u00032\b\u0010\u009e\u0001\u001a\u00030\u009f\u0001H\u0014J\b\u0010~\u001a\u00020)H\u0004J\u0013\u0010Ì\u0001\u001a\u00030\u0097\u00012\u0007\u0010Í\u0001\u001a\u00020\u0003H\u0014J\"\u0010Î\u0001\u001a\u00020)*\u00020\u00032\r\u0010Ï\u0001\u001a\b\u0012\u0004\u0012\u00020\u00030\u0014H\u0002¢\u0006\u0003\u0010Ð\u0001J\r\u0010Ñ\u0001\u001a\u00020k*\u00020\u0003H\u0004J\u000f\u0010Ò\u0001\u001a\u0004\u0018\u00010\u0003*\u00020\u0003H\u0014J\u000b\u0010Ó\u0001\u001a\u00020)*\u00020\u0003R \u0010\t\u001a\u000e\u0012\u0004\u0012\u00020\u0003\u0012\u0004\u0012\u00020\u00030\nX\u0094\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u000b\u0010\fR\u0014\u0010\r\u001a\u00020\u0003X\u0096\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\u000fR\u0014\u0010\u0010\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\b\u0011\u0010\u000fR\u0014\u0010\u0004\u001a\u00020\u0003X\u0096\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0012\u0010\u000fR\u001c\u0010\u0013\u001a\b\u0012\u0004\u0012\u00020\u00030\u0014X\u0084\u0004¢\u0006\n\n\u0002\u0010\u0017\u001a\u0004\b\u0015\u0010\u0016R\u0014\u0010\u0018\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\b\u0019\u0010\u000fR\u0014\u0010\u001a\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\b\u001b\u0010\u000fR\u0014\u0010\u001c\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\b\u001d\u0010\u000fR\u0014\u0010\u001e\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\b\u001f\u0010\u000fR\u0014\u0010 \u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\b!\u0010\u000fR\u0014\u0010\"\u001a\u00020#X\u0096\u0004¢\u0006\b\n\u0000\u001a\u0004\b$\u0010%R\u001c\u0010&\u001a\b\u0012\u0004\u0012\u00020\u00030\u0014X\u0084\u0004¢\u0006\n\n\u0002\u0010\u0017\u001a\u0004\b'\u0010\u0016R\u000e\u0010\u0006\u001a\u00020\u0007X\u0082\u0004¢\u0006\u0002\n\u0000R\u0014\u0010(\u001a\u00020)X\u0094D¢\u0006\b\n\u0000\u001a\u0004\b*\u0010+R\u000e\u0010,\u001a\u00020-X\u0082\u000e¢\u0006\u0002\n\u0000R\u0014\u0010.\u001a\u00020)X\u0094D¢\u0006\b\n\u0000\u001a\u0004\b/\u0010+R \u00100\u001a\u000e\u0012\u0004\u0012\u00020\u0003\u0012\u0004\u0012\u00020\u00030\nX\u0094\u0004¢\u0006\b\n\u0000\u001a\u0004\b1\u0010\fR\u000e\u00102\u001a\u00020)X\u0082\u000e¢\u0006\u0002\n\u0000R \u00103\u001a\b\u0012\u0004\u0012\u00020504X\u0094\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b6\u00107\"\u0004\b8\u00109R\u001c\u0010:\u001a\b\u0012\u0004\u0012\u00020\u00030\u0014X\u0084\u0004¢\u0006\n\n\u0002\u0010\u0017\u001a\u0004\b;\u0010\u0016R\u0014\u0010<\u001a\u00020=X\u0084\u0004¢\u0006\b\n\u0000\u001a\u0004\b>\u0010?R\u001b\u0010@\u001a\u00020A8TX\u0094\u0084\u0002¢\u0006\f\n\u0004\bD\u0010E\u001a\u0004\bB\u0010CR\u0011\u0010\u0005\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\bF\u0010\u000fR\u000e\u0010G\u001a\u00020HX\u0082\u000e¢\u0006\u0002\n\u0000R\u0014\u0010I\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\bJ\u0010\u000fR\u0014\u0010K\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\bL\u0010\u000fR\u0014\u0010M\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\bN\u0010\u000fR\u0014\u0010O\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\bP\u0010\u000fR\u0014\u0010Q\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\bR\u0010\u000fR\u0014\u0010S\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\bT\u0010\u000fR\u0014\u0010U\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\bV\u0010\u000fR\u0014\u0010W\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\bX\u0010\u000fR\u001b\u0010Y\u001a\u00020\u00038TX\u0094\u0084\u0002¢\u0006\f\n\u0004\b[\u0010E\u001a\u0004\bZ\u0010\u000fR\u0014\u0010\\\u001a\u00020\u0003X\u0094D¢\u0006\b\n\u0000\u001a\u0004\b]\u0010\u000fR\u0014\u0010\u0002\u001a\u00020\u0003X\u0096\u0004¢\u0006\b\n\u0000\u001a\u0004\b^\u0010\u000fR\u000e\u0010_\u001a\u00020)X\u0082\u000e¢\u0006\u0002\n\u0000R\u001c\u0010`\u001a\b\u0012\u0004\u0012\u00020\u00030\u0014X\u0084\u0004¢\u0006\n\n\u0002\u0010\u0017\u001a\u0004\ba\u0010\u0016R \u0010b\u001a\u000e\u0012\u0004\u0012\u00020\u0003\u0012\u0004\u0012\u00020\u00030\nX\u0094\u0004¢\u0006\b\n\u0000\u001a\u0004\bc\u0010\fR\u0014\u0010d\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\be\u0010\u000fR\u0014\u0010f\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\bg\u0010\u000fR\u0014\u0010h\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\bi\u0010\u000fR\u0014\u0010j\u001a\u00020kX\u0084\u0004¢\u0006\b\n\u0000\u001a\u0004\bl\u0010mR\u000e\u0010n\u001a\u00020oX\u0082\u0004¢\u0006\u0002\n\u0000R\u0014\u0010p\u001a\u00020\u0003X\u0094D¢\u0006\b\n\u0000\u001a\u0004\bq\u0010\u000fR\u0014\u0010r\u001a\u00020)X\u0094D¢\u0006\b\n\u0000\u001a\u0004\bs\u0010+R\u0014\u0010t\u001a\u00020\u0003X\u0096D¢\u0006\b\n\u0000\u001a\u0004\bu\u0010\u000fR \u0010v\u001a\u000e\u0012\u0004\u0012\u00020\u0003\u0012\u0004\u0012\u00020\u00030\nX\u0094\u0004¢\u0006\b\n\u0000\u001a\u0004\bw\u0010\fR\u0014\u0010x\u001a\u00020)X\u0096D¢\u0006\b\n\u0000\u001a\u0004\by\u0010+R\u0014\u0010z\u001a\u00020{X\u0096\u0004¢\u0006\b\n\u0000\u001a\u0004\b|\u0010}R\u0016\u0010~\u001a\u00020\u007fX\u0094\u0004¢\u0006\n\n\u0000\u001a\u0006\b\u0080\u0001\u0010\u0081\u0001R\u0016\u0010\u0082\u0001\u001a\u00020)X\u0094D¢\u0006\t\n\u0000\u001a\u0005\b\u0083\u0001\u0010+R \u0010\u0084\u0001\u001a\u00030\u0085\u00018DX\u0084\u0084\u0002¢\u0006\u000f\n\u0005\b\u0088\u0001\u0010E\u001a\u0006\b\u0086\u0001\u0010\u0087\u0001¨\u0006ã\u0001"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara;", "Leu/kanade/tachiyomi/source/online/ParsedHttpSource;", "name", "", "baseUrl", "lang", "dateFormat", "Ljava/text/SimpleDateFormat;", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/text/SimpleDateFormat;)V", "adultContentFilterOptions", "", "getAdultContentFilterOptions", "()Ljava/util/Map;", "altName", "getAltName", "()Ljava/lang/String;", "altNameSelector", "getAltNameSelector", "getBaseUrl", "canceledStatusList", "", "getCanceledStatusList", "()[Ljava/lang/String;", "[Ljava/lang/String;", "chapterProtectorDataPrefix", "getChapterProtectorDataPrefix", "chapterProtectorPasswordPrefix", "getChapterProtectorPasswordPrefix", "chapterProtectorSelector", "getChapterProtectorSelector", "chapterUrlSelector", "getChapterUrlSelector", "chapterUrlSuffix", "getChapterUrlSuffix", "client", "Lokhttp3/OkHttpClient;", "getClient", "()Lokhttp3/OkHttpClient;", "completedStatusList", "getCompletedStatusList", "fetchGenres", "", "getFetchGenres", "()Z", "fetchGenresAttempts", "", "filterNonMangaItems", "getFilterNonMangaItems", "genreConditionFilterOptions", "getGenreConditionFilterOptions", "genresFetched", "genresList", "", "Leu/kanade/tachiyomi/multisrc/madara/Madara$Genre;", "getGenresList", "()Ljava/util/List;", "setGenresList", "(Ljava/util/List;)V", "hiatusStatusList", "getHiatusStatusList", "intl", "Leu/kanade/tachiyomi/lib/i18n/Intl;", "getIntl", "()Leu/kanade/tachiyomi/lib/i18n/Intl;", "json", "Lkotlinx/serialization/json/Json;", "getJson", "()Lkotlinx/serialization/json/Json;", "json$delegate", "Lkotlin/Lazy;", "getLang", "loadMoreRequestDetected", "Leu/kanade/tachiyomi/multisrc/madara/Madara$LoadMoreDetection;", "mangaDetailsSelectorArtist", "getMangaDetailsSelectorArtist", "mangaDetailsSelectorAuthor", "getMangaDetailsSelectorAuthor", "mangaDetailsSelectorDescription", "getMangaDetailsSelectorDescription", "mangaDetailsSelectorGenre", "getMangaDetailsSelectorGenre", "mangaDetailsSelectorStatus", "getMangaDetailsSelectorStatus", "mangaDetailsSelectorTag", "getMangaDetailsSelectorTag", "mangaDetailsSelectorThumbnail", "getMangaDetailsSelectorThumbnail", "mangaDetailsSelectorTitle", "getMangaDetailsSelectorTitle", "mangaEntrySelector", "getMangaEntrySelector", "mangaEntrySelector$delegate", "mangaSubString", "getMangaSubString", "getName", "oldChapterEndpointDisabled", "ongoingStatusList", "getOngoingStatusList", "orderByFilterOptions", "getOrderByFilterOptions", "pageListParseSelector", "getPageListParseSelector", "popularMangaUrlSelector", "getPopularMangaUrlSelector", "popularMangaUrlSelectorImg", "getPopularMangaUrlSelectorImg", "salted", "", "getSalted", "()[B", "scope", "Lkotlinx/coroutines/CoroutineScope;", "searchMangaUrlSelector", "getSearchMangaUrlSelector", "sendViewCount", "getSendViewCount", "seriesTypeSelector", "getSeriesTypeSelector", "statusFilterOptions", "getStatusFilterOptions", "supportsLatest", "getSupportsLatest", "updatingRegex", "Lkotlin/text/Regex;", "getUpdatingRegex", "()Lkotlin/text/Regex;", "useLoadMoreRequest", "Leu/kanade/tachiyomi/multisrc/madara/Madara$LoadMoreStrategy;", "getUseLoadMoreRequest", "()Leu/kanade/tachiyomi/multisrc/madara/Madara$LoadMoreStrategy;", "useNewChapterEndpoint", "getUseNewChapterEndpoint", "xhrHeaders", "Lokhttp3/Headers;", "getXhrHeaders", "()Lokhttp3/Headers;", "xhrHeaders$delegate", "chapterDateSelector", "chapterFromElement", "Leu/kanade/tachiyomi/source/model/SChapter;", "element", "Lorg/jsoup/nodes/Element;", "chapterListParse", "response", "Lokhttp3/Response;", "chapterListSelector", "countViews", "", "document", "Lorg/jsoup/nodes/Document;", "countViewsRequest", "Lokhttp3/Request;", "detectLoadMore", "fetchSearchManga", "Lrx/Observable;", "Leu/kanade/tachiyomi/source/model/MangasPage;", "page", "query", "filters", "Leu/kanade/tachiyomi/source/model/FilterList;", "genresRequest", "getFilterList", "headersBuilder", "Lokhttp3/Headers$Builder;", "imageFromElement", "imageRequest", "Leu/kanade/tachiyomi/source/model/Page;", "imageUrlParse", "latestUpdatesFromElement", "Leu/kanade/tachiyomi/source/model/SManga;", "latestUpdatesNextPageSelector", "latestUpdatesParse", "latestUpdatesRequest", "latestUpdatesSelector", "launchIO", "Lkotlinx/coroutines/Job;", "block", "Lkotlin/Function0;", "loadMoreRequest", "popular", "mangaDetailsParse", "oldXhrChaptersRequest", "mangaId", "pageListParse", "pageListRequest", "chapter", "parseChapterDate", "", "date", "parseGenres", "parseRelativeDate", "popularMangaFromElement", "popularMangaNextPageSelector", "popularMangaParse", "popularMangaRequest", "popularMangaSelector", "searchLoadMoreRequest", "searchMangaFromElement", "searchMangaNextPageSelector", "searchMangaParse", "searchMangaRequest", "searchMangaSelector", "searchPage", "searchRequest", "xhrChaptersRequest", "mangaUrl", "containsIn", "array", "(Ljava/lang/String;[Ljava/lang/String;)Z", "decodeHex", "getSrcSetImage", "notUpdating", "AdultContentFilter", "ArtistFilter", "AuthorFilter", "Companion", "Genre", "GenreCheckBox", "GenreConditionFilter", "GenreList", "LoadMoreDetection", "LoadMoreStrategy", "OrderByFilter", "StatusFilter", "Tag", "UriPartFilter", "YearFilter", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public abstract class Madara extends ParsedHttpSource {

    /* renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private static final Regex URL_REGEX = new Regex("^(https?://[^\\s/$.?#].[^\\s]*)$");
    public static final String URL_SEARCH_PREFIX = "slug:";
    private final Map<String, String> adultContentFilterOptions;
    private final String altName;
    private final String altNameSelector;
    private final String baseUrl;
    private final String[] canceledStatusList;
    private final String chapterProtectorDataPrefix;
    private final String chapterProtectorPasswordPrefix;
    private final String chapterProtectorSelector;
    private final String chapterUrlSelector;
    private final String chapterUrlSuffix;
    private final OkHttpClient client;
    private final String[] completedStatusList;
    private final SimpleDateFormat dateFormat;
    private final boolean fetchGenres;
    private int fetchGenresAttempts;
    private final boolean filterNonMangaItems;
    private final Map<String, String> genreConditionFilterOptions;
    private boolean genresFetched;
    private List<Genre> genresList;
    private final String[] hiatusStatusList;
    private final Intl intl;

    /* renamed from: json$delegate, reason: from kotlin metadata */
    private final Lazy json;
    private final String lang;
    private LoadMoreDetection loadMoreRequestDetected;
    private final String mangaDetailsSelectorArtist;
    private final String mangaDetailsSelectorAuthor;
    private final String mangaDetailsSelectorDescription;
    private final String mangaDetailsSelectorGenre;
    private final String mangaDetailsSelectorStatus;
    private final String mangaDetailsSelectorTag;
    private final String mangaDetailsSelectorThumbnail;
    private final String mangaDetailsSelectorTitle;

    /* renamed from: mangaEntrySelector$delegate, reason: from kotlin metadata */
    private final Lazy mangaEntrySelector;
    private final String mangaSubString;
    private final String name;
    private boolean oldChapterEndpointDisabled;
    private final String[] ongoingStatusList;
    private final Map<String, String> orderByFilterOptions;
    private final String pageListParseSelector;
    private final String popularMangaUrlSelector;
    private final String popularMangaUrlSelectorImg;
    private final byte[] salted;
    private final CoroutineScope scope;
    private final String searchMangaUrlSelector;
    private final boolean sendViewCount;
    private final String seriesTypeSelector;
    private final Map<String, String> statusFilterOptions;
    private final boolean supportsLatest;
    private final Regex updatingRegex;
    private final LoadMoreStrategy useLoadMoreRequest;
    private final boolean useNewChapterEndpoint;

    /* renamed from: xhrHeaders$delegate, reason: from kotlin metadata */
    private final Lazy xhrHeaders;

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\f\n\u0002\u0018\u0002\n\u0002\u0010\u0010\n\u0002\b\u0005\b\u0082\u0001\u0018\u00002\b\u0012\u0004\u0012\u00020\u00000\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002j\u0002\b\u0003j\u0002\b\u0004j\u0002\b\u0005¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$LoadMoreDetection;", "", "(Ljava/lang/String;I)V", "Pending", "True", "False", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    private enum LoadMoreDetection {
        Pending,
        True,
        False
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\f\n\u0002\u0018\u0002\n\u0002\u0010\u0010\n\u0002\b\u0005\b\u0086\u0001\u0018\u00002\b\u0012\u0004\u0012\u00020\u00000\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002j\u0002\b\u0003j\u0002\b\u0004j\u0002\b\u0005¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$LoadMoreStrategy;", "", "(Ljava/lang/String;I)V", "AutoDetect", "Always", "Never", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public enum LoadMoreStrategy {
        AutoDetect,
        Always,
        Never
    }

    /* compiled from: Madara.kt */
    @Metadata(k = 3, mv = {1, 7, 1}, xi = 48)
    public /* synthetic */ class WhenMappings {
        public static final /* synthetic */ int[] $EnumSwitchMapping$0;

        static {
            int[] iArr = new int[LoadMoreStrategy.values().length];
            try {
                iArr[LoadMoreStrategy.Always.ordinal()] = 1;
            } catch (NoSuchFieldError e) {
            }
            try {
                iArr[LoadMoreStrategy.Never.ordinal()] = 2;
            } catch (NoSuchFieldError e2) {
            }
            $EnumSwitchMapping$0 = iArr;
        }
    }

    public /* synthetic */ Madara(String str, String str2, String str3, SimpleDateFormat simpleDateFormat, int i, DefaultConstructorMarker defaultConstructorMarker) {
        this(str, str2, str3, (i & 8) != 0 ? new SimpleDateFormat("MMMM dd, yyyy", Locale.US) : simpleDateFormat);
    }

    public String getName() {
        return this.name;
    }

    public String getBaseUrl() {
        return this.baseUrl;
    }

    public final String getLang() {
        return this.lang;
    }

    public Madara(String name, String baseUrl, String lang, SimpleDateFormat dateFormat) {
        Intrinsics.checkNotNullParameter(name, "name");
        Intrinsics.checkNotNullParameter(baseUrl, "baseUrl");
        Intrinsics.checkNotNullParameter(lang, "lang");
        Intrinsics.checkNotNullParameter(dateFormat, "dateFormat");
        this.name = name;
        this.baseUrl = baseUrl;
        this.lang = lang;
        this.dateFormat = dateFormat;
        this.supportsLatest = true;
        this.client = getNetwork().getCloudflareClient();
        this.xhrHeaders = LazyKt.lazy(new Function0<Headers>() { // from class: eu.kanade.tachiyomi.multisrc.madara.Madara$xhrHeaders$2
            {
                super(0);
            }

            public final Headers invoke() {
                return this.this$0.headersBuilder().set("X-Requested-With", "XMLHttpRequest").build();
            }
        });
        this.json = LazyKt.lazy(new Function0<Json>() { // from class: eu.kanade.tachiyomi.multisrc.madara.Madara$special$$inlined$injectLazy$1
            /* JADX WARN: Type inference failed for: r0v2, types: [java.lang.Object, kotlinx.serialization.json.Json] */
            public final Json invoke() {
                InjektFactory $receiver$iv = InjektKt.getInjekt();
                TypeReference forType$iv = (FullTypeReference) new FullTypeReference<Json>() { // from class: eu.kanade.tachiyomi.multisrc.madara.Madara$special$$inlined$injectLazy$1.1
                };
                return $receiver$iv.getInstance(forType$iv.getType());
            }
        });
        String str = this.lang;
        Set of = SetsKt.setOf(new String[]{"en", "pt-BR", "es"});
        ClassLoader classLoader = getClass().getClassLoader();
        Intrinsics.checkNotNull(classLoader);
        this.intl = new Intl(str, of, "en", classLoader, null, 16, null);
        this.filterNonMangaItems = true;
        this.mangaEntrySelector = LazyKt.lazy(new Function0<String>() { // from class: eu.kanade.tachiyomi.multisrc.madara.Madara$mangaEntrySelector$2
            {
                super(0);
            }

            public final String invoke() {
                return this.this$0.getFilterNonMangaItems() ? ".manga" : "";
            }
        });
        this.genresList = CollectionsKt.emptyList();
        this.fetchGenres = true;
        this.mangaSubString = "manga";
        this.useLoadMoreRequest = LoadMoreStrategy.AutoDetect;
        this.loadMoreRequestDetected = LoadMoreDetection.Pending;
        this.popularMangaUrlSelector = "div.post-title a";
        this.popularMangaUrlSelectorImg = "img";
        this.statusFilterOptions = MapsKt.mapOf(new Pair[]{TuplesKt.to(this.intl.get("status_filter_completed"), "end"), TuplesKt.to(this.intl.get("status_filter_ongoing"), "on-going"), TuplesKt.to(this.intl.get("status_filter_canceled"), "canceled"), TuplesKt.to(this.intl.get("status_filter_on_hold"), "on-hold")});
        this.orderByFilterOptions = MapsKt.mapOf(new Pair[]{TuplesKt.to(this.intl.get("order_by_filter_relevance"), ""), TuplesKt.to(this.intl.get("order_by_filter_latest"), "latest"), TuplesKt.to(this.intl.get("order_by_filter_az"), "alphabet"), TuplesKt.to(this.intl.get("order_by_filter_rating"), "rating"), TuplesKt.to(this.intl.get("order_by_filter_trending"), "trending"), TuplesKt.to(this.intl.get("order_by_filter_views"), "views"), TuplesKt.to(this.intl.get("order_by_filter_new"), "new-manga")});
        this.genreConditionFilterOptions = MapsKt.mapOf(new Pair[]{TuplesKt.to(this.intl.get("genre_condition_filter_or"), ""), TuplesKt.to(this.intl.get("genre_condition_filter_and"), "1")});
        this.adultContentFilterOptions = MapsKt.mapOf(new Pair[]{TuplesKt.to(this.intl.get("adult_content_filter_all"), ""), TuplesKt.to(this.intl.get("adult_content_filter_none"), "0"), TuplesKt.to(this.intl.get("adult_content_filter_only"), "1")});
        this.searchMangaUrlSelector = "div.post-title a";
        this.completedStatusList = new String[]{"Completed", "Completo", "Completado", "Concluído", "Concluido", "Finalizado", "Achevé", "Terminé", "Hoàn Thành", "مكتملة", "مكتمل", "已完结", "Tamamlandı", "Đã hoàn thành", "Завершено", "Tamamlanan", "Complété"};
        this.ongoingStatusList = new String[]{"OnGoing", "Продолжается", "Updating", "Em Lançamento", "Em lançamento", "Em andamento", "Em Andamento", "En cours", "En Cours", "En cours de publication", "Ativo", "Lançando", "Đang Tiến Hành", "Devam Ediyor", "Devam ediyor", "In Corso", "In Arrivo", "مستمرة", "مستمر", "En Curso", "En curso", "Emision", "Curso", "En marcha", "Publicandose", "Publicándose", "En emision", "连载中", "Em Lançamento", "Devam Ediyo", "Đang làm", "Em postagem", "Devam Eden", "Em progresso", "Em curso", "Atualizações Semanais"};
        this.hiatusStatusList = new String[]{"On Hold", "Pausado", "En espera", "Durduruldu", "Beklemede", "Đang chờ", "متوقف", "En Pause", "Заморожено", "En attente"};
        this.canceledStatusList = new String[]{"Canceled", "Cancelado", "İptal Edildi", "Güncel", "Đã hủy", "ملغي", "Abandonné", "Заброшено", "Annulé"};
        this.mangaDetailsSelectorTitle = "div.post-title h3, div.post-title h1, #manga-title > h1";
        this.mangaDetailsSelectorAuthor = "div.author-content > a, div.manga-authors > a";
        this.mangaDetailsSelectorArtist = "div.artist-content > a";
        this.mangaDetailsSelectorStatus = "div.summary-content, div.summary-heading:contains(Status) + div";
        this.mangaDetailsSelectorDescription = "div.description-summary div.summary__content, div.summary_content div.post-content_item > h5 + div, div.summary_content div.manga-excerpt";
        this.mangaDetailsSelectorThumbnail = "div.summary_image img";
        this.mangaDetailsSelectorGenre = "div.genres-content a";
        this.mangaDetailsSelectorTag = "div.tags-content a";
        this.seriesTypeSelector = ".post-content_item:contains(Type) .summary-content";
        this.altNameSelector = ".post-content_item:contains(Alt) .summary-content";
        this.altName = this.intl.get("alt_names_heading");
        this.updatingRegex = new Regex("Updating|Atualizando", RegexOption.IGNORE_CASE);
        this.chapterUrlSelector = "a";
        this.chapterUrlSuffix = "?style=list";
        this.pageListParseSelector = "div.page-break, li.blocks-gallery-item, .reading-content .text-left:not(:has(.blocks-gallery-item)) img";
        this.chapterProtectorSelector = "#chapter-protector-data";
        this.chapterProtectorPasswordPrefix = "wpmangaprotectornonce='";
        this.chapterProtectorDataPrefix = "chapter_data='";
        this.sendViewCount = true;
        byte[] bytes = "Salted__".getBytes(Charsets.UTF_8);
        Intrinsics.checkNotNullExpressionValue(bytes, "this as java.lang.String).getBytes(charset)");
        this.salted = bytes;
        this.scope = CoroutineScopeKt.CoroutineScope(Dispatchers.getIO());
    }

    public boolean getSupportsLatest() {
        return this.supportsLatest;
    }

    public OkHttpClient getClient() {
        return this.client;
    }

    protected Headers.Builder headersBuilder() {
        return super.headersBuilder().add("Referer", getBaseUrl() + '/');
    }

    protected final Headers getXhrHeaders() {
        return (Headers) this.xhrHeaders.getValue();
    }

    protected Json getJson() {
        return (Json) this.json.getValue();
    }

    protected final Intl getIntl() {
        return this.intl;
    }

    protected boolean getFilterNonMangaItems() {
        return this.filterNonMangaItems;
    }

    protected String getMangaEntrySelector() {
        return (String) this.mangaEntrySelector.getValue();
    }

    protected List<Genre> getGenresList() {
        return this.genresList;
    }

    protected void setGenresList(List<Genre> list) {
        Intrinsics.checkNotNullParameter(list, "<set-?>");
        this.genresList = list;
    }

    protected boolean getFetchGenres() {
        return this.fetchGenres;
    }

    protected String getMangaSubString() {
        return this.mangaSubString;
    }

    protected LoadMoreStrategy getUseLoadMoreRequest() {
        return this.useLoadMoreRequest;
    }

    /* JADX INFO: Thrown type has an unknown type hierarchy: kotlin.NoWhenBranchMatchedException */
    protected final void detectLoadMore(Document document) throws NoWhenBranchMatchedException {
        LoadMoreDetection loadMoreDetection;
        Intrinsics.checkNotNullParameter(document, "document");
        if (getUseLoadMoreRequest() == LoadMoreStrategy.AutoDetect && this.loadMoreRequestDetected == LoadMoreDetection.Pending) {
            boolean z = document.selectFirst("nav.navigation-ajax") != null;
            if (z) {
                loadMoreDetection = LoadMoreDetection.True;
            } else {
                if (z) {
                    throw new NoWhenBranchMatchedException();
                }
                loadMoreDetection = LoadMoreDetection.False;
            }
            this.loadMoreRequestDetected = loadMoreDetection;
        }
    }

    protected final boolean useLoadMoreRequest() {
        switch (WhenMappings.$EnumSwitchMapping$0[getUseLoadMoreRequest().ordinal()]) {
            case 1:
                break;
            case 2:
                break;
            default:
                if (this.loadMoreRequestDetected == LoadMoreDetection.True) {
                }
                break;
        }
        return false;
    }

    protected MangasPage popularMangaParse(Response response) throws NoWhenBranchMatchedException {
        Intrinsics.checkNotNullParameter(response, "response");
        Element elementSelectFirst = null;
        Document document = JsoupExtensionsKt.asJsoup$default(response, (String) null, 1, (Object) null);
        Iterable iterableSelect = document.select(popularMangaSelector());
        Intrinsics.checkNotNullExpressionValue(iterableSelect, "document.select(popularMangaSelector())");
        Iterable $this$map$iv = iterableSelect;
        Collection destination$iv$iv = new ArrayList(CollectionsKt.collectionSizeOrDefault($this$map$iv, 10));
        for (Object item$iv$iv : $this$map$iv) {
            Element p0 = (Element) item$iv$iv;
            destination$iv$iv.add(popularMangaFromElement(p0));
        }
        List entries = (List) destination$iv$iv;
        String it = popularMangaNextPageSelector();
        if (it != null) {
            elementSelectFirst = document.selectFirst(it);
        }
        boolean hasNextPage = elementSelectFirst != null;
        detectLoadMore(document);
        return new MangasPage(entries, hasNextPage);
    }

    protected String popularMangaSelector() {
        return "div.page-item-detail:not(:has(a[href*='bilibilicomics.com']))" + getMangaEntrySelector() + " , .manga__item";
    }

    public String getPopularMangaUrlSelector() {
        return this.popularMangaUrlSelector;
    }

    public String getPopularMangaUrlSelectorImg() {
        return this.popularMangaUrlSelectorImg;
    }

    protected SManga popularMangaFromElement(Element element) {
        Intrinsics.checkNotNullParameter(element, "element");
        SManga manga = SManga.Companion.create();
        Element it = element.selectFirst(getPopularMangaUrlSelector());
        Intrinsics.checkNotNull(it);
        String strAttr = it.attr("abs:href");
        Intrinsics.checkNotNullExpressionValue(strAttr, "it.attr(\"abs:href\")");
        setUrlWithoutDomain(manga, strAttr);
        String strOwnText = it.ownText();
        Intrinsics.checkNotNullExpressionValue(strOwnText, "it.ownText()");
        manga.setTitle(strOwnText);
        Element it2 = element.selectFirst(getPopularMangaUrlSelectorImg());
        if (it2 != null) {
            Intrinsics.checkNotNullExpressionValue(it2, "it");
            manga.setThumbnail_url(imageFromElement(it2));
        }
        return manga;
    }

    protected Request popularMangaRequest(int page) {
        if (useLoadMoreRequest()) {
            return loadMoreRequest(page, true);
        }
        return RequestsKt.GET$default(getBaseUrl() + '/' + getMangaSubString() + '/' + searchPage(page) + "?m_orderby=views", getHeaders(), (CacheControl) null, 4, (Object) null);
    }

    protected String popularMangaNextPageSelector() {
        if (useLoadMoreRequest()) {
            return "body:not(:has(.no-posts))";
        }
        return "div.nav-previous, nav.navigation-ajax, a.nextpostslink";
    }

    protected String latestUpdatesSelector() {
        return popularMangaSelector();
    }

    protected SManga latestUpdatesFromElement(Element element) {
        Intrinsics.checkNotNullParameter(element, "element");
        return popularMangaFromElement(element);
    }

    protected Request latestUpdatesRequest(int page) {
        if (useLoadMoreRequest()) {
            return loadMoreRequest(page, false);
        }
        return RequestsKt.GET$default(getBaseUrl() + '/' + getMangaSubString() + '/' + searchPage(page) + "?m_orderby=latest", getHeaders(), (CacheControl) null, 4, (Object) null);
    }

    protected String latestUpdatesNextPageSelector() {
        return popularMangaNextPageSelector();
    }

    protected MangasPage latestUpdatesParse(Response response) throws NoWhenBranchMatchedException {
        Intrinsics.checkNotNullParameter(response, "response");
        MangasPage mp = popularMangaParse(response);
        Iterable $this$distinctBy$iv = mp.getMangas();
        HashSet set$iv = new HashSet();
        ArrayList list$iv = new ArrayList();
        for (Object e$iv : $this$distinctBy$iv) {
            SManga it = (SManga) e$iv;
            if (set$iv.add(it.getUrl())) {
                list$iv.add(e$iv);
            }
        }
        ArrayList mangas = list$iv;
        return new MangasPage(mangas, mp.getHasNextPage());
    }

    protected final Request loadMoreRequest(int page, boolean popular) {
        FormBody.Builder $this$loadMoreRequest_u24lambda_u245 = new FormBody.Builder((Charset) null, 1, (DefaultConstructorMarker) null);
        $this$loadMoreRequest_u24lambda_u245.add("action", "madara_load_more");
        $this$loadMoreRequest_u24lambda_u245.add("page", String.valueOf(page - 1));
        $this$loadMoreRequest_u24lambda_u245.add("template", "madara-core/content/content-archive");
        $this$loadMoreRequest_u24lambda_u245.add("vars[orderby]", "meta_value_num");
        $this$loadMoreRequest_u24lambda_u245.add("vars[paged]", "1");
        $this$loadMoreRequest_u24lambda_u245.add("vars[post_type]", "wp-manga");
        $this$loadMoreRequest_u24lambda_u245.add("vars[post_status]", "publish");
        $this$loadMoreRequest_u24lambda_u245.add("vars[meta_key]", popular ? "_wp_manga_views" : "_latest_update");
        $this$loadMoreRequest_u24lambda_u245.add("vars[order]", "desc");
        $this$loadMoreRequest_u24lambda_u245.add("vars[sidebar]", "right");
        $this$loadMoreRequest_u24lambda_u245.add("vars[manga_archives_item_layout]", "big_thumbnail");
        return RequestsKt.POST$default(getBaseUrl() + "/wp-admin/admin-ajax.php", getXhrHeaders(), $this$loadMoreRequest_u24lambda_u245.build(), (CacheControl) null, 8, (Object) null);
    }

    public Observable<MangasPage> fetchSearchManga(int page, String query, FilterList filters) {
        Intrinsics.checkNotNullParameter(query, "query");
        Intrinsics.checkNotNullParameter(filters, "filters");
        if (StringsKt.startsWith$default(query, URL_SEARCH_PREFIX, false, 2, (Object) null)) {
            HttpUrl.Builder $this$fetchSearchManga_u24lambda_u246 = HttpUrl.Companion.get(getBaseUrl()).newBuilder();
            $this$fetchSearchManga_u24lambda_u246.addPathSegment(getMangaSubString());
            $this$fetchSearchManga_u24lambda_u246.addPathSegment(StringsKt.substringAfter$default(query, URL_SEARCH_PREFIX, (String) null, 2, (Object) null));
            $this$fetchSearchManga_u24lambda_u246.addPathSegment("");
            final HttpUrl mangaUrl = $this$fetchSearchManga_u24lambda_u246.build();
            Observable observableAsObservableSuccess = OkHttpExtensionsKt.asObservableSuccess(getClient().newCall(RequestsKt.GET$default(mangaUrl, getHeaders(), (CacheControl) null, 4, (Object) null)));
            final Function1<Response, MangasPage> function1 = new Function1<Response, MangasPage>() { // from class: eu.kanade.tachiyomi.multisrc.madara.Madara.fetchSearchManga.1
                /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
                {
                    super(1);
                }

                public final MangasPage invoke(Response response) {
                    Madara madara = Madara.this;
                    Intrinsics.checkNotNullExpressionValue(response, "response");
                    SManga manga = madara.mangaDetailsParse(response);
                    Madara.this.setUrlWithoutDomain(manga, mangaUrl.toString());
                    manga.setInitialized(true);
                    return new MangasPage(CollectionsKt.listOf(manga), false);
                }
            };
            Observable<MangasPage> map = observableAsObservableSuccess.map(new Func1() { // from class: eu.kanade.tachiyomi.multisrc.madara.Madara$$ExternalSyntheticLambda0
                public final Object call(Object obj) {
                    return Madara.fetchSearchManga$lambda$7(function1, obj);
                }
            });
            Intrinsics.checkNotNullExpressionValue(map, "override fun fetchSearch…ge, query, filters)\n    }");
            return map;
        }
        return super.fetchSearchManga(page, query, filters);
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final MangasPage fetchSearchManga$lambda$7(Function1 $tmp0, Object p0) {
        Intrinsics.checkNotNullParameter($tmp0, "$tmp0");
        return (MangasPage) $tmp0.invoke(p0);
    }

    protected String searchPage(int page) {
        if (page == 1) {
            return "";
        }
        return "page/" + page + '/';
    }

    protected Request searchMangaRequest(int page, String query, FilterList filters) {
        Intrinsics.checkNotNullParameter(query, "query");
        Intrinsics.checkNotNullParameter(filters, "filters");
        if (useLoadMoreRequest()) {
            return searchLoadMoreRequest(page, query, filters);
        }
        return searchRequest(page, query, filters);
    }

    protected Request searchRequest(int page, String query, FilterList filters) {
        Intrinsics.checkNotNullParameter(query, "query");
        Intrinsics.checkNotNullParameter(filters, "filters");
        HttpUrl.Builder url = HttpUrl.Companion.get(getBaseUrl() + '/' + searchPage(page)).newBuilder();
        url.addQueryParameter("s", query);
        url.addQueryParameter("post_type", "wp-manga");
        Iterable $this$forEach$iv = (Iterable) filters;
        for (Object element$iv : $this$forEach$iv) {
            Filter filter = (Filter) element$iv;
            if (filter instanceof AuthorFilter) {
                if (!StringsKt.isBlank((CharSequence) ((AuthorFilter) filter).getState())) {
                    url.addQueryParameter("author", (String) ((AuthorFilter) filter).getState());
                }
            } else if (filter instanceof ArtistFilter) {
                if (!StringsKt.isBlank((CharSequence) ((ArtistFilter) filter).getState())) {
                    url.addQueryParameter("artist", (String) ((ArtistFilter) filter).getState());
                }
            } else if (filter instanceof YearFilter) {
                if (!StringsKt.isBlank((CharSequence) ((YearFilter) filter).getState())) {
                    url.addQueryParameter("release", (String) ((YearFilter) filter).getState());
                }
            } else if (filter instanceof StatusFilter) {
                Iterable $this$forEach$iv2 = (Iterable) ((StatusFilter) filter).getState();
                for (Object element$iv2 : $this$forEach$iv2) {
                    Tag it = (Tag) element$iv2;
                    if (((Boolean) it.getState()).booleanValue()) {
                        url.addQueryParameter("status[]", it.getId());
                    }
                }
            } else if (filter instanceof OrderByFilter) {
                if (((Number) ((OrderByFilter) filter).getState()).intValue() != 0) {
                    url.addQueryParameter("m_orderby", ((OrderByFilter) filter).toUriPart());
                }
            } else if (filter instanceof AdultContentFilter) {
                url.addQueryParameter("adult", ((AdultContentFilter) filter).toUriPart());
            } else if (filter instanceof GenreConditionFilter) {
                url.addQueryParameter("op", ((GenreConditionFilter) filter).toUriPart());
            } else if (filter instanceof GenreList) {
                Iterable $this$filter$iv = (Iterable) ((GenreList) filter).getState();
                Collection destination$iv$iv = new ArrayList();
                for (Object element$iv$iv : $this$filter$iv) {
                    if (((Boolean) ((GenreCheckBox) element$iv$iv).getState()).booleanValue()) {
                        destination$iv$iv.add(element$iv$iv);
                    }
                }
                Iterable list = (List) destination$iv$iv;
                int i = 0;
                if (!((Collection) list).isEmpty()) {
                    Iterable $this$forEach$iv3 = list;
                    for (Object element$iv3 : $this$forEach$iv3) {
                        GenreCheckBox genre = (GenreCheckBox) element$iv3;
                        url.addQueryParameter("genre[]", genre.getId());
                        i = i;
                    }
                }
            }
        }
        return RequestsKt.GET$default(url.build(), getHeaders(), (CacheControl) null, 4, (Object) null);
    }

    /* JADX WARN: Multi-variable type inference failed */
    /* JADX WARN: Removed duplicated region for block: B:101:0x0466 A[PHI: r21
  0x0466: PHI (r21v9 java.lang.Iterable) = 
  (r21v3 java.lang.Iterable)
  (r21v4 java.lang.Iterable)
  (r21v5 java.lang.Iterable)
  (r21v6 java.lang.Iterable)
  (r21v8 java.lang.Iterable)
  (r21v10 java.lang.Iterable)
 binds: [B:99:0x0457, B:95:0x0440, B:91:0x0428, B:87:0x0410, B:84:0x03f6, B:81:0x03ea] A[DONT_GENERATE, DONT_INLINE]] */
    /* JADX WARN: Type inference failed for: r8v13 */
    /*
        Code decompiled incorrectly, please refer to instructions dump.
        To view partially-correct code enable 'Show inconsistent code' option in preferences
    */
    protected okhttp3.Request searchLoadMoreRequest(int r28, java.lang.String r29, eu.kanade.tachiyomi.source.model.FilterList r30) {
        /*
            Method dump skipped, instructions count: 1542
            To view this dump change 'Code comments level' option to 'DEBUG'
        */
        throw new UnsupportedOperationException("Method not decompiled: eu.kanade.tachiyomi.multisrc.madara.Madara.searchLoadMoreRequest(int, java.lang.String, eu.kanade.tachiyomi.source.model.FilterList):okhttp3.Request");
    }

    protected Map<String, String> getStatusFilterOptions() {
        return this.statusFilterOptions;
    }

    protected Map<String, String> getOrderByFilterOptions() {
        return this.orderByFilterOptions;
    }

    protected Map<String, String> getGenreConditionFilterOptions() {
        return this.genreConditionFilterOptions;
    }

    protected Map<String, String> getAdultContentFilterOptions() {
        return this.adultContentFilterOptions;
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0010\u0011\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\b\n\u0002\b\u0004\b\u0016\u0018\u00002\b\u0012\u0004\u0012\u00020\u00020\u0001B1\u0012\u0006\u0010\u0003\u001a\u00020\u0002\u0012\u0018\u0010\u0004\u001a\u0014\u0012\u0010\u0012\u000e\u0012\u0004\u0012\u00020\u0002\u0012\u0004\u0012\u00020\u00020\u00060\u0005\u0012\b\b\u0002\u0010\u0007\u001a\u00020\b¢\u0006\u0002\u0010\tJ\u0006\u0010\u000b\u001a\u00020\u0002R\"\u0010\u0004\u001a\u0014\u0012\u0010\u0012\u000e\u0012\u0004\u0012\u00020\u0002\u0012\u0004\u0012\u00020\u00020\u00060\u0005X\u0082\u0004¢\u0006\u0004\n\u0002\u0010\n¨\u0006\f"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$UriPartFilter;", "Leu/kanade/tachiyomi/source/model/Filter$Select;", "", "displayName", "vals", "", "Lkotlin/Pair;", "state", "", "(Ljava/lang/String;[Lkotlin/Pair;I)V", "[Lkotlin/Pair;", "toUriPart", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static class UriPartFilter extends Filter.Select<String> {
        private final Pair<String, String>[] vals;

        public /* synthetic */ UriPartFilter(String str, Pair[] pairArr, int i, int i2, DefaultConstructorMarker defaultConstructorMarker) {
            this(str, pairArr, (i2 & 4) != 0 ? 0 : i);
        }

        public UriPartFilter(String displayName, Pair<String, String>[] pairArr, int state) {
            Intrinsics.checkNotNullParameter(displayName, "displayName");
            Intrinsics.checkNotNullParameter(pairArr, "vals");
            Collection destination$iv$iv = new ArrayList(pairArr.length);
            for (Pair<String, String> pair : pairArr) {
                destination$iv$iv.add((String) pair.getFirst());
            }
            Collection $this$toTypedArray$iv = (List) destination$iv$iv;
            super(displayName, $this$toTypedArray$iv.toArray(new String[0]), state);
            this.vals = pairArr;
        }

        public final String toUriPart() {
            return (String) this.vals[((Number) getState()).intValue()].getSecond();
        }
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\u0012\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0005\b\u0016\u0018\u00002\u00020\u0001B\u0015\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003¢\u0006\u0002\u0010\u0005R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0006\u0010\u0007¨\u0006\b"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$Tag;", "Leu/kanade/tachiyomi/source/model/Filter$CheckBox;", "name", "", "id", "(Ljava/lang/String;Ljava/lang/String;)V", "getId", "()Ljava/lang/String;", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static class Tag extends Filter.CheckBox {
        private final String id;

        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        public Tag(String name, String id) {
            super(name, false, 2, (DefaultConstructorMarker) null);
            Intrinsics.checkNotNullParameter(name, "name");
            Intrinsics.checkNotNullParameter(id, "id");
            this.id = id;
        }

        public final String getId() {
            return this.id;
        }
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\u0012\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0004\u0018\u00002\u00020\u0001B\r\u0012\u0006\u0010\u0002\u001a\u00020\u0003¢\u0006\u0002\u0010\u0004¨\u0006\u0005"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$AuthorFilter;", "Leu/kanade/tachiyomi/source/model/Filter$Text;", "title", "", "(Ljava/lang/String;)V", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    protected static final class AuthorFilter extends Filter.Text {
        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        public AuthorFilter(String title) {
            super(title, (String) null, 2, (DefaultConstructorMarker) null);
            Intrinsics.checkNotNullParameter(title, "title");
        }
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\u0012\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0004\u0018\u00002\u00020\u0001B\r\u0012\u0006\u0010\u0002\u001a\u00020\u0003¢\u0006\u0002\u0010\u0004¨\u0006\u0005"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$ArtistFilter;", "Leu/kanade/tachiyomi/source/model/Filter$Text;", "title", "", "(Ljava/lang/String;)V", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    protected static final class ArtistFilter extends Filter.Text {
        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        public ArtistFilter(String title) {
            super(title, (String) null, 2, (DefaultConstructorMarker) null);
            Intrinsics.checkNotNullParameter(title, "title");
        }
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\u0012\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0004\u0018\u00002\u00020\u0001B\r\u0012\u0006\u0010\u0002\u001a\u00020\u0003¢\u0006\u0002\u0010\u0004¨\u0006\u0005"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$YearFilter;", "Leu/kanade/tachiyomi/source/model/Filter$Text;", "title", "", "(Ljava/lang/String;)V", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    protected static final class YearFilter extends Filter.Text {
        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        public YearFilter(String title) {
            super(title, (String) null, 2, (DefaultConstructorMarker) null);
            Intrinsics.checkNotNullParameter(title, "title");
        }
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\u001c\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010 \n\u0002\b\u0002\b\u0004\u0018\u00002\b\u0012\u0004\u0012\u00020\u00020\u0001B\u001b\u0012\u0006\u0010\u0003\u001a\u00020\u0004\u0012\f\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00020\u0006¢\u0006\u0002\u0010\u0007¨\u0006\b"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$StatusFilter;", "Leu/kanade/tachiyomi/source/model/Filter$Group;", "Leu/kanade/tachiyomi/multisrc/madara/Madara$Tag;", "title", "", "status", "", "(Ljava/lang/String;Ljava/util/List;)V", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    protected static final class StatusFilter extends Filter.Group<Tag> {
        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        public StatusFilter(String title, List<? extends Tag> list) {
            super(title, list);
            Intrinsics.checkNotNullParameter(title, "title");
            Intrinsics.checkNotNullParameter(list, "status");
        }
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\b\n\u0002\b\u0002\b\u0004\u0018\u00002\u00020\u0001B1\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0018\u0010\u0004\u001a\u0014\u0012\u0010\u0012\u000e\u0012\u0004\u0012\u00020\u0003\u0012\u0004\u0012\u00020\u00030\u00060\u0005\u0012\b\b\u0002\u0010\u0007\u001a\u00020\b¢\u0006\u0002\u0010\t¨\u0006\n"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$OrderByFilter;", "Leu/kanade/tachiyomi/multisrc/madara/Madara$UriPartFilter;", "title", "", "options", "", "Lkotlin/Pair;", "state", "", "(Ljava/lang/String;Ljava/util/List;I)V", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    protected static final class OrderByFilter extends UriPartFilter {
        public /* synthetic */ OrderByFilter(String str, List list, int i, int i2, DefaultConstructorMarker defaultConstructorMarker) {
            this(str, list, (i2 & 4) != 0 ? 0 : i);
        }

        /* JADX WARN: Illegal instructions before constructor call */
        public OrderByFilter(String title, List<Pair<String, String>> list, int state) {
            Intrinsics.checkNotNullParameter(title, "title");
            Intrinsics.checkNotNullParameter(list, "options");
            List<Pair<String, String>> $this$toTypedArray$iv = list;
            super(title, (Pair[]) $this$toTypedArray$iv.toArray(new Pair[0]), state);
        }
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\u001c\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\b\u0002\b\u0004\u0018\u00002\u00020\u0001B'\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0018\u0010\u0004\u001a\u0014\u0012\u0010\u0012\u000e\u0012\u0004\u0012\u00020\u0003\u0012\u0004\u0012\u00020\u00030\u00060\u0005¢\u0006\u0002\u0010\u0007¨\u0006\b"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$GenreConditionFilter;", "Leu/kanade/tachiyomi/multisrc/madara/Madara$UriPartFilter;", "title", "", "options", "", "Lkotlin/Pair;", "(Ljava/lang/String;Ljava/util/List;)V", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    protected static final class GenreConditionFilter extends UriPartFilter {
        /* JADX WARN: Illegal instructions before constructor call */
        public GenreConditionFilter(String title, List<Pair<String, String>> list) {
            Intrinsics.checkNotNullParameter(title, "title");
            Intrinsics.checkNotNullParameter(list, "options");
            List<Pair<String, String>> $this$toTypedArray$iv = list;
            super(title, (Pair[]) $this$toTypedArray$iv.toArray(new Pair[0]), 0, 4, null);
        }
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\u001c\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\b\u0002\b\u0004\u0018\u00002\u00020\u0001B'\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0018\u0010\u0004\u001a\u0014\u0012\u0010\u0012\u000e\u0012\u0004\u0012\u00020\u0003\u0012\u0004\u0012\u00020\u00030\u00060\u0005¢\u0006\u0002\u0010\u0007¨\u0006\b"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$AdultContentFilter;", "Leu/kanade/tachiyomi/multisrc/madara/Madara$UriPartFilter;", "title", "", "options", "", "Lkotlin/Pair;", "(Ljava/lang/String;Ljava/util/List;)V", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    protected static final class AdultContentFilter extends UriPartFilter {
        /* JADX WARN: Illegal instructions before constructor call */
        public AdultContentFilter(String title, List<Pair<String, String>> list) {
            Intrinsics.checkNotNullParameter(title, "title");
            Intrinsics.checkNotNullParameter(list, "options");
            List<Pair<String, String>> $this$toTypedArray$iv = list;
            super(title, (Pair[]) $this$toTypedArray$iv.toArray(new Pair[0]), 0, 4, null);
        }
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\b\u0002\b\u0004\u0018\u00002\b\u0012\u0004\u0012\u00020\u00020\u0001B\u001b\u0012\u0006\u0010\u0003\u001a\u00020\u0004\u0012\f\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00070\u0006¢\u0006\u0002\u0010\b¨\u0006\t"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$GenreList;", "Leu/kanade/tachiyomi/source/model/Filter$Group;", "Leu/kanade/tachiyomi/multisrc/madara/Madara$GenreCheckBox;", "title", "", "genres", "", "Leu/kanade/tachiyomi/multisrc/madara/Madara$Genre;", "(Ljava/lang/String;Ljava/util/List;)V", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    protected static final class GenreList extends Filter.Group<GenreCheckBox> {
        public GenreList(String title, List<Genre> list) {
            Intrinsics.checkNotNullParameter(title, "title");
            Intrinsics.checkNotNullParameter(list, "genres");
            List<Genre> $this$map$iv = list;
            Collection destination$iv$iv = new ArrayList(CollectionsKt.collectionSizeOrDefault($this$map$iv, 10));
            for (Object item$iv$iv : $this$map$iv) {
                Genre it = (Genre) item$iv$iv;
                destination$iv$iv.add(new GenreCheckBox(it.getName(), it.getId()));
            }
            super(title, (List) destination$iv$iv);
        }
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\u0012\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0005\u0018\u00002\u00020\u0001B\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0003¢\u0006\u0002\u0010\u0005R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0006\u0010\u0007¨\u0006\b"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$GenreCheckBox;", "Leu/kanade/tachiyomi/source/model/Filter$CheckBox;", "name", "", "id", "(Ljava/lang/String;Ljava/lang/String;)V", "getId", "()Ljava/lang/String;", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class GenreCheckBox extends Filter.CheckBox {
        private final String id;

        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        public GenreCheckBox(String name, String id) {
            super(name, false, 2, (DefaultConstructorMarker) null);
            Intrinsics.checkNotNullParameter(name, "name");
            Intrinsics.checkNotNullParameter(id, "id");
            this.id = id;
        }

        public /* synthetic */ GenreCheckBox(String str, String str2, int i, DefaultConstructorMarker defaultConstructorMarker) {
            this(str, (i & 2) != 0 ? str : str2);
        }

        public final String getId() {
            return this.id;
        }
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\u0012\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0006\u0018\u00002\u00020\u0001B\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0003¢\u0006\u0002\u0010\u0005R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0006\u0010\u0007R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\b\u0010\u0007¨\u0006\t"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$Genre;", "", "name", "", "id", "(Ljava/lang/String;Ljava/lang/String;)V", "getId", "()Ljava/lang/String;", "getName", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Genre {
        private final String id;
        private final String name;

        public Genre(String name, String id) {
            Intrinsics.checkNotNullParameter(name, "name");
            Intrinsics.checkNotNullParameter(id, "id");
            this.name = name;
            this.id = id;
        }

        public /* synthetic */ Genre(String str, String str2, int i, DefaultConstructorMarker defaultConstructorMarker) {
            this(str, (i & 2) != 0 ? str : str2);
        }

        public final String getId() {
            return this.id;
        }

        public final String getName() {
            return this.name;
        }
    }

    public FilterList getFilterList() {
        launchIO(new Function0<Unit>() { // from class: eu.kanade.tachiyomi.multisrc.madara.Madara.getFilterList.1
            {
                super(0);
            }

            public /* bridge */ /* synthetic */ Object invoke() {
                m5invoke();
                return Unit.INSTANCE;
            }

            /* renamed from: invoke, reason: collision with other method in class */
            public final void m5invoke() {
                Madara.this.fetchGenres();
            }
        });
        Filter[] filterArr = new Filter[6];
        filterArr[0] = (Filter) new AuthorFilter(this.intl.get("author_filter_title"));
        filterArr[1] = (Filter) new ArtistFilter(this.intl.get("artist_filter_title"));
        filterArr[2] = (Filter) new YearFilter(this.intl.get("year_filter_title"));
        String str = this.intl.get("status_filter_title");
        Map $this$map$iv = getStatusFilterOptions();
        Collection destination$iv$iv = new ArrayList($this$map$iv.size());
        for (Map.Entry item$iv$iv : $this$map$iv.entrySet()) {
            destination$iv$iv.add(new Tag(item$iv$iv.getKey(), item$iv$iv.getValue()));
        }
        filterArr[3] = (Filter) new StatusFilter(str, (List) destination$iv$iv);
        filterArr[4] = (Filter) new OrderByFilter(this.intl.get("order_by_filter_title"), MapsKt.toList(getOrderByFilterOptions()), 0);
        filterArr[5] = (Filter) new AdultContentFilter(this.intl.get("adult_content_filter_title"), MapsKt.toList(getAdultContentFilterOptions()));
        List filters = CollectionsKt.mutableListOf(filterArr);
        if (!getGenresList().isEmpty()) {
            CollectionsKt.addAll(filters, CollectionsKt.listOf(new Filter[]{(Filter) new Filter.Separator((String) null, 1, (DefaultConstructorMarker) null), (Filter) new Filter.Header(this.intl.get("genre_filter_header")), (Filter) new GenreConditionFilter(this.intl.get("genre_condition_filter_title"), MapsKt.toList(getGenreConditionFilterOptions())), (Filter) new GenreList(this.intl.get("genre_filter_title"), getGenresList())}));
        } else if (getFetchGenres()) {
            CollectionsKt.addAll(filters, CollectionsKt.listOf(new Filter[]{(Filter) new Filter.Separator((String) null, 1, (DefaultConstructorMarker) null), (Filter) new Filter.Header(this.intl.get("genre_missing_warning"))}));
        }
        return new FilterList(filters);
    }

    protected MangasPage searchMangaParse(Response response) throws NoWhenBranchMatchedException {
        Intrinsics.checkNotNullParameter(response, "response");
        Element elementSelectFirst = null;
        Document document = JsoupExtensionsKt.asJsoup$default(response, (String) null, 1, (Object) null);
        Iterable iterableSelect = document.select(searchMangaSelector());
        Intrinsics.checkNotNullExpressionValue(iterableSelect, "document.select(searchMangaSelector())");
        Iterable $this$map$iv = iterableSelect;
        Collection destination$iv$iv = new ArrayList(CollectionsKt.collectionSizeOrDefault($this$map$iv, 10));
        for (Object item$iv$iv : $this$map$iv) {
            Element p0 = (Element) item$iv$iv;
            destination$iv$iv.add(searchMangaFromElement(p0));
        }
        List entries = (List) destination$iv$iv;
        String it = searchMangaNextPageSelector();
        if (it != null) {
            elementSelectFirst = document.selectFirst(it);
        }
        boolean hasNextPage = elementSelectFirst != null;
        detectLoadMore(document);
        return new MangasPage(entries, hasNextPage);
    }

    protected String searchMangaSelector() {
        return "div.c-tabs-item__content , .manga__item";
    }

    protected String getSearchMangaUrlSelector() {
        return this.searchMangaUrlSelector;
    }

    protected SManga searchMangaFromElement(Element element) {
        Intrinsics.checkNotNullParameter(element, "element");
        SManga manga = SManga.Companion.create();
        Element it = element.selectFirst(getSearchMangaUrlSelector());
        Intrinsics.checkNotNull(it);
        String strAttr = it.attr("abs:href");
        Intrinsics.checkNotNullExpressionValue(strAttr, "it.attr(\"abs:href\")");
        setUrlWithoutDomain(manga, strAttr);
        String strOwnText = it.ownText();
        Intrinsics.checkNotNullExpressionValue(strOwnText, "it.ownText()");
        manga.setTitle(strOwnText);
        Element it2 = element.selectFirst("img");
        if (it2 != null) {
            Intrinsics.checkNotNullExpressionValue(it2, "it");
            manga.setThumbnail_url(imageFromElement(it2));
        }
        return manga;
    }

    protected String searchMangaNextPageSelector() {
        return popularMangaNextPageSelector();
    }

    protected final String[] getCompletedStatusList() {
        return this.completedStatusList;
    }

    protected final String[] getOngoingStatusList() {
        return this.ongoingStatusList;
    }

    protected final String[] getHiatusStatusList() {
        return this.hiatusStatusList;
    }

    protected final String[] getCanceledStatusList() {
        return this.canceledStatusList;
    }

    protected SManga mangaDetailsParse(Document document) throws IOException {
        String it;
        String it2;
        Document $this$mangaDetailsParse_u24lambda_u2443;
        Intrinsics.checkNotNullParameter(document, "document");
        SManga manga = SManga.Companion.create();
        Document $this$mangaDetailsParse_u24lambda_u24432 = document;
        Element elementSelectFirst = $this$mangaDetailsParse_u24lambda_u24432.selectFirst(getMangaDetailsSelectorTitle());
        Intrinsics.checkNotNull(elementSelectFirst);
        String strOwnText = elementSelectFirst.ownText();
        Intrinsics.checkNotNullExpressionValue(strOwnText, "selectFirst(mangaDetailsSelectorTitle)!!.ownText()");
        manga.setTitle(strOwnText);
        Iterable iterableEachText = $this$mangaDetailsParse_u24lambda_u24432.select(getMangaDetailsSelectorAuthor()).eachText();
        Intrinsics.checkNotNullExpressionValue(iterableEachText, "select(mangaDetailsSelectorAuthor).eachText()");
        Iterable $this$filter$iv = iterableEachText;
        Collection destination$iv$iv = new ArrayList();
        for (Object element$iv$iv : $this$filter$iv) {
            String it3 = (String) element$iv$iv;
            Intrinsics.checkNotNullExpressionValue(it3, "it");
            if (notUpdating(it3)) {
                destination$iv$iv.add(element$iv$iv);
            }
        }
        String it4 = CollectionsKt.joinToString$default((List) destination$iv$iv, (CharSequence) null, (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, (Function1) null, 63, (Object) null);
        if (StringsKt.isBlank(it4)) {
            it4 = null;
        }
        if (it4 != null) {
            manga.setAuthor(it4);
        }
        Iterable iterableEachText2 = $this$mangaDetailsParse_u24lambda_u24432.select(getMangaDetailsSelectorArtist()).eachText();
        Intrinsics.checkNotNullExpressionValue(iterableEachText2, "select(mangaDetailsSelectorArtist).eachText()");
        Iterable $this$filter$iv2 = iterableEachText2;
        Collection destination$iv$iv2 = new ArrayList();
        for (Object element$iv$iv2 : $this$filter$iv2) {
            String it5 = (String) element$iv$iv2;
            Intrinsics.checkNotNullExpressionValue(it5, "it");
            if (notUpdating(it5)) {
                destination$iv$iv2.add(element$iv$iv2);
            }
        }
        String it6 = CollectionsKt.joinToString$default((List) destination$iv$iv2, (CharSequence) null, (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, (Function1) null, 63, (Object) null);
        String it7 = StringsKt.isBlank(it6) ? null : it6;
        if (it7 != null) {
            manga.setArtist(it7);
        }
        Elements it8 = $this$mangaDetailsParse_u24lambda_u24432.select(getMangaDetailsSelectorDescription());
        String strText = it8.select("p").text();
        Intrinsics.checkNotNullExpressionValue(strText, "it.select(\"p\").text()");
        if (strText.length() > 0) {
            Iterable iterableSelect = it8.select("p");
            Intrinsics.checkNotNullExpressionValue(iterableSelect, "it.select(\"p\")");
            manga.setDescription(CollectionsKt.joinToString$default(iterableSelect, "\n\n", (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, new Function1<Element, CharSequence>() { // from class: eu.kanade.tachiyomi.multisrc.madara.Madara$mangaDetailsParse$1$7$1
                public final CharSequence invoke(Element p) {
                    String strText2 = p.text();
                    Intrinsics.checkNotNullExpressionValue(strText2, "p.text()");
                    return StringsKt.replace$default(strText2, "<br>", "\n", false, 4, (Object) null);
                }
            }, 30, (Object) null));
        } else {
            manga.setDescription(it8.text());
        }
        Element it9 = $this$mangaDetailsParse_u24lambda_u24432.selectFirst(getMangaDetailsSelectorThumbnail());
        if (it9 != null) {
            Intrinsics.checkNotNullExpressionValue(it9, "it");
            manga.setThumbnail_url(imageFromElement(it9));
        }
        Element it10 = $this$mangaDetailsParse_u24lambda_u24432.select(getMangaDetailsSelectorStatus()).last();
        if (it10 != null) {
            CharSequence $this$filter$iv3 = it10.text();
            Intrinsics.checkNotNullExpressionValue($this$filter$iv3, "it.text()");
            CharSequence $this$filterTo$iv$iv = $this$filter$iv3;
            Appendable destination$iv$iv3 = new StringBuilder();
            int length = $this$filterTo$iv$iv.length();
            for (int index$iv$iv = 0; index$iv$iv < length; index$iv$iv++) {
                char element$iv$iv3 = $this$filterTo$iv$iv.charAt(index$iv$iv);
                char ch = (Character.isLetterOrDigit(element$iv$iv3) || CharsKt.isWhitespace(element$iv$iv3)) ? (char) 1 : (char) 0;
                if (ch != 0) {
                    destination$iv$iv3.append(element$iv$iv3);
                }
            }
            String string = ((StringBuilder) destination$iv$iv3).toString();
            Intrinsics.checkNotNullExpressionValue(string, "filterTo(StringBuilder(), predicate).toString()");
            String $this$mangaDetailsParse_u24lambda_u2443_u24lambda_u2437_u24lambda_u2436 = StringsKt.trim(string).toString();
            manga.setStatus(Integer.valueOf(containsIn($this$mangaDetailsParse_u24lambda_u2443_u24lambda_u2437_u24lambda_u2436, this.completedStatusList) ? 2 : containsIn($this$mangaDetailsParse_u24lambda_u2443_u24lambda_u2437_u24lambda_u2436, this.ongoingStatusList) ? 1 : containsIn($this$mangaDetailsParse_u24lambda_u2443_u24lambda_u2437_u24lambda_u2436, this.hiatusStatusList) ? 6 : containsIn($this$mangaDetailsParse_u24lambda_u2443_u24lambda_u2437_u24lambda_u2436, this.canceledStatusList) ? 5 : 0).intValue());
        }
        Iterable iterableSelect2 = $this$mangaDetailsParse_u24lambda_u24432.select(getMangaDetailsSelectorGenre());
        Intrinsics.checkNotNullExpressionValue(iterableSelect2, "select(mangaDetailsSelectorGenre)");
        Iterable $this$mapTo$iv = iterableSelect2;
        Collection destination$iv = new ArrayList();
        for (Object item$iv : $this$mapTo$iv) {
            destination$iv.add(((Element) item$iv).text());
        }
        ArrayList genres = (ArrayList) destination$iv;
        if (getMangaDetailsSelectorTag().length() > 0) {
            Iterable iterableSelect3 = $this$mangaDetailsParse_u24lambda_u24432.select(getMangaDetailsSelectorTag());
            Intrinsics.checkNotNullExpressionValue(iterableSelect3, "select(mangaDetailsSelectorTag)");
            Iterable $this$forEach$iv = iterableSelect3;
            for (Object element$iv : $this$forEach$iv) {
                Element element = (Element) element$iv;
                if (element.text().length() <= 25) {
                    String strText2 = element.text();
                    Intrinsics.checkNotNullExpressionValue(strText2, "element.text()");
                    $this$mangaDetailsParse_u24lambda_u2443 = $this$mangaDetailsParse_u24lambda_u24432;
                    if (!StringsKt.contains(strText2, "read", true)) {
                        String strText3 = element.text();
                        Intrinsics.checkNotNullExpressionValue(strText3, "element.text()");
                        if (!StringsKt.contains(strText3, getName(), true)) {
                            String strText4 = element.text();
                            Intrinsics.checkNotNullExpressionValue(strText4, "element.text()");
                            if (!StringsKt.contains(strText4, StringsKt.replace$default(getName(), " ", "", false, 4, (Object) null), true)) {
                                String strText5 = element.text();
                                Intrinsics.checkNotNullExpressionValue(strText5, "element.text()");
                                if (!StringsKt.contains(strText5, manga.getTitle(), true)) {
                                    String strText6 = element.text();
                                    Intrinsics.checkNotNullExpressionValue(strText6, "element.text()");
                                    if (!StringsKt.contains(strText6, getAltName(), true)) {
                                        genres.add(element.text());
                                    }
                                }
                            }
                        }
                    }
                } else {
                    $this$mangaDetailsParse_u24lambda_u2443 = $this$mangaDetailsParse_u24lambda_u24432;
                }
                $this$mangaDetailsParse_u24lambda_u24432 = $this$mangaDetailsParse_u24lambda_u2443;
            }
        }
        Element elementSelectFirst2 = document.selectFirst(getSeriesTypeSelector());
        if (elementSelectFirst2 != null && (it2 = elementSelectFirst2.ownText()) != null) {
            Intrinsics.checkNotNullExpressionValue(it2, "ownText()");
            if (!(it2.length() == 0) && notUpdating(it2) && !Intrinsics.areEqual(it2, "-")) {
                genres.add(it2);
            }
        }
        ArrayList $this$distinctBy$iv = genres;
        HashSet set$iv = new HashSet();
        ArrayList list$iv = new ArrayList();
        for (Object e$iv : $this$distinctBy$iv) {
            String p0 = (String) e$iv;
            String lowerCase = p0.toLowerCase(Locale.ROOT);
            Iterable $this$distinctBy$iv2 = $this$distinctBy$iv;
            Intrinsics.checkNotNullExpressionValue(lowerCase, "this as java.lang.String).toLowerCase(Locale.ROOT)");
            if (set$iv.add(lowerCase)) {
                list$iv.add(e$iv);
                $this$distinctBy$iv = $this$distinctBy$iv2;
            } else {
                $this$distinctBy$iv = $this$distinctBy$iv2;
            }
        }
        manga.setGenre(CollectionsKt.joinToString$default(list$iv, (CharSequence) null, (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, (Function1) null, 63, (Object) null));
        Element elementSelectFirst3 = document.selectFirst(getAltNameSelector());
        if (elementSelectFirst3 != null && (it = elementSelectFirst3.ownText()) != null) {
            Intrinsics.checkNotNullExpressionValue(it, "ownText()");
            if (!StringsKt.isBlank(it) && notUpdating(it)) {
                String description = manga.getDescription();
                manga.setDescription(description == null || StringsKt.isBlank(description) ? getAltName() + ' ' + it : manga.getDescription() + "\n\n" + getAltName() + ' ' + it);
            }
        }
        return manga;
    }

    public String getMangaDetailsSelectorTitle() {
        return this.mangaDetailsSelectorTitle;
    }

    public String getMangaDetailsSelectorAuthor() {
        return this.mangaDetailsSelectorAuthor;
    }

    public String getMangaDetailsSelectorArtist() {
        return this.mangaDetailsSelectorArtist;
    }

    public String getMangaDetailsSelectorStatus() {
        return this.mangaDetailsSelectorStatus;
    }

    public String getMangaDetailsSelectorDescription() {
        return this.mangaDetailsSelectorDescription;
    }

    public String getMangaDetailsSelectorThumbnail() {
        return this.mangaDetailsSelectorThumbnail;
    }

    public String getMangaDetailsSelectorGenre() {
        return this.mangaDetailsSelectorGenre;
    }

    public String getMangaDetailsSelectorTag() {
        return this.mangaDetailsSelectorTag;
    }

    public String getSeriesTypeSelector() {
        return this.seriesTypeSelector;
    }

    public String getAltNameSelector() {
        return this.altNameSelector;
    }

    public String getAltName() {
        return this.altName;
    }

    public Regex getUpdatingRegex() {
        return this.updatingRegex;
    }

    public final boolean notUpdating(String $this$notUpdating) {
        Intrinsics.checkNotNullParameter($this$notUpdating, "<this>");
        return !getUpdatingRegex().containsMatchIn($this$notUpdating);
    }

    private final boolean containsIn(String $this$containsIn, String[] array) {
        Collection destination$iv$iv = new ArrayList(array.length);
        for (String str : array) {
            String lowerCase = str.toLowerCase(Locale.ROOT);
            Intrinsics.checkNotNullExpressionValue(lowerCase, "this as java.lang.String).toLowerCase(Locale.ROOT)");
            destination$iv$iv.add(lowerCase);
        }
        String lowerCase2 = $this$containsIn.toLowerCase(Locale.ROOT);
        Intrinsics.checkNotNullExpressionValue(lowerCase2, "this as java.lang.String).toLowerCase(Locale.ROOT)");
        return ((List) destination$iv$iv).contains(lowerCase2);
    }

    protected String imageFromElement(Element element) {
        Intrinsics.checkNotNullParameter(element, "element");
        if (element.hasAttr("data-src")) {
            return element.attr("abs:data-src");
        }
        if (element.hasAttr("data-lazy-src")) {
            return element.attr("abs:data-lazy-src");
        }
        if (!element.hasAttr("srcset")) {
            return element.hasAttr("data-cfsrc") ? element.attr("abs:data-cfsrc") : element.attr("abs:src");
        }
        String strAttr = element.attr("abs:srcset");
        Intrinsics.checkNotNullExpressionValue(strAttr, "element.attr(\"abs:srcset\")");
        return getSrcSetImage(strAttr);
    }

    protected String getSrcSetImage(String $this$getSrcSetImage) {
        String str;
        Intrinsics.checkNotNullParameter($this$getSrcSetImage, "<this>");
        Iterable $this$filter$iv = StringsKt.split$default($this$getSrcSetImage, new String[]{" "}, false, 0, 6, (Object) null);
        Regex regex = URL_REGEX;
        Collection destination$iv$iv = new ArrayList();
        for (Object element$iv$iv : $this$filter$iv) {
            CharSequence p0 = (CharSequence) element$iv$iv;
            if (regex.matches(p0)) {
                destination$iv$iv.add(element$iv$iv);
            }
        }
        Iterator it = ((List) destination$iv$iv).iterator();
        if (it.hasNext()) {
            String p02 = (String) it.next();
            String p03 = p02.toString();
            while (it.hasNext()) {
                String p04 = (String) it.next();
                String p05 = p04.toString();
                if (p03.compareTo(p05) < 0) {
                    p03 = p05;
                }
            }
            str = p03;
        } else {
            str = null;
        }
        return str;
    }

    protected boolean getUseNewChapterEndpoint() {
        return this.useNewChapterEndpoint;
    }

    protected Request oldXhrChaptersRequest(String mangaId) {
        Intrinsics.checkNotNullParameter(mangaId, "mangaId");
        return RequestsKt.POST$default(getBaseUrl() + "/wp-admin/admin-ajax.php", getXhrHeaders(), new FormBody.Builder((Charset) null, 1, (DefaultConstructorMarker) null).add("action", "manga_get_chapters").add("manga", mangaId).build(), (CacheControl) null, 8, (Object) null);
    }

    protected Request xhrChaptersRequest(String mangaUrl) {
        Intrinsics.checkNotNullParameter(mangaUrl, "mangaUrl");
        return RequestsKt.POST$default(mangaUrl + "/ajax/chapters", getXhrHeaders(), (RequestBody) null, (CacheControl) null, 12, (Object) null);
    }

    protected List<SChapter> chapterListParse(Response response) {
        Request xhrRequest;
        Intrinsics.checkNotNullParameter(response, "response");
        final Document document = JsoupExtensionsKt.asJsoup$default(response, (String) null, 1, (Object) null);
        launchIO(new Function0<Unit>() { // from class: eu.kanade.tachiyomi.multisrc.madara.Madara.chapterListParse.1
            /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
            {
                super(0);
            }

            public /* bridge */ /* synthetic */ Object invoke() {
                m4invoke();
                return Unit.INSTANCE;
            }

            /* renamed from: invoke, reason: collision with other method in class */
            public final void m4invoke() {
                Madara.this.countViews(document);
            }
        });
        Collection collectionSelect = document.select("div[id^=manga-chapters-holder]");
        Elements chapterElements = document.select(chapterListSelector());
        if (chapterElements.isEmpty()) {
            Collection collection = collectionSelect;
            if (!(collection == null || collection.isEmpty())) {
                String strLocation = document.location();
                Intrinsics.checkNotNullExpressionValue(strLocation, "document.location()");
                String mangaUrl = StringsKt.removeSuffix(strLocation, "/");
                String mangaId = collectionSelect.attr("data-id");
                if (getUseNewChapterEndpoint() || this.oldChapterEndpointDisabled) {
                    xhrRequest = xhrChaptersRequest(mangaUrl);
                } else {
                    Intrinsics.checkNotNullExpressionValue(mangaId, "mangaId");
                    xhrRequest = oldXhrChaptersRequest(mangaId);
                }
                Response xhrResponse = getClient().newCall(xhrRequest).execute();
                if (!getUseNewChapterEndpoint() && xhrResponse.code() == 400) {
                    xhrResponse.close();
                    this.oldChapterEndpointDisabled = true;
                    Request xhrRequest2 = xhrChaptersRequest(mangaUrl);
                    xhrResponse = getClient().newCall(xhrRequest2).execute();
                }
                chapterElements = JsoupExtensionsKt.asJsoup$default(xhrResponse, (String) null, 1, (Object) null).select(chapterListSelector());
                xhrResponse.close();
            }
        }
        Intrinsics.checkNotNullExpressionValue(chapterElements, "chapterElements");
        Iterable $this$map$iv = (Iterable) chapterElements;
        Collection destination$iv$iv = new ArrayList(CollectionsKt.collectionSizeOrDefault($this$map$iv, 10));
        for (Object item$iv$iv : $this$map$iv) {
            Element p0 = (Element) item$iv$iv;
            destination$iv$iv.add(chapterFromElement(p0));
        }
        return (List) destination$iv$iv;
    }

    protected String chapterListSelector() {
        return "li.wp-manga-chapter";
    }

    protected String chapterDateSelector() {
        return "span.chapter-release-date";
    }

    public String getChapterUrlSelector() {
        return this.chapterUrlSelector;
    }

    public String getChapterUrlSuffix() {
        return this.chapterUrlSuffix;
    }

    protected SChapter chapterFromElement(Element element) {
        long chapterDate;
        String it;
        String it2;
        Intrinsics.checkNotNullParameter(element, "element");
        SChapter chapter = SChapter.Companion.create();
        Element urlElement = element.selectFirst(getChapterUrlSelector());
        Intrinsics.checkNotNull(urlElement);
        String it3 = urlElement.attr("abs:href");
        StringBuilder sb = new StringBuilder();
        Intrinsics.checkNotNullExpressionValue(it3, "it");
        chapter.setUrl(sb.append(StringsKt.substringBefore$default(it3, "?style=paged", (String) null, 2, (Object) null)).append(!StringsKt.endsWith$default(it3, getChapterUrlSuffix(), false, 2, (Object) null) ? getChapterUrlSuffix() : "").toString());
        String strText = urlElement.text();
        Intrinsics.checkNotNullExpressionValue(strText, "urlElement.text()");
        chapter.setName(strText);
        Element elementSelectFirst = element.selectFirst("img:not(.thumb)");
        if (elementSelectFirst == null || (it2 = elementSelectFirst.attr("alt")) == null) {
            Element elementSelectFirst2 = element.selectFirst("span a");
            if (elementSelectFirst2 == null || (it = elementSelectFirst2.attr("title")) == null) {
                Element elementSelectFirst3 = element.selectFirst(chapterDateSelector());
                chapterDate = parseChapterDate(elementSelectFirst3 != null ? elementSelectFirst3.text() : null);
            } else {
                Intrinsics.checkNotNullExpressionValue(it, "attr(\"title\")");
                chapterDate = Long.valueOf(parseRelativeDate(it)).longValue();
            }
        } else {
            Intrinsics.checkNotNullExpressionValue(it2, "attr(\"alt\")");
            chapterDate = Long.valueOf(parseRelativeDate(it2)).longValue();
        }
        chapter.setDate_upload(chapterDate);
        return chapter;
    }

    public long parseChapterDate(String date) {
        String strReplace;
        if (date == null) {
            return 0L;
        }
        if (new WordSet("yesterday", "يوم واحد").startsWith(date)) {
            Calendar $this$parseChapterDate_u24lambda_u2453 = Calendar.getInstance();
            $this$parseChapterDate_u24lambda_u2453.add(5, -1);
            $this$parseChapterDate_u24lambda_u2453.set(11, 0);
            $this$parseChapterDate_u24lambda_u2453.set(12, 0);
            $this$parseChapterDate_u24lambda_u2453.set(13, 0);
            $this$parseChapterDate_u24lambda_u2453.set(14, 0);
            return $this$parseChapterDate_u24lambda_u2453.getTimeInMillis();
        }
        if (new WordSet("today").startsWith(date)) {
            Calendar $this$parseChapterDate_u24lambda_u2454 = Calendar.getInstance();
            $this$parseChapterDate_u24lambda_u2454.set(11, 0);
            $this$parseChapterDate_u24lambda_u2454.set(12, 0);
            $this$parseChapterDate_u24lambda_u2454.set(13, 0);
            $this$parseChapterDate_u24lambda_u2454.set(14, 0);
            return $this$parseChapterDate_u24lambda_u2454.getTimeInMillis();
        }
        if (new WordSet("يومين").startsWith(date)) {
            Calendar $this$parseChapterDate_u24lambda_u2455 = Calendar.getInstance();
            $this$parseChapterDate_u24lambda_u2455.add(5, -2);
            $this$parseChapterDate_u24lambda_u2455.set(11, 0);
            $this$parseChapterDate_u24lambda_u2455.set(12, 0);
            $this$parseChapterDate_u24lambda_u2455.set(13, 0);
            $this$parseChapterDate_u24lambda_u2455.set(14, 0);
            return $this$parseChapterDate_u24lambda_u2455.getTimeInMillis();
        }
        if (new WordSet("ago", "atrás", "önce", "قبل").endsWith(date)) {
            return parseRelativeDate(date);
        }
        if (new WordSet("hace", "giờ", "phút", "giây").startsWith(date)) {
            return parseRelativeDate(date);
        }
        if (new Regex("\\b\\d+ jour").containsMatchIn(date)) {
            return parseRelativeDate(date);
        }
        if (new Regex("\\d(st|nd|rd|th)").containsMatchIn(date)) {
            Iterable $this$map$iv = StringsKt.split$default(date, new String[]{" "}, false, 0, 6, (Object) null);
            Collection destination$iv$iv = new ArrayList(CollectionsKt.collectionSizeOrDefault($this$map$iv, 10));
            for (Object item$iv$iv : $this$map$iv) {
                String it = (String) item$iv$iv;
                if (new Regex("\\d\\D\\D").containsMatchIn(it)) {
                    strReplace = new Regex("\\D").replace(it, "");
                } else {
                    strReplace = it;
                }
                destination$iv$iv.add(strReplace);
            }
            return parseChapterDate$tryParse(this.dateFormat, CollectionsKt.joinToString$default((List) destination$iv$iv, " ", (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, (Function1) null, 62, (Object) null));
        }
        return parseChapterDate$tryParse(this.dateFormat, date);
    }

    private static final long parseChapterDate$tryParse(SimpleDateFormat $this$parseChapterDate_u24tryParse, String string) {
        try {
            Date date = $this$parseChapterDate_u24tryParse.parse(string);
            if (date != null) {
                return date.getTime();
            }
            return 0L;
        } catch (ParseException e) {
            return 0L;
        }
    }

    protected long parseRelativeDate(String date) {
        String value;
        Integer intOrNull;
        Intrinsics.checkNotNullParameter(date, "date");
        MatchResult matchResultFind$default = Regex.find$default(new Regex("(\\d+)"), date, 0, 2, (Object) null);
        if (matchResultFind$default == null || (value = matchResultFind$default.getValue()) == null || (intOrNull = StringsKt.toIntOrNull(value)) == null) {
            return 0L;
        }
        int number = intOrNull.intValue();
        Calendar cal = Calendar.getInstance();
        if (new WordSet("hari", "gün", "jour", "día", "dia", "day", "วัน", "ngày", "giorni", "أيام", "天").anyWordIn(date)) {
            cal.add(5, -number);
            return cal.getTimeInMillis();
        }
        if (new WordSet("jam", "saat", "heure", "hora", "hour", "ชั่วโมง", "giờ", "ore", "ساعة", "小时").anyWordIn(date)) {
            cal.add(10, -number);
            return cal.getTimeInMillis();
        }
        if (new WordSet("menit", "dakika", "min", "minute", "minuto", "นาที", "دقائق", "phút").anyWordIn(date)) {
            cal.add(12, -number);
            return cal.getTimeInMillis();
        }
        if (new WordSet("detik", "segundo", "second", "วินาที", "giây").anyWordIn(date)) {
            cal.add(13, -number);
            return cal.getTimeInMillis();
        }
        if (new WordSet("week", "semana", "tuần").anyWordIn(date)) {
            cal.add(5, (-number) * 7);
            return cal.getTimeInMillis();
        }
        if (new WordSet("month", "mes", "tháng").anyWordIn(date)) {
            cal.add(2, -number);
            return cal.getTimeInMillis();
        }
        if (!new WordSet("year", "año", "năm").anyWordIn(date)) {
            return 0L;
        }
        cal.add(1, -number);
        return cal.getTimeInMillis();
    }

    protected Request pageListRequest(SChapter chapter) {
        Intrinsics.checkNotNullParameter(chapter, "chapter");
        if (StringsKt.startsWith$default(chapter.getUrl(), "http", false, 2, (Object) null)) {
            return RequestsKt.GET$default(chapter.getUrl(), getHeaders(), (CacheControl) null, 4, (Object) null);
        }
        return super.pageListRequest(chapter);
    }

    public String getPageListParseSelector() {
        return this.pageListParseSelector;
    }

    public String getChapterProtectorSelector() {
        return this.chapterProtectorSelector;
    }

    public String getChapterProtectorPasswordPrefix() {
        return this.chapterProtectorPasswordPrefix;
    }

    public String getChapterProtectorDataPrefix() {
        return this.chapterProtectorDataPrefix;
    }

    protected List<Page> pageListParse(final Document document) {
        String chapterProtectorHtml;
        String it;
        String imageUrl;
        Intrinsics.checkNotNullParameter(document, "document");
        launchIO(new Function0<Unit>() { // from class: eu.kanade.tachiyomi.multisrc.madara.Madara.pageListParse.1
            /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
            {
                super(0);
            }

            public /* bridge */ /* synthetic */ Object invoke() {
                m7invoke();
                return Unit.INSTANCE;
            }

            /* renamed from: invoke, reason: collision with other method in class */
            public final void m7invoke() {
                Madara.this.countViews(document);
            }
        });
        Element chapterProtector = document.selectFirst(getChapterProtectorSelector());
        if (chapterProtector == null) {
            Iterable iterableSelect = document.select(getPageListParseSelector());
            Intrinsics.checkNotNullExpressionValue(iterableSelect, "document.select(pageListParseSelector)");
            Iterable $this$mapIndexed$iv = iterableSelect;
            Collection destination$iv$iv = new ArrayList(CollectionsKt.collectionSizeOrDefault($this$mapIndexed$iv, 10));
            int index$iv$iv = 0;
            for (Object item$iv$iv : $this$mapIndexed$iv) {
                int index$iv$iv2 = index$iv$iv + 1;
                if (index$iv$iv < 0) {
                    CollectionsKt.throwIndexOverflow();
                }
                Element element = (Element) item$iv$iv;
                int index = index$iv$iv;
                Element it2 = element.selectFirst("img");
                if (it2 != null) {
                    Intrinsics.checkNotNullExpressionValue(it2, "it");
                    imageUrl = imageFromElement(it2);
                } else {
                    imageUrl = null;
                }
                String strLocation = document.location();
                Intrinsics.checkNotNullExpressionValue(strLocation, "document.location()");
                destination$iv$iv.add(new Page(index, strLocation, imageUrl, (Uri) null, 8, (DefaultConstructorMarker) null));
                index$iv$iv = index$iv$iv2;
            }
            return (List) destination$iv$iv;
        }
        String it3 = chapterProtector.attr("src");
        Intrinsics.checkNotNullExpressionValue(it3, "it");
        if (!StringsKt.startsWith$default(it3, "data:text/javascript;base64,", false, 2, (Object) null)) {
            it3 = null;
        }
        if (it3 != null && (it = StringsKt.substringAfter$default(it3, "data:text/javascript;base64,", (String) null, 2, (Object) null)) != null) {
            byte[] bArrDecode = Base64.decode(it, 0);
            Intrinsics.checkNotNullExpressionValue(bArrDecode, "decode(it, Base64.DEFAULT)");
            chapterProtectorHtml = new String(bArrDecode, Charsets.UTF_8);
        } else {
            chapterProtectorHtml = chapterProtector.html();
        }
        Intrinsics.checkNotNullExpressionValue(chapterProtectorHtml, "chapterProtectorHtml");
        String password = StringsKt.substringBefore$default(StringsKt.substringAfter$default(chapterProtectorHtml, getChapterProtectorPasswordPrefix(), (String) null, 2, (Object) null), "';", (String) null, 2, (Object) null);
        JsonObject chapterData = JsonElementKt.getJsonObject(getJson().parseToJsonElement(StringsKt.replace$default(StringsKt.substringBefore$default(StringsKt.substringAfter$default(chapterProtectorHtml, getChapterProtectorDataPrefix(), (String) null, 2, (Object) null), "';", (String) null, 2, (Object) null), "\\/", "/", false, 4, (Object) null)));
        Object obj = chapterData.get("ct");
        Intrinsics.checkNotNull(obj);
        byte[] unsaltedCiphertext = Base64.decode(JsonElementKt.getJsonPrimitive((JsonElement) obj).getContent(), 0);
        Object obj2 = chapterData.get("s");
        Intrinsics.checkNotNull(obj2);
        byte[] salt = decodeHex(JsonElementKt.getJsonPrimitive((JsonElement) obj2).getContent());
        byte[] bArrPlus = ArraysKt.plus(this.salted, salt);
        Intrinsics.checkNotNullExpressionValue(unsaltedCiphertext, "unsaltedCiphertext");
        byte[] ciphertext = ArraysKt.plus(bArrPlus, unsaltedCiphertext);
        CryptoAES cryptoAES = CryptoAES.INSTANCE;
        String strEncodeToString = Base64.encodeToString(ciphertext, 0);
        Intrinsics.checkNotNullExpressionValue(strEncodeToString, "encodeToString(ciphertext, Base64.DEFAULT)");
        String rawImgArray = cryptoAES.decrypt(strEncodeToString, password);
        String imgArrayString = JsonElementKt.getJsonPrimitive(getJson().parseToJsonElement(rawImgArray)).getContent();
        Iterable $this$mapIndexed$iv2 = JsonElementKt.getJsonArray(getJson().parseToJsonElement(imgArrayString));
        Collection destination$iv$iv2 = new ArrayList(CollectionsKt.collectionSizeOrDefault($this$mapIndexed$iv2, 10));
        int index$iv$iv3 = 0;
        for (Object item$iv$iv2 : $this$mapIndexed$iv2) {
            int index$iv$iv4 = index$iv$iv3 + 1;
            if (index$iv$iv3 < 0) {
                CollectionsKt.throwIndexOverflow();
            }
            int idx = index$iv$iv3;
            String strLocation2 = document.location();
            Intrinsics.checkNotNullExpressionValue(strLocation2, "document.location()");
            destination$iv$iv2.add(new Page(idx, strLocation2, JsonElementKt.getJsonPrimitive((JsonElement) item$iv$iv2).getContent(), (Uri) null, 8, (DefaultConstructorMarker) null));
            index$iv$iv3 = index$iv$iv4;
        }
        return (List) destination$iv$iv2;
    }

    protected Request imageRequest(Page page) {
        Intrinsics.checkNotNullParameter(page, "page");
        String imageUrl = page.getImageUrl();
        Intrinsics.checkNotNull(imageUrl);
        return RequestsKt.GET$default(imageUrl, getHeaders().newBuilder().set("Referer", page.getUrl()).build(), (CacheControl) null, 4, (Object) null);
    }

    protected String imageUrlParse(Document document) {
        Intrinsics.checkNotNullParameter(document, "document");
        return "";
    }

    protected boolean getSendViewCount() {
        return this.sendViewCount;
    }

    protected Request countViewsRequest(Document document) {
        JsonPrimitive jsonPrimitive;
        Intrinsics.checkNotNullParameter(document, "document");
        Element elementSelectFirst = document.selectFirst("script#wp-manga-js-extra");
        String wpMangaData = elementSelectFirst != null ? elementSelectFirst.data() : null;
        if (wpMangaData == null) {
            return null;
        }
        String wpMangaInfo = StringsKt.substringBeforeLast$default(StringsKt.substringAfter$default(wpMangaData, "var manga = ", (String) null, 2, (Object) null), ";", (String) null, 2, (Object) null);
        JsonObject wpManga = JsonElementKt.getJsonObject(getJson().parseToJsonElement(wpMangaInfo));
        JsonElement jsonElement = (JsonElement) wpManga.get("enable_manga_view");
        if (!Intrinsics.areEqual((jsonElement == null || (jsonPrimitive = JsonElementKt.getJsonPrimitive(jsonElement)) == null) ? null : jsonPrimitive.getContent(), "1")) {
            return null;
        }
        FormBody.Builder builderAdd = new FormBody.Builder((Charset) null, 1, (DefaultConstructorMarker) null).add("action", "manga_views");
        Object obj = wpManga.get("manga_id");
        Intrinsics.checkNotNull(obj);
        FormBody.Builder formBuilder = builderAdd.add("manga", JsonElementKt.getJsonPrimitive((JsonElement) obj).getContent());
        if (wpManga.get("chapter_slug") != null) {
            Object obj2 = wpManga.get("chapter_slug");
            Intrinsics.checkNotNull(obj2);
            formBuilder.add("chapter", JsonElementKt.getJsonPrimitive((JsonElement) obj2).getContent());
        }
        RequestBody requestBodyBuild = formBuilder.build();
        Headers.Builder builderHeadersBuilder = headersBuilder();
        String strLocation = document.location();
        Intrinsics.checkNotNullExpressionValue(strLocation, "document.location()");
        Headers newHeaders = builderHeadersBuilder.set("Referer", strLocation).build();
        return RequestsKt.POST$default(getBaseUrl() + "/wp-admin/admin-ajax.php", newHeaders, requestBodyBuild, (CacheControl) null, 8, (Object) null);
    }

    protected final void countViews(Document document) {
        Intrinsics.checkNotNullParameter(document, "document");
        if (!getSendViewCount()) {
            return;
        }
        try {
            Request request = countViewsRequest(document);
            if (request == null) {
                return;
            }
            getClient().newCall(request).execute().close();
        } catch (Exception e) {
        }
    }

    protected final void fetchGenres() {
        Response it;
        if (!getFetchGenres() || this.fetchGenresAttempts >= 3 || this.genresFetched) {
            return;
        }
        try {
            it = (Closeable) getClient().newCall(genresRequest()).execute();
        } catch (Exception e) {
        } catch (Throwable th) {
            this.fetchGenresAttempts++;
            throw th;
        }
        try {
            List it2 = parseGenres(JsoupExtensionsKt.asJsoup$default(it, (String) null, 1, (Object) null));
            CloseableKt.closeFinally(it, (Throwable) null);
            this.genresFetched = true;
            List it3 = it2.isEmpty() ? null : it2;
            if (it3 != null) {
                setGenresList(it3);
            }
            this.fetchGenresAttempts++;
        } catch (Throwable th2) {
            try {
                throw th2;
            } catch (Throwable th3) {
                CloseableKt.closeFinally(it, th2);
                throw th3;
            }
        }
    }

    protected Request genresRequest() {
        return RequestsKt.GET$default(getBaseUrl() + "/?s=genre&post_type=wp-manga", getHeaders(), (CacheControl) null, 4, (Object) null);
    }

    protected List<Genre> parseGenres(Document document) {
        Intrinsics.checkNotNullParameter(document, "document");
        Element elementSelectFirst = document.selectFirst("div.checkbox-group");
        Iterable iterableEmptyList = (List) (elementSelectFirst != null ? elementSelectFirst.select("div.checkbox") : null);
        if (iterableEmptyList == null) {
            iterableEmptyList = CollectionsKt.emptyList();
        }
        Iterable $this$map$iv = iterableEmptyList;
        Collection destination$iv$iv = new ArrayList(CollectionsKt.collectionSizeOrDefault($this$map$iv, 10));
        for (Object item$iv$iv : $this$map$iv) {
            Element li = (Element) item$iv$iv;
            Element elementSelectFirst2 = li.selectFirst("label");
            Intrinsics.checkNotNull(elementSelectFirst2);
            String strText = elementSelectFirst2.text();
            Intrinsics.checkNotNullExpressionValue(strText, "li.selectFirst(\"label\")!!.text()");
            Element elementSelectFirst3 = li.selectFirst("input[type=checkbox]");
            Intrinsics.checkNotNull(elementSelectFirst3);
            String strVal = elementSelectFirst3.val();
            Intrinsics.checkNotNullExpressionValue(strVal, "li.selectFirst(\"input[type=checkbox]\")!!.`val`()");
            destination$iv$iv.add(new Genre(strText, strVal));
        }
        return (List) destination$iv$iv;
    }

    protected final byte[] decodeHex(String $this$decodeHex) {
        Intrinsics.checkNotNullParameter($this$decodeHex, "<this>");
        if (!($this$decodeHex.length() % 2 == 0)) {
            throw new IllegalStateException("Must have an even length".toString());
        }
        Iterable $this$map$iv = StringsKt.chunked($this$decodeHex, 2);
        Collection destination$iv$iv = new ArrayList(CollectionsKt.collectionSizeOrDefault($this$map$iv, 10));
        for (Object item$iv$iv : $this$map$iv) {
            String it = (String) item$iv$iv;
            destination$iv$iv.add(Byte.valueOf((byte) Integer.parseInt(it, CharsKt.checkRadix(16))));
        }
        return CollectionsKt.toByteArray((List) destination$iv$iv);
    }

    protected final byte[] getSalted() {
        return this.salted;
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\n\n\u0000\n\u0002\u0010\u0002\n\u0002\u0018\u0002\u0010\u0000\u001a\u00020\u0001*\u00020\u0002H\u008a@"}, d2 = {"<anonymous>", "", "Lkotlinx/coroutines/CoroutineScope;"}, k = 3, mv = {1, 7, 1}, xi = 48)
    @DebugMetadata(c = "eu.kanade.tachiyomi.multisrc.madara.Madara$launchIO$1", f = "Madara.kt", i = {}, l = {}, m = "invokeSuspend", n = {}, s = {})
    /* renamed from: eu.kanade.tachiyomi.multisrc.madara.Madara$launchIO$1, reason: invalid class name and case insensitive filesystem */
    static final class C00021 extends SuspendLambda implements Function2<CoroutineScope, Continuation<? super Unit>, Object> {
        final /* synthetic */ Function0<Unit> $block;
        int label;

        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        C00021(Function0<Unit> function0, Continuation<? super C00021> continuation) {
            super(2, continuation);
            this.$block = function0;
        }

        public final Continuation<Unit> create(Object obj, Continuation<?> continuation) {
            return new C00021(this.$block, continuation);
        }

        public final Object invoke(CoroutineScope coroutineScope, Continuation<? super Unit> continuation) {
            return create(coroutineScope, continuation).invokeSuspend(Unit.INSTANCE);
        }

        public final Object invokeSuspend(Object obj) {
            IntrinsicsKt.getCOROUTINE_SUSPENDED();
            switch (this.label) {
                case 0:
                    ResultKt.throwOnFailure(obj);
                    this.$block.invoke();
                    return Unit.INSTANCE;
                default:
                    throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
            }
        }
    }

    protected final Job launchIO(Function0<Unit> block) {
        Intrinsics.checkNotNullParameter(block, "block");
        return BuildersKt.launch$default(this.scope, (CoroutineContext) null, (CoroutineStart) null, new C00021(block, null), 3, (Object) null);
    }

    /* compiled from: Madara.kt */
    @Metadata(d1 = {"\u0000\u001a\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002R\u0011\u0010\u0003\u001a\u00020\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0005\u0010\u0006R\u000e\u0010\u0007\u001a\u00020\bX\u0086T¢\u0006\u0002\n\u0000¨\u0006\t"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/Madara$Companion;", "", "()V", "URL_REGEX", "Lkotlin/text/Regex;", "getURL_REGEX", "()Lkotlin/text/Regex;", "URL_SEARCH_PREFIX", "", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final Regex getURL_REGEX() {
            return Madara.URL_REGEX;
        }
    }
}
