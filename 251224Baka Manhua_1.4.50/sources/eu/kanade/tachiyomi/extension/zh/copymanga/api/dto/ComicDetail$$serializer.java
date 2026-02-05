package eu.kanade.tachiyomi.extension.zh.copymanga.api.dto;

import java.util.List;
import kotlin.Deprecated;
import kotlin.DeprecationLevel;
import kotlin.Metadata;
import kotlin.ReplaceWith;
import kotlin.jvm.internal.Intrinsics;
import kotlin.jvm.internal.Reflection;
import kotlinx.serialization.ContextualSerializer;
import kotlinx.serialization.KSerializer;
import kotlinx.serialization.UnknownFieldException;
import kotlinx.serialization.builtins.BuiltinSerializersKt;
import kotlinx.serialization.descriptors.SerialDescriptor;
import kotlinx.serialization.encoding.CompositeDecoder;
import kotlinx.serialization.encoding.CompositeEncoder;
import kotlinx.serialization.encoding.Decoder;
import kotlinx.serialization.encoding.Encoder;
import kotlinx.serialization.internal.ArrayListSerializer;
import kotlinx.serialization.internal.BooleanSerializer;
import kotlinx.serialization.internal.GeneratedSerializer;
import kotlinx.serialization.internal.IntSerializer;
import kotlinx.serialization.internal.PluginGeneratedSerialDescriptor;
import kotlinx.serialization.internal.SerializationConstructorMarker;
import kotlinx.serialization.internal.StringSerializer;
import kotlinx.serialization.json.JsonElement;
import kotlinx.serialization.json.JsonElementSerializer;

