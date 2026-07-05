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
import kotlinx.serialization.descriptors.SerialDescriptor;
import kotlinx.serialization.encoding.CompositeDecoder;
import kotlinx.serialization.encoding.CompositeEncoder;
import kotlinx.serialization.encoding.Decoder;
import kotlinx.serialization.encoding.Encoder;
import kotlinx.serialization.internal.ArrayListSerializer;
import kotlinx.serialization.internal.GeneratedSerializer;
import kotlinx.serialization.internal.IntSerializer;
import kotlinx.serialization.internal.PluginGeneratedSerialDescriptor;
import kotlinx.serialization.internal.SerializationConstructorMarker;
import kotlinx.serialization.internal.StringSerializer;
import kotlinx.serialization.json.JsonElement;
import kotlinx.serialization.json.JsonElementSerializer;

/* JADX INFO: compiled from: RecommendResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u00006\n\u0000\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010\u0011\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\bÇ\u0002\u0018\u00002\b\u0012\u0004\u0012\u00020\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0003J\u0018\u0010\b\u001a\f\u0012\b\u0012\u0006\u0012\u0002\b\u00030\n0\tHÖ\u0001¢\u0006\u0002\u0010\u000bJ\u0011\u0010\f\u001a\u00020\u00022\u0006\u0010\r\u001a\u00020\u000eHÖ\u0001J\u0019\u0010\u000f\u001a\u00020\u00102\u0006\u0010\u0011\u001a\u00020\u00122\u0006\u0010\u0013\u001a\u00020\u0002HÖ\u0001R\u0014\u0010\u0004\u001a\u00020\u00058VXÖ\u0005¢\u0006\u0006\u001a\u0004\b\u0006\u0010\u0007¨\u0006\u0014"}, d2 = {"eu/kanade/tachiyomi/extension/zh/copymanga/api/dto/RecommendComic.$serializer", "Lkotlinx/serialization/internal/GeneratedSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/RecommendComic;", "()V", "descriptor", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "getDescriptor", "()Lkotlinx/serialization/descriptors/SerialDescriptor;", "childSerializers", "", "Lkotlinx/serialization/KSerializer;", "()[Lkotlinx/serialization/KSerializer;", "deserialize", "decoder", "Lkotlinx/serialization/encoding/Decoder;", "serialize", "", "encoder", "Lkotlinx/serialization/encoding/Encoder;", "value", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
public final class RecommendComic$$serializer implements GeneratedSerializer<RecommendComic> {
    public static final RecommendComic$$serializer INSTANCE;
    public static final /* synthetic */ SerialDescriptor descriptor;

    public SerialDescriptor getDescriptor() {
        return descriptor;
    }

    static {
        RecommendComic$$serializer recommendComic$$serializer = new RecommendComic$$serializer();
        INSTANCE = recommendComic$$serializer;
        SerialDescriptor pluginGeneratedSerialDescriptor = new PluginGeneratedSerialDescriptor("eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.RecommendComic", recommendComic$$serializer, 8);
        pluginGeneratedSerialDescriptor.addElement("name", false);
        pluginGeneratedSerialDescriptor.addElement("females", true);
        pluginGeneratedSerialDescriptor.addElement("males", true);
        pluginGeneratedSerialDescriptor.addElement("theme", true);
        pluginGeneratedSerialDescriptor.addElement("path_word", false);
        pluginGeneratedSerialDescriptor.addElement("author", false);
        pluginGeneratedSerialDescriptor.addElement("cover", false);
        pluginGeneratedSerialDescriptor.addElement("popular", false);
        descriptor = pluginGeneratedSerialDescriptor;
    }

    private RecommendComic$$serializer() {
    }

    public KSerializer<?>[] childSerializers() {
        return new KSerializer[]{(KSerializer) StringSerializer.INSTANCE, (KSerializer) new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (KSerializer) new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (KSerializer) new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(ThemeInfo.class), ThemeInfo$$serializer.INSTANCE, new KSerializer[0])), (KSerializer) StringSerializer.INSTANCE, (KSerializer) new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), (KSerializer) StringSerializer.INSTANCE, (KSerializer) IntSerializer.INSTANCE};
    }

    /* JADX INFO: Thrown type has an unknown type hierarchy: kotlinx.serialization.UnknownFieldException */
    /* JADX INFO: renamed from: deserialize, reason: merged with bridge method [inline-methods] */
    public RecommendComic m41deserialize(Decoder decoder) throws UnknownFieldException {
        String strDecodeStringElement;
        int iDecodeIntElement;
        int i;
        Object objDecodeSerializableElement;
        Object objDecodeSerializableElement2;
        Object objDecodeSerializableElement3;
        Object objDecodeSerializableElement4;
        String str;
        Intrinsics.checkNotNullParameter(decoder, "decoder");
        SerialDescriptor descriptor2 = getDescriptor();
        CompositeDecoder compositeDecoderBeginStructure = decoder.beginStructure(descriptor2);
        int i2 = 6;
        int i3 = 5;
        int i4 = 4;
        String strDecodeStringElement2 = null;
        if (compositeDecoderBeginStructure.decodeSequentially()) {
            String strDecodeStringElement3 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 0);
            objDecodeSerializableElement2 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 1, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (Object) null);
            objDecodeSerializableElement3 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 2, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), (Object) null);
            objDecodeSerializableElement4 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 3, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(ThemeInfo.class), ThemeInfo$$serializer.INSTANCE, new KSerializer[0])), (Object) null);
            String strDecodeStringElement4 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 4);
            objDecodeSerializableElement = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 5, new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), (Object) null);
            i = 255;
            strDecodeStringElement2 = strDecodeStringElement3;
            strDecodeStringElement = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 6);
            str = strDecodeStringElement4;
            iDecodeIntElement = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 7);
        } else {
            int i5 = 7;
            Object objDecodeSerializableElement5 = null;
            Object objDecodeSerializableElement6 = null;
            Object objDecodeSerializableElement7 = null;
            Object objDecodeSerializableElement8 = null;
            String strDecodeStringElement5 = null;
            strDecodeStringElement = null;
            int iDecodeIntElement2 = 0;
            int i6 = 0;
            boolean z = true;
            while (z) {
                int iDecodeElementIndex = compositeDecoderBeginStructure.decodeElementIndex(descriptor2);
                switch (iDecodeElementIndex) {
                    case -1:
                        z = false;
                        break;
                    case 0:
                        strDecodeStringElement2 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, 0);
                        i6 |= 1;
                        i2 = 6;
                        i3 = 5;
                        i4 = 4;
                        i5 = 7;
                        break;
                    case 1:
                        objDecodeSerializableElement6 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 1, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), objDecodeSerializableElement6);
                        i6 |= 2;
                        i2 = 6;
                        i3 = 5;
                        i4 = 4;
                        i5 = 7;
                        break;
                    case 2:
                        objDecodeSerializableElement7 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 2, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), objDecodeSerializableElement7);
                        i6 |= 4;
                        i2 = 6;
                        i3 = 5;
                        i4 = 4;
                        i5 = 7;
                        break;
                    case 3:
                        objDecodeSerializableElement8 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 3, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(ThemeInfo.class), ThemeInfo$$serializer.INSTANCE, new KSerializer[0])), objDecodeSerializableElement8);
                        i6 |= 8;
                        i2 = 6;
                        i3 = 5;
                        i4 = 4;
                        i5 = 7;
                        break;
                    case 4:
                        strDecodeStringElement5 = compositeDecoderBeginStructure.decodeStringElement(descriptor2, i4);
                        i6 |= 16;
                        i2 = 6;
                        break;
                    case 5:
                        objDecodeSerializableElement5 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, i3, new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), objDecodeSerializableElement5);
                        i6 |= 32;
                        i2 = 6;
                        break;
                    case 6:
                        strDecodeStringElement = compositeDecoderBeginStructure.decodeStringElement(descriptor2, i2);
                        i6 |= 64;
                        break;
                    case 7:
                        iDecodeIntElement2 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, i5);
                        i6 |= 128;
                        break;
                    default:
                        throw new UnknownFieldException(iDecodeElementIndex);
                }
            }
            iDecodeIntElement = iDecodeIntElement2;
            i = i6;
            objDecodeSerializableElement = objDecodeSerializableElement5;
            objDecodeSerializableElement2 = objDecodeSerializableElement6;
            objDecodeSerializableElement3 = objDecodeSerializableElement7;
            objDecodeSerializableElement4 = objDecodeSerializableElement8;
            str = strDecodeStringElement5;
        }
        compositeDecoderBeginStructure.endStructure(descriptor2);
        return new RecommendComic(i, strDecodeStringElement2, (List) objDecodeSerializableElement2, (List) objDecodeSerializableElement3, (List) objDecodeSerializableElement4, str, (List) objDecodeSerializableElement, strDecodeStringElement, iDecodeIntElement, (SerializationConstructorMarker) null);
    }

    public void serialize(Encoder encoder, RecommendComic value) {
        Intrinsics.checkNotNullParameter(encoder, "encoder");
        Intrinsics.checkNotNullParameter(value, "value");
        SerialDescriptor descriptor2 = getDescriptor();
        CompositeEncoder compositeEncoderBeginStructure = encoder.beginStructure(descriptor2);
        RecommendComic.write$Self(value, compositeEncoderBeginStructure, descriptor2);
        compositeEncoderBeginStructure.endStructure(descriptor2);
    }

    public KSerializer<?>[] typeParametersSerializers() {
        return GeneratedSerializer.DefaultImpls.typeParametersSerializers(this);
    }
}
