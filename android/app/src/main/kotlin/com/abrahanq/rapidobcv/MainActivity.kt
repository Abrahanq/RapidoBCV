package com.abrahanq.rapidobcv

import android.graphics.Color
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)

		// Opt-in edge-to-edge for Android 15+ and keep the same behavior on older versions.
		WindowCompat.setDecorFitsSystemWindows(window, false)
		window.statusBarColor = Color.TRANSPARENT
		window.navigationBarColor = Color.TRANSPARENT
	}
}
