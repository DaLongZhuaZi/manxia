package eu.kanade.tachiyomi.lib.chineseutils;

import java.util.HashMap;
import java.util.Map;

/* loaded from: classes.dex */
public class TrieNode<T> {
    private char key;
    private boolean leaf;
    private T value;
    private int level = 0;
    private final Map<Character, TrieNode<T>> children = new HashMap();

    public TrieNode(char c) {
        this.key = c;
    }

    public char getKey() {
        return this.key;
    }

    public void setKey(char c) {
        this.key = c;
    }

    public boolean isLeaf() {
        return this.leaf;
    }

    public void setLeaf(boolean z) {
        this.leaf = z;
    }

    public T getValue() {
        return this.value;
    }

    public void setValue(T t) {
        this.value = t;
    }

    public TrieNode<T> addChild(char c) {
        TrieNode<T> trieNode = new TrieNode<>(c);
        trieNode.level = this.level + 1;
        this.children.put(Character.valueOf(c), trieNode);
        return trieNode;
    }

    public TrieNode<T> child(char c) {
        return this.children.get(Character.valueOf(c));
    }

    public int getLevel() {
        return this.level;
    }

    public void setLevel(int i) {
        this.level = i;
    }

    public String toString() {
        StringBuilder sb = new StringBuilder(this.key);
        if (this.value != null) {
            sb.append(":");
            sb.append(this.value);
        }
        return sb.toString();
    }
}
