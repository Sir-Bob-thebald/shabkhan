package com.nightlyreader.nightly_reader

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Hands two kinds of incoming intents to Flutter:
/// - links shared from other apps ("Share → Nightly Reader"), to add as a source;
/// - the Notion sign-in coming back (shabkhan://oauth/notion?code=…).
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingShare: String? = null
    private var pendingLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nightly_reader/share").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeShared" -> { result.success(pendingShare); pendingShare = null }
                    "takeLink" -> { result.success(pendingLink); pendingLink = null }
                    else -> result.notImplemented()
                }
            }
        }
        if (!fromHistory(intent)) {
            pendingShare = sharedText(intent)
            pendingLink = openedLink(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        sharedText(intent)?.let { channel?.invokeMethod("shared", it) }
        openedLink(intent)?.let { channel?.invokeMethod("link", it) }
    }

    // Reopened from Recents after Android closed the app: that intent was already handled.
    private fun fromHistory(intent: Intent?) =
        intent != null && intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0

    private fun sharedText(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_SEND || intent.type != "text/plain") return null
        // Some apps share rich text, which getStringExtra would drop.
        return intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
    }

    private fun openedLink(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_VIEW) intent.dataString else null
}
