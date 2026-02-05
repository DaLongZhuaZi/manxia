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
import kotlinx.serialization.internal.GeneratedSerializer;
import kotlinx.serialization.internal.IntSerializer;
import kotlinx.serialization.internal.PluginGeneratedSerialDescriptor;

/* compiled from: RankResult.kt */
@Metadata(d1 = {"\u00006\n\u0000\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010\u0011\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\bÇ\u0002\u0018\u00002\b\u0012\u0004\u0012\u00020\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0003J\u0018\u0010\b\u001a\f\u0012\b\u0012\u0006\u0012\u0002\b\u00030\n0\tHÖ\u0001¢\u0006\u0002\u0010\u000bJ\u0011\u0010\f\u001a\u00020\u00022\u0006\u0010\r\u001a\u00020\u000eHÖ\u0001J\u0019\u0010\u000f\u001a\u00020\u00102\u0006\u0010\u0011\u001a\u00020\u00122\u0006\u0010\u0013\u001a\u00020\u0002HÖ\u0001R\u0014\u0010\u0004\u001a\u00020\u00058VXÖ\u0005¢\u0006\u0006\u001a\u0004\b\u0006\u0010\u0007¨\u0006\u0014"}, d2 = {"eu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ListItem.$serializer", "Lkotlinx/serialization/internal/GeneratedSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ListItem;", "()V", "descriptor", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "getDescriptor", "()Lkotlinx/serialization/descriptors/SerialDescriptor;", "childSerializers", "", "Lkotlinx/serialization/KSerializer;", "()[Lkotlinx/serialization/KSerializer;", "deserialize", "decoder", "Lkotlinx/serialization/encoding/Decoder;", "serialize", "", "encoder", "Lkotlinx/serialization/encoding/Encoder;", "value", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
/* loaded from: classes.dex */
public final class ListItem$$serializer implements GeneratedSerializer<ListItem> {
    public static final ListItem$$serializer INSTANCE;
    public static final /* synthetic */ SerialDescriptor descriptor;

    public SerialDescriptor getDescriptor() {
        return descriptor;
    }

    static {
        ListItem$$serializer listItem$$serializer = new ListItem$$serializer();
        INSTANCE = listItem$$serializer;
        SerialDescriptor pluginGeneratedSerialDescriptor = new PluginGeneratedSerialDescriptor("eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ListItem", listItem$$serializer, 7);
        pluginGeneratedSerialDescriptor.addElement("sort", false);
        pluginGeneratedSerialDescriptor.addElement("sort_last", false);
        pluginGeneratedSerialDescriptor.addElement("rise_sort", false);
        pluginGeneratedSerialDescriptor.addElement("rise_num", false);
        pluginGeneratedSerialDescriptor.addElement("date_type", false);
        pluginGeneratedSerialDescriptor.addElement("popular", false);
        pluginGeneratedSerialDescriptor.addElement("comic", false);
        descriptor = pluginGeneratedSerialDescriptor;
    }

    private ListItem$$serializer() {
    }

    public KSerializer<?>[] childSerializers() {
        return new KSerializer[]{(KSerializer) IntSerializer.INSTANCE, (KSerializer) IntSerializer.INSTANCE, (KSerializer) IntSerializer.INSTANCE, (KSerializer) IntSerializer.INSTANCE, (KSerializer) IntSerializer.INSTANCE, (KSerializer) IntSerializer.INSTANCE, (KSerializer) ComicInfo$$serializer.INSTANCE};
    }

    /* JADX INFO: Thrown type has an unknown type hierarchy: kotlinx.serialization.UnknownFieldException */
    /* renamed from: deserialize, reason: merged with bridge method [inline-methods] */
    public ListItem m32deserialize(Decoder decoder) throws UnknownFieldException {
        int iDecodeIntElement;
        Object objDecodeSerializableElement;
        int i;
        int i2;
        int i3;
        int i4;
        int i5;
        int i6;
        Intrinsics.checkNotNullParameter(decoder, "decoder");
        SerialDescriptor descriptor2 = getDescriptor();
        CompositeDecoder compositeDecoderBeginStructure = decoder.beginStructure(descriptor2);
        if (compositeDecoderBeginStructure.decodeSequentially()) {
            int iDecodeIntElement2 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 0);
            int iDecodeIntElement3 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 1);
            int iDecodeIntElement4 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 2);
            int iDecodeIntElement5 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 3);
            int iDecodeIntElement6 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 4);
            int iDecodeIntElement7 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 5);
            objDecodeSerializableElement = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 6, ComicInfo$$serializer.INSTANCE, (Object) null);
            i6 = iDecodeIntElement2;
            i = iDecodeIntElement7;
            i5 = iDecodeIntElement5;
            i3 = iDecodeIntElement6;
            iDecodeIntElement = iDecodeIntElement4;
            i4 = iDecodeIntElement3;
            i2 = 127;
        } else {
            Object objDecodeSerializableElement2 = null;
            int iDecodeIntElement8 = 0;
            int iDecodeIntElement9 = 0;
            int iDecodeIntElement10 = 0;
            int iDecodeIntElement11 = 0;
            iDecodeIntElement = 0;
            int iDecodeIntElement12 = 0;
            int i7 = 0;
            boolean z = true;
            while (z) {
                int iDecodeElementIndex = compositeDecoderBeginStructure.decodeElementIndex(descriptor2);
                switch (iDecodeElementIndex) {
                    case -1:
                        z = false;
                        break;
                    case 0:
                        i7 |= 1;
                        iDecodeIntElement8 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 0);
                        continue;
                    case 1:
                        iDecodeIntElement12 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 1);
                        i7 |= 2;
                        continue;
                    case 2:
                        iDecodeIntElement = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 2);
                        i7 |= 4;
                        break;
                    case 3:
                        iDecodeIntElement10 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 3);
                        i7 |= 8;
                        break;
                    case 4:
                        iDecodeIntElement11 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 4);
                        i7 |= 16;
                        break;
                    case 5:
                        iDecodeIntElement9 = compositeDecoderBeginStructure.decodeIntElement(descriptor2, 5);
                        i7 |= 32;
                        break;
                    case 6:
                        objDecodeSerializableElement2 = compositeDecoderBeginStructure.decodeSerializableElement(descriptor2, 6, ComicInfo$$serializer.INSTANCE, objDecodeSerializableElement2);
                        i7 |= 64;
                        break;
                    default:
                        throw new UnknownFieldException(iDecodeElementIndex);
                }
            }
            objDecodeSerializableElement = objDecodeSerializableElement2;
            i = iDecodeIntElement9;
            i2 = i7;
            i3 = iDecodeIntElement11;
            i4 = iDecodeIntElement12;
            i5 = iDecodeIntElement10;
            i6 = iDecodeIntElement8;
        }
        compositeDecoderBeginStructure.endStructure(descriptor2);
        return new ListItem(i2, i6, i4, iDecodeIntElement, i5, i3, i, (ComicInfo) objDecodeSerializableElement, null);
    }

    public void serialize(Encoder encoder, ListItem value) {
        Intrinsics.checkNotNullParameter(encoder, "encoder");
        Intrinsics.checkNotNullParameter(value, "value");
        SerialDescriptor descriptor2 = getDescriptor();
        CompositeEncoder compositeEncoderBeginStructure = encoder.beginStructure(descriptor2);
        ListItem.write$Self(value, compositeEncoderBeginStructure, descriptor2);
        compositeEncoderBeginStructure.endStructure(descriptor2);
    }

    public KSerializer<?>[] typeParametersSerializers() {
        return GeneratedSerializer.DefaultImpls.typeParametersSerializers(this);
    }
}
