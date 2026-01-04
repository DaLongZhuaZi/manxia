package eu.kanade.tachiyomi.lib.i18n;

import java.io.InputStream;
import java.io.InputStreamReader;
import java.text.Collator;
import java.util.Arrays;
import java.util.Locale;
import java.util.PropertyResourceBundle;
import java.util.Set;
import kotlin.Lazy;
import kotlin.LazyKt;
import kotlin.Metadata;
import kotlin.jvm.functions.Function0;
import kotlin.jvm.functions.Function1;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlin.text.CharsKt;
import kotlin.text.StringsKt;

/* compiled from: Intl.kt */
@Metadata(d1 = {"\u0000F\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\"\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u000b\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0010\u0011\n\u0002\b\u0006\u0018\u0000 (2\u00020\u0001:\u0001(BA\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\f\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00030\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0003\u0012\u0006\u0010\u0007\u001a\u00020\b\u0012\u0014\b\u0002\u0010\t\u001a\u000e\u0012\u0004\u0012\u00020\u0003\u0012\u0004\u0012\u00020\u00030\n¢\u0006\u0002\u0010\u000bJ\u0010\u0010\u001e\u001a\u00020\r2\u0006\u0010\u001f\u001a\u00020\u0003H\u0002J-\u0010 \u001a\u00020\u00032\b\b\u0001\u0010!\u001a\u00020\u00032\u0016\u0010\"\u001a\f\u0012\b\b\u0001\u0012\u0004\u0018\u00010\u00010#\"\u0004\u0018\u00010\u0001¢\u0006\u0002\u0010$J\u0013\u0010%\u001a\u00020\u00032\b\b\u0001\u0010!\u001a\u00020\u0003H\u0086\u0002J\u000e\u0010&\u001a\u00020\u00032\u0006\u0010'\u001a\u00020\u0003R\u001b\u0010\f\u001a\u00020\r8BX\u0082\u0084\u0002¢\u0006\f\n\u0004\b\u0010\u0010\u0011\u001a\u0004\b\u000e\u0010\u000fR\u000e\u0010\u0006\u001a\u00020\u0003X\u0082\u0004¢\u0006\u0002\n\u0000R\u001b\u0010\u0012\u001a\u00020\r8BX\u0082\u0084\u0002¢\u0006\f\n\u0004\b\u0014\u0010\u0011\u001a\u0004\b\u0013\u0010\u000fR\u0011\u0010\u0015\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0017R\u000e\u0010\u0007\u001a\u00020\bX\u0082\u0004¢\u0006\u0002\n\u0000R\u0011\u0010\u0018\u001a\u00020\u0019¢\u0006\b\n\u0000\u001a\u0004\b\u001a\u0010\u001bR\u001a\u0010\t\u001a\u000e\u0012\u0004\u0012\u00020\u0003\u0012\u0004\u0012\u00020\u00030\nX\u0082\u0004¢\u0006\u0002\n\u0000R\u000e\u0010\u001c\u001a\u00020\u001dX\u0082\u0004¢\u0006\u0002\n\u0000¨\u0006)"}, d2 = {"Leu/kanade/tachiyomi/lib/i18n/Intl;", "", "language", "", "availableLanguages", "", "baseLanguage", "classLoader", "Ljava/lang/ClassLoader;", "createMessageFileName", "Lkotlin/Function1;", "(Ljava/lang/String;Ljava/util/Set;Ljava/lang/String;Ljava/lang/ClassLoader;Lkotlin/jvm/functions/Function1;)V", "baseBundle", "Ljava/util/PropertyResourceBundle;", "getBaseBundle", "()Ljava/util/PropertyResourceBundle;", "baseBundle$delegate", "Lkotlin/Lazy;", "bundle", "getBundle", "bundle$delegate", "chosenLanguage", "getChosenLanguage", "()Ljava/lang/String;", "collator", "Ljava/text/Collator;", "getCollator", "()Ljava/text/Collator;", "locale", "Ljava/util/Locale;", "createBundle", "lang", "format", "key", "args", "", "(Ljava/lang/String;[Ljava/lang/Object;)Ljava/lang/String;", "get", "languageDisplayName", "localeCode", "Companion", "i18n_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class Intl {

    /* renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);

    /* renamed from: baseBundle$delegate, reason: from kotlin metadata */
    private final Lazy baseBundle;
    private final String baseLanguage;

    /* renamed from: bundle$delegate, reason: from kotlin metadata */
    private final Lazy bundle;
    private final String chosenLanguage;
    private final ClassLoader classLoader;
    private final Collator collator;
    private final Function1<String, String> createMessageFileName;
    private final Locale locale;

    /* JADX WARN: Multi-variable type inference failed */
    public Intl(String language, Set<String> set, String baseLanguage, ClassLoader classLoader, Function1<? super String, String> function1) {
        Intrinsics.checkNotNullParameter(language, "language");
        Intrinsics.checkNotNullParameter(set, "availableLanguages");
        Intrinsics.checkNotNullParameter(baseLanguage, "baseLanguage");
        Intrinsics.checkNotNullParameter(classLoader, "classLoader");
        Intrinsics.checkNotNullParameter(function1, "createMessageFileName");
        this.baseLanguage = baseLanguage;
        this.classLoader = classLoader;
        this.createMessageFileName = function1;
        this.chosenLanguage = set.contains(language) ? language : this.baseLanguage;
        Locale localeForLanguageTag = Locale.forLanguageTag(this.chosenLanguage);
        Intrinsics.checkNotNullExpressionValue(localeForLanguageTag, "forLanguageTag(chosenLanguage)");
        this.locale = localeForLanguageTag;
        Collator collator = Collator.getInstance(this.locale);
        Intrinsics.checkNotNullExpressionValue(collator, "getInstance(locale)");
        this.collator = collator;
        this.baseBundle = LazyKt.lazy(new Function0<PropertyResourceBundle>() { // from class: eu.kanade.tachiyomi.lib.i18n.Intl$baseBundle$2
            {
                super(0);
            }

            public final PropertyResourceBundle invoke() {
                return this.this$0.createBundle(this.this$0.baseLanguage);
            }
        });
        this.bundle = LazyKt.lazy(new Function0<PropertyResourceBundle>() { // from class: eu.kanade.tachiyomi.lib.i18n.Intl$bundle$2
            {
                super(0);
            }

            public final PropertyResourceBundle invoke() {
                return Intrinsics.areEqual(this.this$0.getChosenLanguage(), this.this$0.baseLanguage) ? this.this$0.getBaseBundle() : this.this$0.createBundle(this.this$0.getChosenLanguage());
            }
        });
    }

    /* JADX WARN: Illegal instructions before constructor call */
    public /* synthetic */ Intl(String str, Set set, String str2, ClassLoader classLoader, Function1 function1, int i, DefaultConstructorMarker defaultConstructorMarker) {
        Function1 function12;
        if ((i & 16) == 0) {
            function12 = function1;
        } else {
            function12 = new Function1<String, String>() { // from class: eu.kanade.tachiyomi.lib.i18n.Intl.1
                public final String invoke(String it) {
                    Intrinsics.checkNotNullParameter(it, "it");
                    return Intl.INSTANCE.createDefaultMessageFileName(it);
                }
            };
        }
        this(str, set, str2, classLoader, function12);
    }

    public final String getChosenLanguage() {
        return this.chosenLanguage;
    }

    public final Collator getCollator() {
        return this.collator;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public final PropertyResourceBundle getBaseBundle() {
        return (PropertyResourceBundle) this.baseBundle.getValue();
    }

    private final PropertyResourceBundle getBundle() {
        return (PropertyResourceBundle) this.bundle.getValue();
    }

    public final String get(String key) {
        Intrinsics.checkNotNullParameter(key, "key");
        if (!getBundle().containsKey(key)) {
            if (!getBaseBundle().containsKey(key)) {
                return '[' + key + ']';
            }
            String string = getBaseBundle().getString(key);
            Intrinsics.checkNotNullExpressionValue(string, "baseBundle.getString(key)");
            return string;
        }
        String string2 = getBundle().getString(key);
        Intrinsics.checkNotNullExpressionValue(string2, "bundle.getString(key)");
        return string2;
    }

    public final String format(String key, Object... args) {
        Intrinsics.checkNotNullParameter(key, "key");
        Intrinsics.checkNotNullParameter(args, "args");
        String str = get(key);
        Locale locale = this.locale;
        Object[] objArrCopyOf = Arrays.copyOf(args, args.length);
        String str2 = String.format(locale, str, Arrays.copyOf(objArrCopyOf, objArrCopyOf.length));
        Intrinsics.checkNotNullExpressionValue(str2, "format(locale, this, *args)");
        return str2;
    }

    public final String languageDisplayName(String localeCode) {
        Intrinsics.checkNotNullParameter(localeCode, "localeCode");
        String displayName = Locale.forLanguageTag(localeCode).getDisplayName(this.locale);
        Intrinsics.checkNotNullExpressionValue(displayName, "forLanguageTag(localeCod…  .getDisplayName(locale)");
        if (!(displayName.length() > 0)) {
            return displayName;
        }
        StringBuilder sb = new StringBuilder();
        char it = displayName.charAt(0);
        StringBuilder sbAppend = sb.append((Object) (Character.isLowerCase(it) ? CharsKt.titlecase(it, this.locale) : String.valueOf(it)));
        String strSubstring = displayName.substring(1);
        Intrinsics.checkNotNullExpressionValue(strSubstring, "this as java.lang.String).substring(startIndex)");
        return sbAppend.append(strSubstring).toString();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public final PropertyResourceBundle createBundle(String lang) {
        String fileName = (String) this.createMessageFileName.invoke(lang);
        InputStream fileContent = this.classLoader.getResourceAsStream(fileName);
        return new PropertyResourceBundle(new InputStreamReader(fileContent, "UTF-8"));
    }

    /* compiled from: Intl.kt */
    @Metadata(d1 = {"\u0000\u0014\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000e\u0010\u0003\u001a\u00020\u00042\u0006\u0010\u0005\u001a\u00020\u0004¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/lib/i18n/Intl$Companion;", "", "()V", "createDefaultMessageFileName", "", "lang", "i18n_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final String createDefaultMessageFileName(String lang) {
            Intrinsics.checkNotNullParameter(lang, "lang");
            String langSnakeCase = StringsKt.replace$default(lang, "-", "_", false, 4, (Object) null).toLowerCase(Locale.ROOT);
            Intrinsics.checkNotNullExpressionValue(langSnakeCase, "this as java.lang.String).toLowerCase(Locale.ROOT)");
            return "assets/i18n/messages_" + langSnakeCase + ".properties";
        }
    }
}
