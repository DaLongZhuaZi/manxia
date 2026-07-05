package eu.kanade.tachiyomi.extension.zh.copymanga;

import kotlin.Metadata;
import kotlin.jvm.internal.Intrinsics;

/* JADX INFO: compiled from: Filter.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\t\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\u0002\b\u0086\b\u0018\u00002\u00020\u0001B\u0015\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003¢\u0006\u0002\u0010\u0005J\t\u0010\t\u001a\u00020\u0003HÆ\u0003J\t\u0010\n\u001a\u00020\u0003HÆ\u0003J\u001d\u0010\u000b\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u0003HÆ\u0001J\u0013\u0010\f\u001a\u00020\r2\b\u0010\u000e\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u000f\u001a\u00020\u0010HÖ\u0001J\t\u0010\u0011\u001a\u00020\u0003HÖ\u0001R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0006\u0010\u0007R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\b\u0010\u0007¨\u0006\u0012"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/Tag;", "", "name", "", "pathWord", "(Ljava/lang/String;Ljava/lang/String;)V", "getName", "()Ljava/lang/String;", "getPathWord", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final /* data */ class Tag {
    private final String name;
    private final String pathWord;

    public static /* synthetic */ Tag copy$default(Tag tag, String str, String str2, int i, Object obj) {
        if ((i & 1) != 0) {
            str = tag.name;
        }
        if ((i & 2) != 0) {
            str2 = tag.pathWord;
        }
        return tag.copy(str, str2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getPathWord() {
        return this.pathWord;
    }

    public final Tag copy(String name, String pathWord) {
        Intrinsics.checkNotNullParameter(name, "name");
        Intrinsics.checkNotNullParameter(pathWord, "pathWord");
        return new Tag(name, pathWord);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof Tag)) {
            return false;
        }
        Tag tag = (Tag) other;
        return Intrinsics.areEqual(this.name, tag.name) && Intrinsics.areEqual(this.pathWord, tag.pathWord);
    }

    public int hashCode() {
        return (this.name.hashCode() * 31) + this.pathWord.hashCode();
    }

    public String toString() {
        return "Tag(name=" + this.name + ", pathWord=" + this.pathWord + ')';
    }

    public Tag(String str, String str2) {
        Intrinsics.checkNotNullParameter(str, "name");
        Intrinsics.checkNotNullParameter(str2, "pathWord");
        this.name = str;
        this.pathWord = str2;
    }

    public final String getName() {
        return this.name;
    }

    public final String getPathWord() {
        return this.pathWord;
    }
}
