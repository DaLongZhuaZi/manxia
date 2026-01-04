package eu.kanade.tachiyomi.lib.cryptoaes;

import android.util.Base64;
import java.security.InvalidAlgorithmParameterException;
import java.security.InvalidKeyException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import javax.crypto.BadPaddingException;
import javax.crypto.Cipher;
import javax.crypto.IllegalBlockSizeException;
import javax.crypto.NoSuchPaddingException;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import kotlin.Metadata;
import kotlin.collections.ArraysKt;
import kotlin.jvm.internal.Intrinsics;
import kotlin.text.Charsets;

/* compiled from: CryptoAES.kt */
@Metadata(d1 = {"\u00004\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\u0005\n\u0002\u0010\u0012\n\u0002\b\u0005\n\u0002\u0010\u0011\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0002\b\u0002\bÆ\u0002\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u001e\u0010\n\u001a\u00020\u00042\u0006\u0010\u000b\u001a\u00020\u00042\u0006\u0010\f\u001a\u00020\r2\u0006\u0010\u000e\u001a\u00020\rJ\u0016\u0010\n\u001a\u00020\u00042\u0006\u0010\u000b\u001a\u00020\u00042\u0006\u0010\u000f\u001a\u00020\u0004J \u0010\u0010\u001a\u00020\u00042\u0006\u0010\u0011\u001a\u00020\r2\u0006\u0010\f\u001a\u00020\r2\u0006\u0010\u000e\u001a\u00020\rH\u0002JG\u0010\u0012\u001a\f\u0012\u0006\u0012\u0004\u0018\u00010\r\u0018\u00010\u00132\u0006\u0010\u0014\u001a\u00020\u00072\u0006\u0010\u0015\u001a\u00020\u00072\u0006\u0010\u0016\u001a\u00020\u00072\u0006\u0010\u0017\u001a\u00020\r2\u0006\u0010\u000f\u001a\u00020\r2\u0006\u0010\u0018\u001a\u00020\u0019H\u0002¢\u0006\u0002\u0010\u001aR\u000e\u0010\u0003\u001a\u00020\u0004X\u0082T¢\u0006\u0002\n\u0000R\u000e\u0010\u0005\u001a\u00020\u0004X\u0082T¢\u0006\u0002\n\u0000R\u000e\u0010\u0006\u001a\u00020\u0007X\u0082T¢\u0006\u0002\n\u0000R\u000e\u0010\b\u001a\u00020\u0004X\u0082T¢\u0006\u0002\n\u0000R\u000e\u0010\t\u001a\u00020\u0007X\u0082T¢\u0006\u0002\n\u0000¨\u0006\u001b"}, d2 = {"Leu/kanade/tachiyomi/lib/cryptoaes/CryptoAES;", "", "()V", CryptoAES.AES, "", "HASH_CIPHER", "IV_SIZE", "", "KDF_DIGEST", "KEY_SIZE", "decrypt", "cipherText", "keyBytes", "", "ivBytes", "password", "decryptAES", "cipherTextBytes", "generateKeyAndIV", "", "keyLength", "ivLength", "iterations", "salt", "md", "Ljava/security/MessageDigest;", "(III[B[BLjava/security/MessageDigest;)[[B", "cryptoaes_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class CryptoAES {
    private static final String AES = "AES";
    private static final String HASH_CIPHER = "AES/CBC/PKCS7PADDING";
    public static final CryptoAES INSTANCE = new CryptoAES();
    private static final int IV_SIZE = 128;
    private static final String KDF_DIGEST = "MD5";
    private static final int KEY_SIZE = 256;

    private CryptoAES() {
    }

    public final String decrypt(String cipherText, String password) {
        byte[] saltBytes;
        byte[] cipherTextBytes;
        MessageDigest md5;
        byte[] bytes;
        byte[] bArr;
        byte[] bArr2;
        Intrinsics.checkNotNullParameter(cipherText, "cipherText");
        Intrinsics.checkNotNullParameter(password, "password");
        try {
            byte[] ctBytes = Base64.decode(cipherText, 0);
            saltBytes = Arrays.copyOfRange(ctBytes, 8, 16);
            cipherTextBytes = Arrays.copyOfRange(ctBytes, 16, ctBytes.length);
            md5 = MessageDigest.getInstance(KDF_DIGEST);
            Intrinsics.checkNotNullExpressionValue(md5, "getInstance(\"MD5\")");
            Intrinsics.checkNotNullExpressionValue(saltBytes, "saltBytes");
            bytes = password.getBytes(Charsets.UTF_8);
            Intrinsics.checkNotNullExpressionValue(bytes, "this as java.lang.String).getBytes(charset)");
        } catch (Exception e) {
        }
        try {
            byte[][] keyAndIV = generateKeyAndIV(32, 16, 1, saltBytes, bytes, md5);
            Intrinsics.checkNotNullExpressionValue(cipherTextBytes, "cipherTextBytes");
            if (keyAndIV == null || (bArr = keyAndIV[0]) == null) {
                bArr = new byte[32];
            }
            if (keyAndIV == null || (bArr2 = keyAndIV[1]) == null) {
                bArr2 = new byte[16];
            }
            return decryptAES(cipherTextBytes, bArr, bArr2);
        } catch (Exception e2) {
            return "";
        }
    }

    public final String decrypt(String cipherText, byte[] keyBytes, byte[] ivBytes) {
        Intrinsics.checkNotNullParameter(cipherText, "cipherText");
        Intrinsics.checkNotNullParameter(keyBytes, "keyBytes");
        Intrinsics.checkNotNullParameter(ivBytes, "ivBytes");
        try {
            byte[] cipherTextBytes = Base64.decode(cipherText, 0);
            Intrinsics.checkNotNullExpressionValue(cipherTextBytes, "cipherTextBytes");
            return decryptAES(cipherTextBytes, keyBytes, ivBytes);
        } catch (Exception e) {
            return "";
        }
    }

    private final String decryptAES(byte[] cipherTextBytes, byte[] keyBytes, byte[] ivBytes) throws BadPaddingException, NoSuchPaddingException, IllegalBlockSizeException, NoSuchAlgorithmException, InvalidKeyException, InvalidAlgorithmParameterException {
        try {
            Cipher cipher = Cipher.getInstance(HASH_CIPHER);
            SecretKeySpec keyS = new SecretKeySpec(keyBytes, AES);
            cipher.init(2, keyS, new IvParameterSpec(ivBytes));
            byte[] bArrDoFinal = cipher.doFinal(cipherTextBytes);
            Intrinsics.checkNotNullExpressionValue(bArrDoFinal, "cipher.doFinal(cipherTextBytes)");
            return new String(bArrDoFinal, Charsets.UTF_8);
        } catch (Exception e) {
            return "";
        }
    }

    private final byte[][] generateKeyAndIV(int keyLength, int ivLength, int iterations, byte[] salt, byte[] password, MessageDigest md) {
        int digestLength = md.getDigestLength();
        int requiredLength = ((((keyLength + ivLength) + digestLength) - 1) / digestLength) * digestLength;
        byte[] generatedData = new byte[requiredLength];
        try {
            try {
                md.reset();
                for (int generatedLength = 0; generatedLength < keyLength + ivLength; generatedLength += digestLength) {
                    if (generatedLength > 0) {
                        md.update(generatedData, generatedLength - digestLength, digestLength);
                    }
                    md.update(password);
                    md.update(salt, 0, 8);
                    md.digest(generatedData, generatedLength, digestLength);
                    for (int i = 1; i < iterations; i++) {
                        md.update(generatedData, generatedLength, digestLength);
                        md.digest(generatedData, generatedLength, digestLength);
                    }
                }
                byte[][] result = new byte[2][];
                result[0] = ArraysKt.copyOfRange(generatedData, 0, keyLength);
                if (ivLength > 0) {
                    result[1] = ArraysKt.copyOfRange(generatedData, keyLength, keyLength + ivLength);
                }
                return result;
            } catch (Exception e) {
                throw e;
            }
        } finally {
            Arrays.fill(generatedData, (byte) 0);
        }
    }
}
