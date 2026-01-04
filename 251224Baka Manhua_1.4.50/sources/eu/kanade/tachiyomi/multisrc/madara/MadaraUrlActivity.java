package eu.kanade.tachiyomi.multisrc.madara;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;
import java.util.List;
import kotlin.Metadata;

/* compiled from: MadaraUrlActivity.kt */
@Metadata(d1 = {"\u0000$\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010!\n\u0000\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\u0018\u00002\u00020\u0001B\u0005¢\u0006\u0002\u0010\u0002J\u0018\u0010\u0003\u001a\u0004\u0018\u00010\u00042\f\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00040\u0006H\u0002J\u0012\u0010\u0007\u001a\u00020\b2\b\u0010\t\u001a\u0004\u0018\u00010\nH\u0014¨\u0006\u000b"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/MadaraUrlActivity;", "Landroid/app/Activity;", "()V", "getSLUG", "", "pathSegments", "", "onCreate", "", "savedInstanceState", "Landroid/os/Bundle;", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class MadaraUrlActivity extends Activity {
    @Override // android.app.Activity
    protected void onCreate(Bundle savedInstanceState) {
        Uri data;
        super.onCreate(savedInstanceState);
        Intent intent = getIntent();
        List pathSegments = (intent == null || (data = intent.getData()) == null) ? null : data.getPathSegments();
        if (pathSegments == null || pathSegments.size() < 2) {
            Log.e("MadaraUrl", "could not parse uri from intent " + getIntent());
        } else {
            Intent mainIntent = new Intent();
            mainIntent.setAction("eu.kanade.tachiyomi.SEARCH");
            mainIntent.putExtra("query", String.valueOf(getSLUG(pathSegments)));
            mainIntent.putExtra("filter", getPackageName());
            try {
                startActivity(mainIntent);
            } catch (ActivityNotFoundException e) {
                Log.e("MadaraUrl", e.toString());
            }
        }
        finish();
        System.exit(0);
        throw new RuntimeException("System.exit returned normally, while it was supposed to halt JVM.");
    }

    private final String getSLUG(List<String> pathSegments) {
        if (pathSegments.size() >= 2) {
            String slug = pathSegments.get(1);
            return Madara.URL_SEARCH_PREFIX + slug;
        }
        return null;
    }
}