/* compiled from: ComicDetailResult.kt */
@Metadata(d1 = {"\u00006\n\u0000\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010\u0011\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\bÇ\u0002\u0018\u00002\b\u0012\u0004\u0012\u00020\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0003J\u0018\u0010\b\u001a\f\u0012\b\u0012\u0006\u0012\u0002\b\u00030\n0\tHÖ\u0001¢\u0006\u0002\u0010\u000bJ\u0011\u0010\f\u001a\u00020\u00022\u0006\u0010\r\u001a\u00020\u000eHÖ\u0001J\u0019\u0010\u000f\u001a\u00020\u00102\u0006\u0010\u0011\u001a\u00020\u00122\u0006\u0010\u0013\u001a\u00020\u0002HÖ\u0001R\u0014\u0010\u0004\u001a\u00020\u00058VXÖ\u0005¢\u0006\u0006\u001a\u0004\b\u0006\u0010\u0007¨\u0006\u0014"}, d2 = {"eu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicDetail.$serializer", "Lkotlinx/serialization/internal/GeneratedSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicDetail;", "()V", "descriptor", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "getDescriptor", "()Lkotlinx/serialization/descriptors/SerialDescriptor;", "childSerializers", "", "Lkotlinx/serialization/KSerializer;", "()[Lkotlinx/serialization/KSerializer;", "deserialize", "decoder", "Lkotlinx/serialization/encoding/Decoder;", "serialize", "", "encoder", "Lkotlinx/serialization/encoding/Encoder;", "value", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
/* loaded from: classes.dex */
public final class ComicDetail$$serializer implements GeneratedSerializer<ComicDetail> {
    public static final ComicDetail$$serializer INSTANCE;
    public static final /* synthetic */ SerialDescriptor descriptor;

    public SerialDescriptor getDescriptor() {
        return descriptor;
    }

    static {
        ComicDetail$$serializer comicDetail$$serializer = new ComicDetail$$serializer();
        INSTANCE = comicDetail$$serializer;
        SerialDescriptor pluginGeneratedSerialDescriptor = new PluginGeneratedSerialDescriptor("eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ComicDetail", comicDetail$$serializer, 26);
        pluginGeneratedSerialDescriptor.addElement("uuid", false);
        pluginGeneratedSerialDescriptor.addElement("b_404", false);
        pluginGeneratedSerialDescriptor.addElement("b_hidden", false);
        pluginGeneratedSerialDescriptor.addElement("ban", false);
        pluginGeneratedSerialDescriptor.addElement("name", false);
        pluginGeneratedSerialDescriptor.addElement("alias", true);
        pluginGeneratedSerialDescriptor.addElement("path_word", false);
        pluginGeneratedSerialDescriptor.addElement("close_comment", false);
        pluginGeneratedSerialDescriptor.addElement("close_roast", false);
        pluginGeneratedSerialDescriptor.addElement("free_type", true);
        pluginGeneratedSerialDescriptor.addElement("restrict", false);
        pluginGeneratedSerialDescriptor.addElement("reclass", false);
        pluginGeneratedSerialDescriptor.addElement("females", true);
        pluginGeneratedSerialDescriptor.addElement("males", true);
        pluginGeneratedSerialDescriptor.addElement("clubs", true);
        pluginGeneratedSerialDescriptor.addElement("seo_baidu", false);
        pluginGeneratedSerialDescriptor.addElement("region", false);
        pluginGeneratedSerialDescriptor.addElement("status", false);
        pluginGeneratedSerialDescriptor.addElement("author", false);
        pluginGeneratedSerialDescriptor.addElement("theme", true);
        pluginGeneratedSerialDescriptor.addElement("parodies", true);
        pluginGeneratedSerialDescriptor.addElement("brief", false);
        pluginGeneratedSerialDescriptor.addElement("datetime_updated", true);
        pluginGeneratedSerialDescriptor.addElement("cover", false);
        pluginGeneratedSerialDescriptor.addElement("last_chapter", false);
        pluginGeneratedSerialDescriptor.addElement("popular", false);
        descriptor = pluginGeneratedSerialDescriptor;
    }

    private ComicDetail$$serializer() {
    }

    public KSerializer<?>[] childSerializers() {
        return new KSerializer[]{(KSerializer) StringSerializer.INSTANCE, (KSerializer) BooleanSerializer.INSTANCE, (KSerializer) BooleanSerializer.INSTANCE, (KSerializer) IntSerializer.INSTANCE, (KSerializer) StringSerializer.INSTANCE, (KSerializer) StringSerializer.INSTANCE, (KSerializer) StringSerializer.INSTANCE, (KSerializer) BooleanSerializer.INSTANCE, (KSerializer) BooleanSerializer.INSTANCE, BuiltinSerializersKt.getNullable(FreeType$$serializer.INSTANCE), (KSerializer) Restrict$$serializer.INSTANCE, (KSerializer) Reclass$$serializer.INSTANCE, (KSerializer) new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (KSerializer) new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (KSerializer) new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (KSerializer) StringSerializer.INSTANCE, (KSerializer) Region$$serializer.INSTANCE, (KSerializer) Status$$serializer.INSTANCE, (KSerializer) new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), (KSerializer) new ArrayListSerializer(ThemeInfo$$serializer.INSTANCE), (KSerializer) new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (KSerializer) StringSerializer.INSTANCE, BuiltinSerializersKt.getNullable(StringSerializer.INSTANCE), (KSerializer) StringSerializer.INSTANCE, (KSerializer) LastChapter$$serializer.INSTANCE, (KSerializer) IntSerializer.INSTANCE};
    }

    /* JADX INFO: Thrown type has an unknown type hierarchy: kotlinx.serialization.UnknownFieldException */
    /* renamed from: deserialize, reason: merged with bridge method [inline-methods] */
    public ComicDetail m19deserialize(Decoder decoder) throws UnknownFieldException {
        Object objDecodeSerializableElement;
        Object objDecodeSerializableElement2;
        String strDecodeStringElement;
        String strDecodeStringElement2;
        String strDecodeStringElement3;
        String strDecodeStringElement4;
        String strDecodeStringElement5;
        int i;
        boolean zDecodeBooleanElement;
        int iDecodeIntElement;
        boolean zDecodeBooleanElement2;
        Object objDecodeSerializableElement3;
        Object obj;
        Object objDecodeSerializableElement4;
        Object obj2;
        Object obj3;
        Object obj4;
        int iDecodeIntElement2;
        boolean zDecodeBooleanElement3;
        boolean zDecodeBooleanElement4;
        String str;
        String str2;
        Object obj5;
        Object obj6;
        Object obj7;
        Object obj8;
        Object obj9;
        int i2;
        Object obj10;
        Object obj11;
        Object obj12;
        Object obj13;
        Object obj14;
        Object obj15;
        Object obj16;
        Object obj17;
        Object obj18;
        int i3;
        Object obj19;
        Object obj20;
        int i4;
        Intrinsics.checkNotNullParameter(decoder, "decoder");
        SerialDescriptor descriptor2 = getDescriptor();
        CompositeDecoder compositeDecoderBeginStructure = decoder.beginStructure(descriptor2);
        if (compositeDecoderBeginStructure.decodeSequentially()) {
            String strDecodeStringElement6 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 0);
            zDecodeBooleanElement4 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 1);
            zDecodeBooleanElement3 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 2);
            int iDecodeIntElement3 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 3);
            String strDecodeStringElement7 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 4);
            String strDecodeStringElement8 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 5);
            String strDecodeStringElement9 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 6);
            boolean zDecodeBooleanElement5 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 7);
            boolean zDecodeBooleanElement6 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 8);
            Object objDecodeNullableSerializableElement = compositeDecoderBeginStructure.decodeNullableSerializableElement(descriptor2, 9, FreeType$$serializer.INSTANCE, (Object) null);
            Object objDecodeSerializableElement5 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 10, Restrict$$serializer.INSTANCE, (Object) null);
            Object objDecodeSerializableElement6 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 11, Reclass$$serializer.INSTANCE, (Object) null);
            str2 = strDecodeStringElement8;
            Object objDecodeSerializableElement7 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 12, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (Object) null);
            objDecodeSerializableElement4 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 13, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (Object) null);
            Object objDecodeSerializableElement8 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 14, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (Object) null);
            String strDecodeStringElement10 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 15);
            Object objDecodeSerializableElement9 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 16, Region$$serializer.INSTANCE, (Object) null);
            Object objDecodeSerializableElement10 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 17, Status$$serializer.INSTANCE, (Object) null);
            Object objDecodeSerializableElement11 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 18, new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), (Object) null);
            Object objDecodeSerializableElement12 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 19, new ArrayListSerializer(ThemeInfo$$serializer.INSTANCE), (Object) null);
            obj4 = objDecodeSerializableElement11;
            Object objDecodeSerializableElement13 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 20, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (Object) null);
            String strDecodeStringElement11 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 21);
            Object objDecodeNullableSerializableElement2 = compositeDecoderBeginStructure.decodeNullableSerializableElement(descriptor2, 22, StringSerializer.INSTANCE, (Object) null);
            String strDecodeStringElement12 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 23);
            objDecodeSerializableElement3 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 24, LastChapter$$serializer.INSTANCE, (Object) null);
            iDecodeIntElement2 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 25);
            obj = objDecodeNullableSerializableElement2;
            strDecodeStringElement5 = strDecodeStringElement12;
            zDecodeBooleanElement2 = zDecodeBooleanElement5;
            strDecodeStringElement2 = strDecodeStringElement9;
            strDecodeStringElement3 = strDecodeStringElement10;
            obj8 = objDecodeSerializableElement8;
            strDecodeStringElement4 = strDecodeStringElement11;
            obj2 = objDecodeSerializableElement7;
            iDecodeIntElement = iDecodeIntElement3;
            str = strDecodeStringElement6;
            strDecodeStringElement = strDecodeStringElement7;
            zDecodeBooleanElement = zDecodeBooleanElement6;
            obj5 = objDecodeSerializableElement10;
            obj3 = objDecodeSerializableElement6;
            obj9 = objDecodeSerializableElement5;
            obj6 = objDecodeSerializableElement9;
            objDecodeSerializableElement2 = objDecodeSerializableElement12;
            objDecodeSerializableElement = objDecodeSerializableElement13;
            obj7 = objDecodeNullableSerializableElement;
            i = 67108863;
        } else {
            Object objDecodeSerializableElement14 = null;
            Object objDecodeSerializableElement15 = null;
            Object objDecodeSerializableElement16 = null;
            Object objDecodeSerializableElement17 = null;
            Object objDecodeSerializableElement18 = null;
            Object objDecodeSerializableElement19 = null;
            Object objDecodeNullableSerializableElement3 = null;
            objDecodeSerializableElement = null;
            objDecodeSerializableElement2 = null;
            Object objDecodeSerializableElement20 = null;
            Object objDecodeSerializableElement21 = null;
            Object objDecodeSerializableElement22 = null;
            String strDecodeStringElement13 = null;
            strDecodeStringElement = null;
            String strDecodeStringElement14 = null;
            strDecodeStringElement2 = null;
            strDecodeStringElement3 = null;
            strDecodeStringElement4 = null;
            strDecodeStringElement5 = null;
            Object objDecodeNullableSerializableElement4 = null;
            boolean z = true;
            i = 0;
            int iDecodeIntElement4 = 0;
            zDecodeBooleanElement = false;
            boolean zDecodeBooleanElement7 = false;
            boolean zDecodeBooleanElement8 = false;
            iDecodeIntElement = 0;
            zDecodeBooleanElement2 = false;
            while (z) {
                boolean z2 = z;
                int iDecodeElementIndex = compositeDecoderBeginStructure.decodeElementIndex(descriptor2);
                switch (iDecodeElementIndex) {
                    case -1:
                        obj10 = objDecodeNullableSerializableElement3;
                        z = false;
                        objDecodeSerializableElement15 = objDecodeSerializableElement15;
                        objDecodeSerializableElement18 = objDecodeSerializableElement18;
                        objDecodeNullableSerializableElement3 = obj10;
                    case 0:
                        obj11 = objDecodeSerializableElement19;
                        obj10 = objDecodeNullableSerializableElement3;
                        obj12 = objDecodeSerializableElement18;
                        obj13 = objDecodeSerializableElement15;
                        strDecodeStringElement13 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 0);
                        i |= 1;
                        objDecodeSerializableElement15 = obj13;
                        objDecodeSerializableElement18 = obj12;
                        z = z2;
                        objDecodeSerializableElement19 = obj11;
                        objDecodeNullableSerializableElement3 = obj10;
                    case 1:
                        obj11 = objDecodeSerializableElement19;
                        obj10 = objDecodeNullableSerializableElement3;
                        obj12 = objDecodeSerializableElement18;
                        obj13 = objDecodeSerializableElement15;
                        zDecodeBooleanElement8 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 1);
                        i |= 2;
                        objDecodeSerializableElement15 = obj13;
                        objDecodeSerializableElement18 = obj12;
                        z = z2;
                        objDecodeSerializableElement19 = obj11;
                        objDecodeNullableSerializableElement3 = obj10;
                    case 2:
                        obj11 = objDecodeSerializableElement19;
                        obj10 = objDecodeNullableSerializableElement3;
                        obj12 = objDecodeSerializableElement18;
                        obj13 = objDecodeSerializableElement15;
                        zDecodeBooleanElement7 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 2);
                        i |= 4;
                        objDecodeSerializableElement15 = obj13;
                        objDecodeSerializableElement18 = obj12;
                        z = z2;
                        objDecodeSerializableElement19 = obj11;
                        objDecodeNullableSerializableElement3 = obj10;
                    case 3:
                        obj11 = objDecodeSerializableElement19;
                        obj10 = objDecodeNullableSerializableElement3;
                        obj12 = objDecodeSerializableElement18;
                        obj13 = objDecodeSerializableElement15;
                        iDecodeIntElement = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 3);
                        i |= 8;
                        objDecodeSerializableElement15 = obj13;
                        objDecodeSerializableElement18 = obj12;
                        z = z2;
                        objDecodeSerializableElement19 = obj11;
                        objDecodeNullableSerializableElement3 = obj10;
                    case 4:
                        obj11 = objDecodeSerializableElement19;
                        obj10 = objDecodeNullableSerializableElement3;
                        obj12 = objDecodeSerializableElement18;
                        obj13 = objDecodeSerializableElement15;
                        strDecodeStringElement = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 4);
                        i |= 16;
                        objDecodeSerializableElement15 = obj13;
                        objDecodeSerializableElement18 = obj12;
                        z = z2;
                        objDecodeSerializableElement19 = obj11;
                        objDecodeNullableSerializableElement3 = obj10;
                    case 5:
                        obj11 = objDecodeSerializableElement19;
                        obj10 = objDecodeNullableSerializableElement3;
                        obj12 = objDecodeSerializableElement18;
                        obj13 = objDecodeSerializableElement15;
                        strDecodeStringElement14 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 5);
                        i |= 32;
                        objDecodeSerializableElement15 = obj13;
                        objDecodeSerializableElement18 = obj12;
                        z = z2;
                        objDecodeSerializableElement19 = obj11;
                        objDecodeNullableSerializableElement3 = obj10;
                    case 6:
                        obj11 = objDecodeSerializableElement19;
                        obj10 = objDecodeNullableSerializableElement3;
                        obj12 = objDecodeSerializableElement18;
                        obj13 = objDecodeSerializableElement15;
                        strDecodeStringElement2 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 6);
                        i |= 64;
                        objDecodeSerializableElement15 = obj13;
                        objDecodeSerializableElement18 = obj12;
                        z = z2;
                        objDecodeSerializableElement19 = obj11;
                        objDecodeNullableSerializableElement3 = obj10;
                    case 7:
                        obj11 = objDecodeSerializableElement19;
                        obj10 = objDecodeNullableSerializableElement3;
                        obj12 = objDecodeSerializableElement18;
                        obj13 = objDecodeSerializableElement15;
                        zDecodeBooleanElement2 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 7);
                        i |= 128;
                        objDecodeSerializableElement15 = obj13;
                        objDecodeSerializableElement18 = obj12;
                        z = z2;
                        objDecodeSerializableElement19 = obj11;
                        objDecodeNullableSerializableElement3 = obj10;
                    case 8:
                        obj11 = objDecodeSerializableElement19;
                        obj10 = objDecodeNullableSerializableElement3;
                        obj12 = objDecodeSerializableElement18;
                        obj13 = objDecodeSerializableElement15;
                        zDecodeBooleanElement = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 8);
                        i |= 256;
                        objDecodeSerializableElement15 = obj13;
                        objDecodeSerializableElement18 = obj12;
                        z = z2;
                        objDecodeSerializableElement19 = obj11;
                        objDecodeNullableSerializableElement3 = obj10;
                    case 9:
                        obj11 = objDecodeSerializableElement19;
                        obj10 = objDecodeNullableSerializableElement3;
                        obj12 = objDecodeSerializableElement18;
                        obj13 = objDecodeSerializableElement15;
                        objDecodeNullableSerializableElement4 = compositeDecoderBeginStructure.decodeNullableSerializableElement(descriptor2, 9, FreeType$$serializer.INSTANCE, objDecodeNullableSerializableElement4);
                        i |= 512;
                        objDecodeSerializableElement15 = obj13;
                        objDecodeSerializableElement18 = obj12;
                        z = z2;
                        objDecodeSerializableElement19 = obj11;
                        objDecodeNullableSerializableElement3 = obj10;
                    case 10:
                        i |= 1024;
                        objDecodeSerializableElement15 = objDecodeSerializableElement15;
                        objDecodeSerializableElement19 = objDecodeSerializableElement19;
                        objDecodeNullableSerializableElement3 = objDecodeNullableSerializableElement3;
                        objDecodeSerializableElement18 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 10, Restrict$$serializer.INSTANCE, objDecodeSerializableElement18);
                        z = z2;
                    case 11:
                        i |= 2048;
                        objDecodeSerializableElement15 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 11, Reclass$$serializer.INSTANCE, objDecodeSerializableElement15);
                        z = z2;
                        objDecodeSerializableElement18 = objDecodeSerializableElement18;
                        objDecodeSerializableElement19 = objDecodeSerializableElement19;
                    case 12:
                        obj11 = objDecodeSerializableElement19;
                        obj10 = objDecodeNullableSerializableElement3;
                        objDecodeSerializableElement16 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 12, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), objDecodeSerializableElement16);
                        i |= 4096;
                        z = z2;
                        objDecodeSerializableElement18 = objDecodeSerializableElement18;
                        objDecodeSerializableElement15 = objDecodeSerializableElement15;
                        objDecodeSerializableElement19 = obj11;
                        objDecodeNullableSerializableElement3 = obj10;
                    case 13:
                        obj14 = objDecodeSerializableElement15;
                        obj15 = objDecodeSerializableElement16;
                        obj16 = objDecodeSerializableElement18;
                        obj17 = objDecodeSerializableElement19;
                        obj18 = objDecodeNullableSerializableElement3;
                        objDecodeSerializableElement14 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 13, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), objDecodeSerializableElement14);
                        i |= 8192;
                        z = z2;
                        objDecodeSerializableElement18 = obj16;
                        objDecodeSerializableElement15 = obj14;
                        objDecodeSerializableElement19 = obj17;
                        objDecodeNullableSerializableElement3 = obj18;
                        objDecodeSerializableElement16 = obj15;
                    case 14:
                        obj14 = objDecodeSerializableElement15;
                        obj15 = objDecodeSerializableElement16;
                        obj16 = objDecodeSerializableElement18;
                        obj17 = objDecodeSerializableElement19;
                        obj18 = objDecodeNullableSerializableElement3;
                        objDecodeSerializableElement22 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 14, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), objDecodeSerializableElement22);
                        i |= 16384;
                        z = z2;
                        objDecodeSerializableElement18 = obj16;
                        objDecodeSerializableElement15 = obj14;
                        objDecodeSerializableElement19 = obj17;
                        objDecodeNullableSerializableElement3 = obj18;
                        objDecodeSerializableElement16 = obj15;
                    case 15:
                        obj14 = objDecodeSerializableElement15;
                        obj15 = objDecodeSerializableElement16;
                        obj16 = objDecodeSerializableElement18;
                        obj17 = objDecodeSerializableElement19;
                        obj18 = objDecodeNullableSerializableElement3;
                        strDecodeStringElement3 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 15);
                        i |= 32768;
                        z = z2;
                        objDecodeSerializableElement18 = obj16;
                        objDecodeSerializableElement15 = obj14;
                        objDecodeSerializableElement19 = obj17;
                        objDecodeNullableSerializableElement3 = obj18;
                        objDecodeSerializableElement16 = obj15;
                    case 16:
                        obj14 = objDecodeSerializableElement15;
                        obj15 = objDecodeSerializableElement16;
                        obj16 = objDecodeSerializableElement18;
                        obj17 = objDecodeSerializableElement19;
                        obj18 = objDecodeNullableSerializableElement3;
                        objDecodeSerializableElement21 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 16, Region$$serializer.INSTANCE, objDecodeSerializableElement21);
                        i3 = 65536;
                        i |= i3;
                        z = z2;
                        objDecodeSerializableElement18 = obj16;
                        objDecodeSerializableElement15 = obj14;
                        objDecodeSerializableElement19 = obj17;
                        objDecodeNullableSerializableElement3 = obj18;
                        objDecodeSerializableElement16 = obj15;
                    case 17:
                        obj15 = objDecodeSerializableElement16;
                        objDecodeSerializableElement17 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 17, Status$$serializer.INSTANCE, objDecodeSerializableElement17);
                        i |= 131072;
                        z = z2;
                        objDecodeSerializableElement18 = objDecodeSerializableElement18;
                        objDecodeSerializableElement15 = objDecodeSerializableElement15;
                        objDecodeSerializableElement19 = objDecodeSerializableElement19;
                        objDecodeSerializableElement16 = obj15;
                    case 18:
                        obj19 = objDecodeSerializableElement15;
                        obj15 = objDecodeSerializableElement16;
                        objDecodeSerializableElement20 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 18, new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), objDecodeSerializableElement20);
                        i |= 262144;
                        z = z2;
                        objDecodeSerializableElement18 = objDecodeSerializableElement18;
                        objDecodeSerializableElement15 = obj19;
                        objDecodeSerializableElement16 = obj15;
                    case 19:
                        obj19 = objDecodeSerializableElement15;
                        obj15 = objDecodeSerializableElement16;
                        objDecodeSerializableElement2 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 19, new ArrayListSerializer(ThemeInfo$$serializer.INSTANCE), objDecodeSerializableElement2);
                        i |= 524288;
                        z = z2;
                        objDecodeSerializableElement15 = obj19;
                        objDecodeSerializableElement16 = obj15;
                    case 20:
                        obj16 = objDecodeSerializableElement18;
                        obj17 = objDecodeSerializableElement19;
                        obj18 = objDecodeNullableSerializableElement3;
                        obj14 = objDecodeSerializableElement15;
                        obj15 = objDecodeSerializableElement16;
                        objDecodeSerializableElement = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 20, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), objDecodeSerializableElement);
                        i3 = 1048576;
                        i |= i3;
                        z = z2;
                        objDecodeSerializableElement18 = obj16;
                        objDecodeSerializableElement15 = obj14;
                        objDecodeSerializableElement19 = obj17;
                        objDecodeNullableSerializableElement3 = obj18;
                        objDecodeSerializableElement16 = obj15;
                    case 21:
                        strDecodeStringElement4 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 21);
                        i2 = 2097152;
                        i |= i2;
                        z = z2;
                    case 22:
                        obj20 = objDecodeSerializableElement18;
                        objDecodeNullableSerializableElement3 = compositeDecoderBeginStructure.decodeNullableSerializableElement(descriptor2, 22, StringSerializer.INSTANCE, objDecodeNullableSerializableElement3);
                        i4 = 4194304;
                        i |= i4;
                        z = z2;
                        objDecodeSerializableElement18 = obj20;
                    case 23:
                        strDecodeStringElement5 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 23);
                        i2 = 8388608;
                        i |= i2;
                        z = z2;
                    case 24:
                        obj20 = objDecodeSerializableElement18;
                        objDecodeSerializableElement19 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 24, LastChapter$$serializer.INSTANCE, objDecodeSerializableElement19);
                        i4 = 16777216;
                        i |= i4;
                        z = z2;
                        objDecodeSerializableElement18 = obj20;
                    case 25:
                        iDecodeIntElement4 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 25);
                        i2 = 33554432;
                        i |= i2;
                        z = z2;
                    default:
                        throw new UnknownFieldException(iDecodeElementIndex);
                }
            }
            objDecodeSerializableElement3 = objDecodeSerializableElement19;
            obj = objDecodeNullableSerializableElement3;
            Object obj21 = objDecodeSerializableElement18;
            objDecodeSerializableElement4 = objDecodeSerializableElement14;
            obj2 = objDecodeSerializableElement16;
            obj3 = objDecodeSerializableElement15;
            obj4 = objDecodeSerializableElement20;
            iDecodeIntElement2 = iDecodeIntElement4;
            zDecodeBooleanElement3 = zDecodeBooleanElement7;
            zDecodeBooleanElement4 = zDecodeBooleanElement8;
            str = strDecodeStringElement13;
            str2 = strDecodeStringElement14;
            obj5 = objDecodeSerializableElement17;
            obj6 = objDecodeSerializableElement21;
            obj7 = objDecodeNullableSerializableElement4;
            obj8 = objDecodeSerializableElement22;
            obj9 = obj21;
        }
        compositeDecoderBeginStructure.endStructure(descriptor2);
        return new ComicDetail(i, str, zDecodeBooleanElement4, zDecodeBooleanElement3, iDecodeIntElement, strDecodeStringElement, str2, strDecodeStringElement2, zDecodeBooleanElement2, zDecodeBooleanElement, (FreeType) obj7, (Restrict) obj9, (Reclass) obj3, (List) obj2, (List) objDecodeSerializableElement4, (List) obj8, strDecodeStringElement3, (Region) obj6, (Status) obj5, (List) obj4, (List) objDecodeSerializableElement2, (List) objDecodeSerializableElement, strDecodeStringElement4, (String) obj, strDecodeStringElement5, (LastChapter) objDecodeSerializableElement3, iDecodeIntElement2, (SerializationConstructorMarker) null);
    }

    public void serialize(Encoder encoder, ComicDetail value) {
        Intrinsics.checkNotNullParameter(encoder, "encoder");
        Intrinsics.checkNotNullParameter(value, "value");
        SerialDescriptor descriptor2 = getDescriptor();
        CompositeEncoder compositeEncoderBeginStructure = encoder.beginStructure(descriptor2);
        ComicDetail.write$Self(value, compositeEncoderBeginStructure, descriptor2);
        compositeEncoderBeginStructure.endStructure(descriptor2);
    }

    public KSerializer<?>[] typeParametersSerializers() {
        return GeneratedSerializer.DefaultImpls.typeParametersSerializers(this);
    }
}
