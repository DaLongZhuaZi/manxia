package eu.kanade.tachiyomi.lib.chineseutils;

import eu.kanade.tachiyomi.lib.chineseutils.pinyin.Pinyin;
import eu.kanade.tachiyomi.lib.chineseutils.pinyin.PinyinFormat;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;

/* JADX INFO: loaded from: classes.dex */
public class ChineseUtils {
    public static String toSimplified(String str) {
        return Converter.SIMPLIFIED.convert(str);
    }

    public static String toTraditional(String str) {
        return Converter.TRADITIONAL.convert(str);
    }

    public static String toPinyin(String str, PinyinFormat pinyinFormat) {
        return Pinyin.INSTANCE.convert(str, pinyinFormat);
    }

    public static String toPinyin(String str) {
        return Pinyin.INSTANCE.convert(str, PinyinFormat.DEFAULT_PINYIN_FORMAT);
    }

    public static void main(String[] strArr) {
        printHelp();
        printHit(0);
        int i = 0;
        while (true) {
            String inputTextLine = readInputTextLine();
            if (inputTextLine == null || inputTextLine.isEmpty()) {
                printHelp();
            } else if ("q".equals(inputTextLine)) {
                System.exit(0);
            } else if ("t".equals(inputTextLine)) {
                i = 2;
            } else if ("s".equals(inputTextLine)) {
                i = 1;
            } else if (i == 1) {
                System.out.println("简体: " + toSimplified(inputTextLine));
            } else if (i == 2) {
                System.out.println("繁体: " + toTraditional(inputTextLine));
            } else {
                System.out.println("拼音: " + toPinyin(inputTextLine) + " (" + toPinyin(inputTextLine, PinyinFormat.UNICODE_PINYIN_FORMAT) + ")");
            }
            printHit(i);
        }
    }

    public static String readInputTextLine() {
        try {
            return new BufferedReader(new InputStreamReader(System.in)).readLine();
        } catch (IOException e) {
            e.printStackTrace();
            return null;
        }
    }

    public static void printHelp() {
        System.out.println("请输入希望转换的中文或输入[q]退出、[s]转简体、[t]转繁体、[p]转拼音。");
    }

    public static void printHit(int i) {
        if (i == 1) {
            System.out.print("转简> ");
        } else if (i == 2) {
            System.out.print("转繁> ");
        } else {
            System.out.print("转拼> ");
        }
    }
}
