package io.github.michalkozik.koho;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;
import android.util.Log;
import android.widget.Toast;

/**
 * Home activity that only forwards to KOReader. Recovery chain when that is impossible
 * (KOReader missing, disabled/frozen by the device): stock Boox home, then system Settings,
 * then a toast. Add other KOReader package ids or stock home components below.
 */
public class Home extends Activity {
    private static final String TAG = "koho";
    private static final String[] READERS = {
        "org.koreader.launcher",
        "org.koreader.launcher.fdroid",
    };
    private static final String[][] STOCK_HOMES = {
        {"com.onyx", "com.onyx.StartupActivity"},
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (!startReader() && !startStockHome() && !startSettings()) {
            Toast.makeText(this, "koho: no reader or recovery launcher found", Toast.LENGTH_LONG).show();
        }
        finish();
    }

    private boolean startReader() {
        for (String pkg : READERS) {
            try {
                Intent launch = getPackageManager().getLaunchIntentForPackage(pkg);
                if (launch == null) {
                    continue;
                }
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
                startActivity(launch);
                return true;
            } catch (Exception e) {
                Log.w(TAG, "could not start reader " + pkg, e);
            }
        }
        return false;
    }

    private boolean startStockHome() {
        for (String[] component : STOCK_HOMES) {
            try {
                Intent home = new Intent(Intent.ACTION_MAIN);
                home.setComponent(new ComponentName(component[0], component[1]));
                home.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(home);
                return true;
            } catch (Exception e) {
                Log.w(TAG, "could not start stock home " + component[0], e);
            }
        }
        return false;
    }

    private boolean startSettings() {
        try {
            Intent settings = new Intent(Settings.ACTION_SETTINGS);
            settings.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(settings);
            return true;
        } catch (Exception e) {
            Log.w(TAG, "could not start settings", e);
            return false;
        }
    }
}
