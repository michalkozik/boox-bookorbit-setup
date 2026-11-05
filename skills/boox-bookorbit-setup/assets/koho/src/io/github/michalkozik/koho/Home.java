package io.github.michalkozik.koho;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Bundle;

public class Home extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Intent i = getPackageManager().getLaunchIntentForPackage("org.koreader.launcher");
        try {
            if (i == null) throw new RuntimeException("koreader unavailable");
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
            startActivity(i);
        } catch (Exception e) {
            // KOReader frozen or missing: fall back to the stock Boox launcher
            Intent f = new Intent(Intent.ACTION_MAIN);
            f.setComponent(new ComponentName("com.onyx", "com.onyx.StartupActivity"));
            f.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try { startActivity(f); } catch (Exception ignored) { }
        }
        finish();
    }
}
