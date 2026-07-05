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

/* JADX INFO: compiled from: CollectResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u00006\n\u0000\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010\u0011\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\bÇ\u0002\u0018\u00002\b\u0012\u0004\u0012\u00020\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0003J\u0018\u0010\b\u001a\f\u0012\b\u0012\u0006\u0012\u0002\b\u00030\n0\tHÖ\u0001¢\u0006\u0002\u0010\u000bJ\u0011\u0010\f\u001a\u00020\u00022\u0006\u0010\r\u001a\u00020\u000eHÖ\u0001J\u0019\u0010\u000f\u001a\u00020\u00102\u0006\u0010\u0011\u001a\u00020\u00122\u0006\u0010\u0013\u001a\u00020\u0002HÖ\u0001R\u0014\u0010\u0004\u001a\u00020\u00058VXÖ\u0005¢\u0006\u0006\u001a\u0004\b\u0006\u0010\u0007¨\u0006\u0014"}, d2 = {"eu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectComic.$serializer", "Lkotlinx/serialization/internal/GeneratedSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectComic;", "()V", "descriptor", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "getDescriptor", "()Lkotlinx/serialization/descriptors/SerialDescriptor;", "childSerializers", "", "Lkotlinx/serialization/KSerializer;", "()[Lkotlinx/serialization/KSerializer;", "deserialize", "decoder", "Lkotlinx/serialization/encoding/Decoder;", "serialize", "", "encoder", "Lkotlinx/serialization/encoding/Encoder;", "value", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
public final class CollectComic$$serializer implements GeneratedSerializer<CollectComic> {
    public static final CollectComic$$serializer INSTANCE;
    public static final /* synthetic */ SerialDescriptor descriptor;

    public SerialDescriptor getDescriptor() {
        return descriptor;
    }

    static {
        CollectComic$$serializer collectComic$$serializer = new CollectComic$$serializer();
        INSTANCE = collectComic$$serializer;
        SerialDescriptor pluginGeneratedSerialDescriptor = new PluginGeneratedSerialDescriptor("eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.CollectComic", collectComic$$serializer, 15);
        pluginGeneratedSerialDescriptor.addElement("uuid", false);
        pluginGeneratedSerialDescriptor.addElement("b_display", false);
        pluginGeneratedSerialDescriptor.addElement("name", false);
        pluginGeneratedSerialDescriptor.addElement("path_word", false);
        pluginGeneratedSerialDescriptor.addElement("females", true);
        pluginGeneratedSerialDescriptor.addElement("males", true);
        pluginGeneratedSerialDescriptor.addElement("author", false);
        pluginGeneratedSerialDescriptor.addElement("theme", true);
        pluginGeneratedSerialDescriptor.addElement("cover", false);
        pluginGeneratedSerialDescriptor.addElement("status", true);
        pluginGeneratedSerialDescriptor.addElement("popular", false);
        pluginGeneratedSerialDescriptor.addElement("datetime_updated", false);
        pluginGeneratedSerialDescriptor.addElement("last_chapter_id", false);
        pluginGeneratedSerialDescriptor.addElement("last_chapter_name", false);
        pluginGeneratedSerialDescriptor.addElement("browse", true);
        descriptor = pluginGeneratedSerialDescriptor;
    }

    private CollectComic$$serializer() {
    }

    public KSerializer<?>[] childSerializers() {
        return new KSerializer[]{(KSerializer) StringSerializer.INSTANCE, (KSerializer) BooleanSerializer.INSTANCE, (KSerializer) StringSerializer.INSTANCE, (KSerializer) StringSerializer.INSTANCE, (KSerializer) new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (KSerializer) new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (KSerializer) new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), (KSerializer) new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(ThemeInfo.class), ThemeInfo$$serializer.INSTANCE, new KSerializer[0])), (KSerializer) StringSerializer.INSTANCE, BuiltinSerializersKt.getNullable(IntSerializer.INSTANCE), (KSerializer) IntSerializer.INSTANCE, (KSerializer) StringSerializer.INSTANCE, (KSerializer) StringSerializer.INSTANCE, (KSerializer) StringSerializer.INSTANCE, BuiltinSerializersKt.getNullable(Browse$$serializer.INSTANCE)};
    }

    /* JADX INFO: Thrown type has an unknown type hierarchy: kotlinx.serialization.UnknownFieldException */
    /* JADX INFO: renamed from: deserialize, reason: merged with bridge method [inline-methods] */
    public CollectComic m18deserialize(Decoder decoder) throws UnknownFieldException {
        Object objDecodeSerializableElement;
        Object objDecodeSerializableElement2;
        Object objDecodeNullableSerializableElement;
        Object objDecodeSerializableElement3;
        Object objDecodeNullableSerializableElement2;
        String str;
        String str2;
        String str3;
        String str4;
        int i;
        boolean z;
        String str5;
        int i2;
        Object objDecodeSerializableElement4;
        String str6;
        String str7;
        boolean z2;
        String str8;
        String str9;
        boolean z3;
        Intrinsics.checkNotNullParameter(decoder, "decoder");
        SerialDescriptor descriptor2 = getDescriptor();
        CompositeDecoder compositeDecoderBeginStructure = decoder.beginStructure(descriptor2);
        if (compositeDecoderBeginStructure.decodeSequentially()) {
            String strDecodeStringElement = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 0);
            boolean zDecodeBooleanElement = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 1);
            String strDecodeStringElement2 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 2);
            String strDecodeStringElement3 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 3);
            objDecodeSerializableElement4 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 4, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (Object) null);
            objDecodeSerializableElement2 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 5, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (Object) null);
            objDecodeSerializableElement = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 6, new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), (Object) null);
            objDecodeSerializableElement3 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 7, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(ThemeInfo.class), ThemeInfo$$serializer.INSTANCE, new KSerializer[0])), (Object) null);
            String strDecodeStringElement4 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 8);
            objDecodeNullableSerializableElement2 = compositeDecoderBeginStructure.decodeNullableSerializableElement(descriptor2, 9, IntSerializer.INSTANCE, (Object) null);
            int iDecodeIntElement = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 10);
            String strDecodeStringElement5 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 11);
            String strDecodeStringElement6 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 12);
            String strDecodeStringElement7 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 13);
            objDecodeNullableSerializableElement = compositeDecoderBeginStructure.decodeNullableSerializableElement(descriptor2, 14, Browse$$serializer.INSTANCE, (Object) null);
            str7 = strDecodeStringElement2;
            str4 = strDecodeStringElement7;
            str = strDecodeStringElement4;
            i = iDecodeIntElement;
            str2 = strDecodeStringElement5;
            str3 = strDecodeStringElement6;
            z = zDecodeBooleanElement;
            str6 = strDecodeStringElement;
            str5 = strDecodeStringElement3;
            i2 = 32767;
        } else {
            String strDecodeStringElement8 = null;
            int i3 = 14;
            Object objDecodeSerializableElement5 = null;
            Object objDecodeSerializableElement6 = null;
            String strDecodeStringElement9 = null;
            String strDecodeStringElement10 = null;
            Object objDecodeNullableSerializableElement3 = null;
            Object objDecodeSerializableElement7 = null;
            Object objDecodeSerializableElement8 = null;
            Object objDecodeNullableSerializableElement4 = null;
            String strDecodeStringElement11 = null;
            String strDecodeStringElement12 = null;
            String strDecodeStringElement13 = null;
            String strDecodeStringElement14 = null;
            int i4 = 0;
            boolean zDecodeBooleanElement2 = false;
            int iDecodeIntElement2 = 0;
            boolean z4 = true;
            while (z4) {
                int iDecodeElementIndex = compositeDecoderBeginStructure.decodeElementIndex(descriptor2);
                switch (iDecodeElementIndex) {
                    case -1:
                        strDecodeStringElement10 = strDecodeStringElement10;
                        z4 = false;
                        break;
                    case 0:
                        z2 = zDecodeBooleanElement2;
                        str8 = strDecodeStringElement9;
                        str9 = strDecodeStringElement10;
                        strDecodeStringElement8 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 0);
                        i4 |= 1;
                        strDecodeStringElement9 = str8;
                        zDecodeBooleanElement2 = z2;
                        strDecodeStringElement10 = str9;
                        i3 = 14;
                        break;
                    case 1:
                        str9 = strDecodeStringElement10;
                        i4 |= 2;
                        zDecodeBooleanElement2 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 1);
                        strDecodeStringElement9 = strDecodeStringElement9;
                        strDecodeStringElement10 = str9;
                        i3 = 14;
                        break;
                    case 2:
                        z3 = zDecodeBooleanElement2;
                        strDecodeStringElement9 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 2);
                        i4 |= 4;
                        zDecodeBooleanElement2 = z3;
                        i3 = 14;
                        break;
                    case 3:
                        strDecodeStringElement10 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 3);
                        i4 |= 8;
                        i3 = 14;
                        break;
                    case 4:
                        z2 = zDecodeBooleanElement2;
                        str8 = strDecodeStringElement9;
                        str9 = strDecodeStringElement10;
                        objDecodeSerializableElement8 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 4, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), objDecodeSerializableElement8);
                        i4 |= 16;
                        strDecodeStringElement9 = str8;
                        zDecodeBooleanElement2 = z2;
                        strDecodeStringElement10 = str9;
                        i3 = 14;
                        break;
                    case 5:
                        z2 = zDecodeBooleanElement2;
                        str8 = strDecodeStringElement9;
                        str9 = strDecodeStringElement10;
                        objDecodeSerializableElement6 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 5, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), objDecodeSerializableElement6);
                        i4 |= 32;
                        strDecodeStringElement9 = str8;
                        zDecodeBooleanElement2 = z2;
                        strDecodeStringElement10 = str9;
                        i3 = 14;
                        break;
                    case 6:
                        z3 = zDecodeBooleanElement2;
                        objDecodeSerializableElement5 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 6, new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), objDecodeSerializableElement5);
                        i4 |= 64;
                        zDecodeBooleanElement2 = z3;
                        i3 = 14;
                        break;
                    case 7:
                        z2 = zDecodeBooleanElement2;
                        str8 = strDecodeStringElement9;
                        str9 = strDecodeStringElement10;
                        objDecodeSerializableElement7 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 7, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(ThemeInfo.class), ThemeInfo$$serializer.INSTANCE, new KSerializer[0])), objDecodeSerializableElement7);
                        i4 |= 128;
                        strDecodeStringElement9 = str8;
                        zDecodeBooleanElement2 = z2;
                        strDecodeStringElement10 = str9;
                        i3 = 14;
                        break;
                    case 8:
                        strDecodeStringElement11 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 8);
                        i4 |= 256;
                        i3 = 14;
                        break;
                    case 9:
                        objDecodeNullableSerializableElement4 = compositeDecoderBeginStructure.decodeNullableSerializableElement(descriptor2, 9, IntSerializer.INSTANCE, objDecodeNullableSerializableElement4);
                        i4 |= 512;
                        i3 = 14;
                        break;
                    case 10:
                        iDecodeIntElement2 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 10);
                        i4 |= 1024;
                        i3 = 14;
                        break;
                    case 11:
                        strDecodeStringElement12 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 11);
                        i4 |= 2048;
                        i3 = 14;
                        break;
                    case 12:
                        strDecodeStringElement13 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 12);
                        i4 |= 4096;
                        i3 = 14;
                        break;
                    case 13:
                        strDecodeStringElement14 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 13);
                        i4 |= 8192;
                        break;
                    case 14:
                        objDecodeNullableSerializableElement3 = compositeDecoderBeginStructure.decodeNullableSerializableElement(descriptor2, i3, Browse$$serializer.INSTANCE, objDecodeNullableSerializableElement3);
                        i4 |= 16384;
                        break;
                    default:
                        throw new UnknownFieldException(iDecodeElementIndex);
                }
            }
            boolean z5 = zDecodeBooleanElement2;
            String str10 = strDecodeStringElement9;
            objDecodeSerializableElement = objDecodeSerializableElement5;
            objDecodeSerializableElement2 = objDecodeSerializableElement6;
            objDecodeNullableSerializableElement = objDecodeNullableSerializableElement3;
            objDecodeSerializableElement3 = objDecodeSerializableElement7;
            objDecodeNullableSerializableElement2 = objDecodeNullableSerializableElement4;
            str = strDecodeStringElement11;
            str2 = strDecodeStringElement12;
            str3 = strDecodeStringElement13;
            str4 = strDecodeStringElement14;
            i = iDecodeIntElement2;
            z = z5;
            str5 = strDecodeStringElement10;
            i2 = i4;
            objDecodeSerializableElement4 = objDecodeSerializableElement8;
            str6 = strDecodeStringElement8;
            str7 = str10;
        }
        compositeDecoderBeginStructure.endStructure(descriptor2);
        return new CollectComic(i2, str6, z, str7, str5, (List) objDecodeSerializableElement4, (List) objDecodeSerializableElement2, (List) objDecodeSerializableElement, (List) objDecodeSerializableElement3, str, (Integer) objDecodeNullableSerializableElement2, i, str2, str3, str4, (Browse) objDecodeNullableSerializableElement, (SerializationConstructorMarker) null);
    }

    public void serialize(Encoder encoder, CollectComic value) {
        Intrinsics.checkNotNullParameter(encoder, "encoder");
        Intrinsics.checkNotNullParameter(value, "value");
        SerialDescriptor descriptor2 = getDescriptor();
        CompositeEncoder compositeEncoderBeginStructure = encoder.beginStructure(descriptor2);
        CollectComic.write$Self(value, compositeEncoderBeginStructure, descriptor2);
        compositeEncoderBeginStructure.endStructure(descriptor2);
    }

    public KSerializer<?>[] typeParametersSerializers() {
        return GeneratedSerializer.DefaultImpls.typeParametersSerializers(this);
    }
}
