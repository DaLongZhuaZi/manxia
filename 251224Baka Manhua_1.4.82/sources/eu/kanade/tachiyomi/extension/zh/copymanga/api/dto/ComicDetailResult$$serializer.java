package eu.kanade.tachiyomi.extension.zh.copymanga.api.dto;

import java.util.Map;
import kotlin.Deprecated;
import kotlin.DeprecationLevel;
import kotlin.Metadata;
import kotlin.ReplaceWith;
import kotlin.jvm.internal.Intrinsics;
import kotlinx.serialization.KSerializer;
import kotlinx.serialization.UnknownFieldException;
import kotlinx.serialization.descriptors.SerialDescriptor;
import kotlinx.serialization.encoding.CompositeDecoder;
import kotlinx.serialization.encoding.CompositeEncoder;
import kotlinx.serialization.encoding.Decoder;
import kotlinx.serialization.encoding.Encoder;
import kotlinx.serialization.internal.BooleanSerializer;
import kotlinx.serialization.internal.GeneratedSerializer;
import kotlinx.serialization.internal.IntSerializer;
import kotlinx.serialization.internal.LinkedHashMapSerializer;
import kotlinx.serialization.internal.PluginGeneratedSerialDescriptor;
import kotlinx.serialization.internal.SerializationConstructorMarker;
import kotlinx.serialization.internal.StringSerializer;

