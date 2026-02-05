package eu.kanade.tachiyomi.lib.chineseutils;

import java.io.BufferedInputStream;
import java.io.BufferedReader;
import java.io.CharArrayWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PushbackReader;
import java.io.Reader;
import java.io.StringReader;
import java.io.StringWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;

/* loaded from: classes.dex */
public enum Converter {
    SIMPLIFIED(false),
    TRADITIONAL(true);

    public static final char CJK_UNIFIED_IDEOGRAPHS_END = 40869;
    public static final char CJK_UNIFIED_IDEOGRAPHS_START = 19968;
    public static final String EMPTY = "";
    public static final String EQUAL = "=";
    public static final String SHARP = "#";
    public static final String SIMPLIFIED_LEXEMIC_MAPPING_FILE = "/assets/simplified.txt";
    public static final String SIMPLIFIED_MAPPING_FILE = "/assets/simp.txt";
    public static final String TRADITIONAL_LEXEMIC_MAPPING_FILE = "/assets/traditional.txt";
    public static final String TRADITIONAL_MAPPING_FILE = "/assets/trad.txt";
    private char[] chars = null;
    private Trie<String> dict = null;
    private int maxLen = 2;

    Converter(boolean z) throws IOException {
        loadCharMapping(z);
        loadLexemicMapping(z);
    }

    public void loadCharMapping(boolean z) throws IOException {
        String str;
        if (!z) {
            str = SIMPLIFIED_MAPPING_FILE;
        } else {
            str = TRADITIONAL_MAPPING_FILE;
        }
        try {
            BufferedReader bufferedReader = new BufferedReader(new InputStreamReader(new BufferedInputStream(getClass().getResourceAsStream(str)), StandardCharsets.UTF_8));
            CharArrayWriter charArrayWriter = new CharArrayWriter();
            while (true) {
                String line = bufferedReader.readLine();
                if (line != null) {
                    charArrayWriter.write(line);
                } else {
                    this.chars = charArrayWriter.toCharArray();
                    bufferedReader.close();
                    return;
                }
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    public void loadLexemicMapping(boolean z) throws IOException {
        String str;
        if (!z) {
            str = SIMPLIFIED_LEXEMIC_MAPPING_FILE;
        } else {
            str = TRADITIONAL_LEXEMIC_MAPPING_FILE;
        }
        this.dict = new Trie<>();
        try {
            BufferedReader bufferedReader = new BufferedReader(new InputStreamReader(new BufferedInputStream(getClass().getResourceAsStream(str)), StandardCharsets.UTF_8));
            while (true) {
                String line = bufferedReader.readLine();
                if (line != null) {
                    if (!line.isEmpty() && !line.startsWith("#")) {
                        String[] strArrSplit = line.split("=");
                        if (strArrSplit.length >= 2) {
                            this.maxLen = Math.max(this.maxLen, strArrSplit[0].length());
                            this.dict.add(strArrSplit[0], strArrSplit[1]);
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

    public char convert(char c) {
        return (c < 19968 || c > 40869) ? c : this.chars[c - CJK_UNIFIED_IDEOGRAPHS_START];
    }

    public void convert(Reader reader, Writer writer) throws IOException {
        PushbackReader pushbackReader = new PushbackReader(new BufferedReader(reader), this.maxLen);
        char[] cArr = new char[this.maxLen];
        while (true) {
            int i = pushbackReader.read(cArr);
            if (i == -1) {
                return;
            }
            TrieNode<String> trieNodeBestMatch = this.dict.bestMatch(cArr, 0, i);
            if (trieNodeBestMatch != null) {
                int level = trieNodeBestMatch.getLevel();
                writer.write(trieNodeBestMatch.getValue());
                pushbackReader.unread(cArr, level, i - level);
            } else {
                pushbackReader.unread(cArr, 0, i);
                writer.write(convert((char) pushbackReader.read()));
            }
        }
    }

    public String convert(String str) {
        StringReader stringReader = new StringReader(str);
        StringWriter stringWriter = new StringWriter();
        try {
            convert(stringReader, stringWriter);
        } catch (IOException e) {
            e.printStackTrace();
        }
        return stringWriter.toString();
    }
}
