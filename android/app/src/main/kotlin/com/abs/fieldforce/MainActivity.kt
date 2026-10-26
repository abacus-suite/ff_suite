package com.abs.fieldforce

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "ff/whatsapp" sendFile: a PDF from the cache's ledgers folder straight into one WhatsApp chat.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ff/whatsapp").setMethodCallHandler { call, result ->
            if (call.method != "sendFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            val phone = call.argument<String>("phone")
            val text = call.argument<String>("text")
            result.success(path != null && phone != null && sendFile(File(path), phone, text))
        }
    }

    /** Opens the chat with [phone] (digits with the country code) with the file attached, in WhatsApp
     *  or else WhatsApp Business. False when neither is installed, so the app can share another way. */
    private fun sendFile(file: File, phone: String, text: String?): Boolean {
        if (!file.exists()) return false
        val uri = FileProvider.getUriForFile(this, "$packageName.ledger_files", file)
        for (app in listOf("com.whatsapp", "com.whatsapp.w4b")) {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "application/pdf"
                setPackage(app)
                putExtra(Intent.EXTRA_STREAM, uri)
                if (text != null) putExtra(Intent.EXTRA_TEXT, text)
                // WhatsApp's way to pick the chat: the number as its "jid".
                putExtra("jid", "$phone@s.whatsapp.net")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            try {
                startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                // Not installed: try the next one.
            }
        }
        return false
    }
}