/* JADX INFO: compiled from: ComicDetailResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u00006\n\u0000\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010\u0011\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\bÇ\u0002\u0018\u00002\b\u0012\u0004\u0012\u00020\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0003J\u0018\u0010\b\u001a\f\u0012\b\u0012\u0006\u0012\u0002\b\u00030\n0\tHÖ\u0001¢\u0006\u0002\u0010\u000bJ\u0011\u0010\f\u001a\u00020\u00022\u0006\u0010\r\u001a\u00020\u000eHÖ\u0001J\u0019\u0010\u000f\u001a\u00020\u00102\u0006\u0010\u0011\u001a\u00020\u00122\u0006\u0010\u0013\u001a\u00020\u0002HÖ\u0001R\u0014\u0010\u0004\u001a\u00020\u00058VXÖ\u0005¢\u0006\u0006\u001a\u0004\b\u0006\u0010\u0007¨\u0006\u0014"}, d2 = {"eu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicDetailResult.$serializer", "Lkotlinx/serialization/internal/GeneratedSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicDetailResult;", "()V", "descriptor", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "getDescriptor", "()Lkotlinx/serialization/descriptors/SerialDescriptor;", "childSerializers", "", "Lkotlinx/serialization/KSerializer;", "()[Lkotlinx/serialization/KSerializer;", "deserialize", "decoder", "Lkotlinx/serialization/encoding/Decoder;", "serialize", "", "encoder", "Lkotlinx/serialization/encoding/Encoder;", "value", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
public final class ComicDetailResult$$serializer implements GeneratedSerializer<ComicDetailResult> {
    public static final ComicDetailResult$$serializer INSTANCE;
    public static final /* synthetic */ SerialDescriptor descriptor;

    public SerialDescriptor getDescriptor() {
        return descriptor;
    }

    static {
        ComicDetailResult$$serializer comicDetailResult$$serializer = new ComicDetailResult$$serializer();
        INSTANCE = comicDetailResult$$serializer;
        SerialDescriptor pluginGeneratedSerialDescriptor = new PluginGeneratedSerialDescriptor("eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ComicDetailResult", comicDetailResult$$serializer, 8);
        pluginGeneratedSerialDescriptor.addElement("is_banned", true);
        pluginGeneratedSerialDescriptor.addElement("is_lock", false);
        pluginGeneratedSerialDescriptor.addElement("is_login", false);
        pluginGeneratedSerialDescriptor.addElement("is_mobile_bind", false);
        pluginGeneratedSerialDescriptor.addElement("is_vip", false);
        pluginGeneratedSerialDescriptor.addElement("comic", false);
        pluginGeneratedSerialDescriptor.addElement("popular", false);
        pluginGeneratedSerialDescriptor.addElement("groups", false);
        descriptor = pluginGeneratedSerialDescriptor;
    }

    private ComicDetailResult$$serializer() {
    }

    public KSerializer<?>[] childSerializers() {
        return new KSerializer[]{(KSerializer) BooleanSerializer.INSTANCE, (KSerializer) BooleanSerializer.INSTANCE, (KSerializer) BooleanSerializer.INSTANCE, (KSerializer) BooleanSerializer.INSTANCE, (KSerializer) BooleanSerializer.INSTANCE, (KSerializer) ComicDetail$$serializer.INSTANCE, (KSerializer) IntSerializer.INSTANCE, (KSerializer) new LinkedHashMapSerializer(StringSerializer.INSTANCE, GroupInfo$$serializer.INSTANCE)};
    }

    /* JADX INFO: Thrown type has an unknown type hierarchy: kotlinx.serialization.UnknownFieldException */
    /* JADX INFO: renamed from: deserialize, reason: merged with bridge method [inline-methods] */
    public ComicDetailResult m22deserialize(Decoder decoder) throws UnknownFieldException {
        boolean zDecodeBooleanElement;
        boolean zDecodeBooleanElement2;
        Object objDecodeSerializableElement;
        Object objDecodeSerializableElement2;
        int i;
        boolean z;
        boolean z2;
        int i2;
        boolean z3;
        Intrinsics.checkNotNullParameter(decoder, "decoder");
        SerialDescriptor descriptor2 = getDescriptor();
        CompositeDecoder compositeDecoderBeginStructure = decoder.beginStructure(descriptor2);
        int i3 = 0;
        if (compositeDecoderBeginStructure.decodeSequentially()) {
            boolean zDecodeBooleanElement3 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 0);
            boolean zDecodeBooleanElement4 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 1);
            boolean zDecodeBooleanElement5 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 2);
            boolean zDecodeBooleanElement6 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 3);
            boolean zDecodeBooleanElement7 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 4);
            objDecodeSerializableElement2 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 5, ComicDetail$$serializer.INSTANCE, (Object) null);
            int iDecodeIntElement = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 6);
            objDecodeSerializableElement = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 7, new LinkedHashMapSerializer(StringSerializer.INSTANCE, GroupInfo$$serializer.INSTANCE), (Object) null);
            i2 = iDecodeIntElement;
            zDecodeBooleanElement = zDecodeBooleanElement6;
            zDecodeBooleanElement2 = zDecodeBooleanElement7;
            z3 = zDecodeBooleanElement5;
            z = zDecodeBooleanElement4;
            i = 255;
            z2 = zDecodeBooleanElement3;
        } else {
            Object objDecodeSerializableElement3 = null;
            Object objDecodeSerializableElement4 = null;
            boolean zDecodeBooleanElement8 = false;
            int iDecodeIntElement2 = 0;
            zDecodeBooleanElement = false;
            zDecodeBooleanElement2 = false;
            boolean zDecodeBooleanElement9 = false;
            boolean zDecodeBooleanElement10 = false;
            boolean z4 = true;
            while (z4) {
                int iDecodeElementIndex = compositeDecoderBeginStructure.decodeElementIndex(descriptor2);
                switch (iDecodeElementIndex) {
                    case -1:
                        z4 = false;
                        break;
                    case 0:
                        i3 |= 1;
                        zDecodeBooleanElement8 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 0);
                        break;
                    case 1:
                        i3 |= 2;
                        zDecodeBooleanElement10 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 1);
                        break;
                    case 2:
                        i3 |= 4;
                        zDecodeBooleanElement9 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 2);
                        break;
                    case 3:
                        zDecodeBooleanElement = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 3);
                        i3 |= 8;
                        break;
                    case 4:
                        zDecodeBooleanElement2 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 4);
                        i3 |= 16;
                        break;
                    case 5:
                        objDecodeSerializableElement4 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 5, ComicDetail$$serializer.INSTANCE, objDecodeSerializableElement4);
                        i3 |= 32;
                        break;
                    case 6:
                        iDecodeIntElement2 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 6);
                        i3 |= 64;
                        break;
                    case 7:
                        objDecodeSerializableElement3 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 7, new LinkedHashMapSerializer(StringSerializer.INSTANCE, GroupInfo$$serializer.INSTANCE), objDecodeSerializableElement3);
                        i3 |= 128;
                        break;
                    default:
                        throw new UnknownFieldException(iDecodeElementIndex);
                }
            }
            objDecodeSerializableElement = objDecodeSerializableElement3;
            objDecodeSerializableElement2 = objDecodeSerializableElement4;
            i = i3;
            z = zDecodeBooleanElement10;
            z2 = zDecodeBooleanElement8;
            i2 = iDecodeIntElement2;
            z3 = zDecodeBooleanElement9;
        }
        compositeDecoderBeginStructure.endStructure(descriptor2);
        return new ComicDetailResult(i, z2, z, z3, zDecodeBooleanElement, zDecodeBooleanElement2, (ComicDetail) objDecodeSerializableElement2, i2, (Map) objDecodeSerializableElement, (SerializationConstructorMarker) null);
    }

    public void serialize(Encoder encoder, ComicDetailResult value) {
        Intrinsics.checkNotNullParameter(encoder, "encoder");
        Intrinsics.checkNotNullParameter(value, "value");
        SerialDescriptor descriptor2 = getDescriptor();
        CompositeEncoder compositeEncoderBeginStructure = encoder.beginStructure(descriptor2);
        ComicDetailResult.write$Self(value, compositeEncoderBeginStructure, descriptor2);
        compositeEncoderBeginStructure.endStructure(descriptor2);
    }

    public KSerializer<?>[] typeParametersSerializers() {
        return GeneratedSerializer.DefaultImpls.typeParametersSerializers(this);
    }
}
