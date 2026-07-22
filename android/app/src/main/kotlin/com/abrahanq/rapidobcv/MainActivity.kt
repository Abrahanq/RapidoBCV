package com.abrahanq.rapidobcv

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)

		// Opt-in edge-to-edge for pre-15 compatibility. Android 15+ (target SDK 35+)
		// already enforces edge-to-edge by default; do not set statusBarColor /
		// navigationBarColor directly, those Window APIs are deprecated for
		// edge-to-edge apps as of Android 15.
		WindowCompat.setDecorFitsSystemWindows(window, false)
	}
}
