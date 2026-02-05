package eu.kanade.tachiyomi.lib.chineseutils.pinyin;

import eu.kanade.tachiyomi.lib.chineseutils.Converter;
import eu.kanade.tachiyomi.lib.chineseutils.Trie;
import eu.kanade.tachiyomi.lib.chineseutils.TrieNode;
import java.io.BufferedInputStream;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PushbackReader;
import java.io.Reader;
import java.io.StringReader;
import java.io.StringWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/* loaded from: classes.dex */
public enum Pinyin {
    INSTANCE;

    public static final String COMMA = ",";
    public static final String EMPTY = "";
    public static final String EQUAL = "=";
    public static final String PINYIN_MAPPING_FILE = "/assets/pinyin.txt";
    public static final String POLYPHONE_MAPPING_FILE = "/assets/polyphone.txt";
    public static final String SHARP = "#";
    public static final String SPACE = " ";
    private List<String> pinyinDict = null;
    private Trie<String> polyphoneDict = null;
    private int maxLen = 2;

    Pinyin() throws IOException {
        loadPinyinMapping();
        loadPolyphoneMapping();
    }

    public void loadPinyinMapping() throws IOException {
        this.pinyinDict = new ArrayList();
        try {
            BufferedReader bufferedReader = new BufferedReader(new InputStreamReader(new BufferedInputStream(getClass().getResourceAsStream(PINYIN_MAPPING_FILE)), StandardCharsets.UTF_8));
            while (true) {
                String line = bufferedReader.readLine();
                if (line != null) {
                    if (!line.isEmpty() && !line.startsWith("#")) {
                        String[] strArrSplit = line.split("=");
                        if (strArrSplit.length < 2) {
                            this.pinyinDict.add("");
                        } else {
                            this.pinyinDict.add(strArrSplit[1]);
                        }
                    }
                } else {
                    bufferedReader.close();
                    return;
                }
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    public void loadPolyphoneMapping() throws IOException {
        this.polyphoneDict = new Trie<>();
        try {
            BufferedReader bufferedReader = new BufferedReader(new InputStreamReader(new BufferedInputStream(getClass().getResourceAsStream(POLYPHONE_MAPPING_FILE)), StandardCharsets.UTF_8));
            while (true) {
                String line = bufferedReader.readLine();
                if (line != null) {
                    if (!line.isEmpty() && !line.startsWith("#")) {
                        String[] strArrSplit = line.split("=");
                        if (strArrSplit.length >= 2) {
                            this.maxLen = Math.max(this.maxLen, strArrSplit[0].length());
                            this.polyphoneDict.add(strArrSplit[0], strArrSplit[1]);
                        }
                    }
                } else {
                    bufferedReader.close();
                    return;
                }
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    public String[] toUnformattedPinyin(char c) {
        if (c < 19968 || c > 40869) {
            return null;
        }
        return this.pinyinDict.get(c - Converter.CJK_UNIFIED_IDEOGRAPHS_START).split(COMMA);
    }

    public String[] toFormattedPinyin(char c, PinyinFormat pinyinFormat) {
        String[] unformattedPinyin = toUnformattedPinyin(c);
        if (unformattedPinyin == null) {
            return null;
        }
        for (int i = 0; i < unformattedPinyin.length; i++) {
            unformattedPinyin[i] = PinyinFormatter.formatPinyin(unformattedPinyin[i], pinyinFormat);
        }
        return unformattedPinyin;
    }

    public String toPinyin(char c) {
        String[] unformattedPinyin = toUnformattedPinyin(c);
        if (unformattedPinyin == null || unformattedPinyin.length <= 0) {
            return null;
        }
        return unformattedPinyin[0];
    }

    public String toPinyin(char c, PinyinFormat pinyinFormat) {
        String[] formattedPinyin = toFormattedPinyin(c, pinyinFormat);
        if (formattedPinyin == null || formattedPinyin.length <= 0) {
            return null;
        }
        return formattedPinyin[0];
    }

    public void convert(Reader reader, Writer writer, PinyinFormat pinyinFormat) throws IOException {
        PushbackReader pushbackReader = new PushbackReader(new BufferedReader(reader), this.maxLen);
        char[] cArr = new char[this.maxLen];
        boolean z = false;
        while (true) {
            int i = pushbackReader.read(cArr);
            if (i == -1) {
                return;
            }
            TrieNode<String> trieNodeBestMatch = this.polyphoneDict.bestMatch(cArr, 0, i);
            if (trieNodeBestMatch != null) {
                int level = trieNodeBestMatch.getLevel();
                for (String str : trieNodeBestMatch.getValue().split(SPACE)) {
                    String pinyin = PinyinFormatter.formatPinyin(str, pinyinFormat);
                    if (pinyin != null) {
                        if (z) {
                            writer.write(pinyinFormat.getSeparator());
                        }
                        writer.write(pinyin);
                        z = true;
                    }
                }
                pushbackReader.unread(cArr, level, i - level);
            } else {
                pushbackReader.unread(cArr, 0, i);
                char c = (char) pushbackReader.read();
                String pinyin2 = toPinyin(c, pinyinFormat);
                if (pinyin2 != null) {
                    if (z) {
                        writer.write(pinyinFormat.getSeparator());
                    }
                    writer.write(pinyin2);
                } else if (!pinyinFormat.isOnlyPinyin()) {
                    writer.write(c);
                }
                z = true;
            }
        }
    }

    public String convert(String str, PinyinFormat pinyinFormat) {
        StringReader stringReader = new StringReader(str);
        StringWriter stringWriter = new StringWriter();
        try {
            convert(stringReader, stringWriter, pinyinFormat);
        } catch (IOException e) {
            e.printStackTrace();
        }
        return stringWriter.toString();
    }
}
