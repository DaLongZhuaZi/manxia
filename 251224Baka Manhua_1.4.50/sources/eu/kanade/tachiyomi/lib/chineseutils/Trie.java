package eu.kanade.tachiyomi.lib.chineseutils;

/* loaded from: classes.dex */
public class Trie<T> {
    private TrieNode<T> root = new TrieNode<>(' ');

    public void add(char[] cArr, T t) {
        if (cArr.length < 1) {
            return;
        }
        TrieNode<T> trieNodeAddChild = this.root;
        for (char c : cArr) {
            TrieNode<T> trieNodeChild = trieNodeAddChild.child(c);
            trieNodeAddChild = trieNodeChild == null ? trieNodeAddChild.addChild(c) : trieNodeChild;
        }
        trieNodeAddChild.setLeaf(true);
        trieNodeAddChild.setValue(t);
    }

    public void add(String str, T t) {
        if (str == null) {
            return;
        }
        add(str.toCharArray(), (char[]) t);
    }

    public TrieNode<T> match(char[] cArr, int i, int i2) {
        TrieNode<T> trieNodeChild = this.root;
        for (int i3 = 0; i3 < i2; i3++) {
            trieNodeChild = trieNodeChild.child(cArr[i + i3]);
            if (trieNodeChild == null) {
                return null;
            }
        }
        return trieNodeChild;
    }

    public TrieNode<T> bestMatch(char[] cArr, int i, int i2) {
        TrieNode<T> trieNodeChild = this.root;
        TrieNode<T> trieNode = null;
        while (i < i2) {
            trieNodeChild = trieNodeChild.child(cArr[i]);
            if (trieNodeChild == null) {
                break;
            }
            if (trieNodeChild.isLeaf()) {
                trieNode = trieNodeChild;
            }
            i++;
        }
        return trieNode;
    }

    public TrieNode<T> bestMatch(char[] cArr, int i) {
        return bestMatch(cArr, i, cArr.length);
    }
}
