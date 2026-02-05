package eu.kanade.tachiyomi.extension.zh.copymanga.api.dto;

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
import kotlinx.serialization.internal.PluginGeneratedSerialDescriptor;
import kotlinx.serialization.internal.SerializationConstructorMarker;

/* compiled from: ContentResult.kt */
@Metadata(d1 = {"\u00006\n\u0000\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010\u0011\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\bÇ\u0002\u0018\u00002\b\u0012\u0004\u0012\u00020\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0003J\u0018\u0010\b\u001a\f\u0012\b\u0012\u0006\u0012\u0002\b\u00030\n0\tHÖ\u0001¢\u0006\u0002\u0010\u000bJ\u0011\u0010\f\u001a\u00020\u00022\u0006\u0010\r\u001a\u00020\u000eHÖ\u0001J\u0019\u0010\u000f\u001a\u00020\u00102\u0006\u0010\u0011\u001a\u00020\u00122\u0006\u0010\u0013\u001a\u00020\u0002HÖ\u0001R\u0014\u0010\u0004\u001a\u00020\u00058VXÖ\u0005¢\u0006\u0006\u001a\u0004\b\u0006\u0010\u0007¨\u0006\u0014"}, d2 = {"eu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ContentResult.$serializer", "Lkotlinx/serialization/internal/GeneratedSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ContentResult;", "()V", "descriptor", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "getDescriptor", "()Lkotlinx/serialization/descriptors/SerialDescriptor;", "childSerializers", "", "Lkotlinx/serialization/KSerializer;", "()[Lkotlinx/serialization/KSerializer;", "deserialize", "decoder", "Lkotlinx/serialization/encoding/Decoder;", "serialize", "", "encoder", "Lkotlinx/serialization/encoding/Encoder;", "value", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
/* loaded from: classes.dex */
public final class ContentResult$$serializer implements GeneratedSerializer<ContentResult> {
    public static final ContentResult$$serializer INSTANCE;
    public static final /* synthetic */ SerialDescriptor descriptor;

    public SerialDescriptor getDescriptor() {
        return descriptor;
    }

    static {
        ContentResult$$serializer contentResult$$serializer = new ContentResult$$serializer();
        INSTANCE = contentResult$$serializer;
        SerialDescriptor pluginGeneratedSerialDescriptor = new PluginGeneratedSerialDescriptor("eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ContentResult", contentResult$$serializer, 8);
        pluginGeneratedSerialDescriptor.addElement("show_app", true);
        pluginGeneratedSerialDescriptor.addElement("is_lock", false);
        pluginGeneratedSerialDescriptor.addElement("is_login", false);
        pluginGeneratedSerialDescriptor.addElement("is_mobile_bind", false);
        pluginGeneratedSerialDescriptor.addElement("is_vip", false);
        pluginGeneratedSerialDescriptor.addElement("is_banned", true);
        pluginGeneratedSerialDescriptor.addElement("comic", false);
        pluginGeneratedSerialDescriptor.addElement("chapter", false);
        descriptor = pluginGeneratedSerialDescriptor;
    }

    private ContentResult$$serializer() {
    }

    public KSerializer<?>[] childSerializers() {
        return new KSerializer[]{(KSerializer) BooleanSerializer.INSTANCE, (KSerializer) BooleanSerializer.INSTANCE, (KSerializer) BooleanSerializer.INSTANCE, (KSerializer) BooleanSerializer.INSTANCE, (KSerializer) BooleanSerializer.INSTANCE, (KSerializer) BooleanSerializer.INSTANCE, (KSerializer) ComicSummaryFace$$serializer.INSTANCE, (KSerializer) ChapterDetail$$serializer.INSTANCE};
    }

    /* JADX INFO: Thrown type has an unknown type hierarchy: kotlinx.serialization.UnknownFieldException */
    /* renamed from: deserialize, reason: merged with bridge method [inline-methods] */
    public ContentResult m27deserialize(Decoder decoder) throws UnknownFieldException {
        boolean zDecodeBooleanElement;
        boolean zDecodeBooleanElement2;
        Object objDecodeSerializableElement;
        Object objDecodeSerializableElement2;
        int i;
        boolean z;
        boolean z2;
        boolean z3;
        boolean z4;
        Intrinsics.checkNotNullParameter(decoder, "decoder");
        SerialDescriptor descriptor2 = getDescriptor();
        CompositeDecoder compositeDecoderBeginStructure = decoder.beginStructure(descriptor2);
        int i2 = 0;
        if (compositeDecoderBeginStructure.decodeSequentially()) {
            boolean zDecodeBooleanElement3 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 0);
            boolean zDecodeBooleanElement4 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 1);
            boolean zDecodeBooleanElement5 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 2);
            boolean zDecodeBooleanElement6 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 3);
            boolean zDecodeBooleanElement7 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 4);
            boolean zDecodeBooleanElement8 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 5);
            objDecodeSerializableElement2 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 6, ComicSummaryFace$$serializer.INSTANCE, (Object) null);
            objDecodeSerializableElement = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 7, ChapterDetail$$serializer.INSTANCE, (Object) null);
            z3 = zDecodeBooleanElement8;
            zDecodeBooleanElement = zDecodeBooleanElement6;
            zDecodeBooleanElement2 = zDecodeBooleanElement7;
            z4 = zDecodeBooleanElement5;
            z = zDecodeBooleanElement4;
            i = 255;
            z2 = zDecodeBooleanElement3;
        } else {
            Object objDecodeSerializableElement3 = null;
            Object objDecodeSerializableElement4 = null;
            boolean zDecodeBooleanElement9 = false;
            boolean zDecodeBooleanElement10 = false;
            zDecodeBooleanElement = false;
            zDecodeBooleanElement2 = false;
            boolean zDecodeBooleanElement11 = false;
            boolean zDecodeBooleanElement12 = false;
            boolean z5 = true;
            while (z5) {
                int iDecodeElementIndex = compositeDecoderBeginStructure.decodeElementIndex(descriptor2);
                switch (iDecodeElementIndex) {
                    case -1:
                        z5 = false;
                        break;
                    case 0:
                        i2 |= 1;
                        zDecodeBooleanElement9 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 0);
                        continue;
                    case 1:
                        i2 |= 2;
                        zDecodeBooleanElement12 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 1);
                        continue;
                    case 2:
                        i2 |= 4;
                        zDecodeBooleanElement11 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 2);
                        continue;
                    case 3:
                        zDecodeBooleanElement = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 3);
                        i2 |= 8;
                        continue;
                    case 4:
                        zDecodeBooleanElement2 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 4);
                        i2 |= 16;
                        break;
                    case 5:
                        zDecodeBooleanElement10 = compositeDecoderBeginStructure.decodeBooleanElement(descriptor2, 5);
                        i2 |= 32;
                        break;
                    case 6:
                        objDecodeSerializableElement4 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 6, ComicSummaryFace$$serializer.INSTANCE, objDecodeSerializableElement4);
                        i2 |= 64;
                        break;
                    case 7:
                        objDecodeSerializableElement3 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 7, ChapterDetail$$serializer.INSTANCE, objDecodeSerializableElement3);
                        i2 |= 128;
                        break;
                    default:
                        throw new UnknownFieldException(iDecodeElementIndex);
                }
            }
            objDecodeSerializableElement = objDecodeSerializableElement3;
            objDecodeSerializableElement2 = objDecodeSerializableElement4;
            i = i2;
            z = zDecodeBooleanElement12;
            z2 = zDecodeBooleanElement9;
            boolean z6 = zDecodeBooleanElement11;
            z3 = zDecodeBooleanElement10;
            z4 = z6;
        }
        compositeDecoderBeginStructure.endStructure(descriptor2);
        return new ContentResult(i, z2, z, z4, zDecodeBooleanElement, zDecodeBooleanElement2, z3, (ComicSummaryFace) objDecodeSerializableElement2, (ChapterDetail) objDecodeSerializableElement, (SerializationConstructorMarker) null);
    }

    public void serialize(Encoder encoder, ContentResult value) {
        Intrinsics.checkNotNullParameter(encoder, "encoder");
        Intrinsics.checkNotNullParameter(value, "value");
        SerialDescriptor descriptor2 = getDescriptor();
        CompositeEncoder compositeEncoderBeginStructure = encoder.beginStructure(descriptor2);
        ContentResult.write$Self(value, compositeEncoderBeginStructure, descriptor2);
        compositeEncoderBeginStructure.endStructure(descriptor2);
    }

    public KSerializer<?>[] typeParametersSerializers() {
        return GeneratedSerializer.DefaultImpls.typeParametersSerializers(this);
    }
}
