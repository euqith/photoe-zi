package com.photoezi.photoe_zi

import android.annotation.SuppressLint
import android.app.Dialog
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.net.Uri
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.photoezi/oauth_popup"
    private var activeDialog: Dialog? = null
    private var pendingResult: MethodChannel.Result? = null
    private var isCompleted: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openOAuthPopup" -> {
                        val url = call.argument<String>("url")
                        val redirectPrefix = call.argument<String>("redirectPrefix") ?: "http://127.0.0.1"
                        if (url.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Missing OAuth URL", null)
                        } else {
                            presentOAuthPopupDialog(url, redirectPrefix, result)
                        }
                    }
                    "closeOAuthPopup" -> {
                        dismissActivePopup(null, notifyCancel = false)
                        result.success(true)
                    }
                    "openExternalUrl" -> {
                        val url = call.argument<String>("url")
                        if (!url.isNullOrBlank()) {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun presentOAuthPopupDialog(
        authUrl: String,
        redirectPrefix: String,
        flutterResult: MethodChannel.Result
    ) {
        if (activeDialog != null) {
            dismissActivePopup(null, notifyCancel = true)
        }

        pendingResult = flutterResult
        isCompleted = false

        val dialog = Dialog(this, android.R.style.Theme_DeviceDefault_NoActionBar)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
        dialog.window?.setBackgroundDrawable(ColorDrawable(Color.parseColor("#18181B")))

        val rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#18181B"))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        // Top Studio Header Bar
        val density = resources.displayMetrics.density
        val headerHeight = (52 * density).toInt()
        val horizontalPad = (16 * density).toInt()

        val headerBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.parseColor("#222226"))
            setPadding(horizontalPad, 0, horizontalPad, 0)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                headerHeight
            )
        }

        val titleView = TextView(this).apply {
            text = "Sign in with Google — PhotoE-Zi"
            setTextColor(Color.parseColor("#F3F4F6"))
            textSize = 15f
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }

        val closeBtn = TextView(this).apply {
            text = "Cancel"
            setTextColor(Color.parseColor("#F59E0B"))
            textSize = 14f
            setPadding((12 * density).toInt(), (8 * density).toInt(), (4 * density).toInt(), (8 * density).toInt())
            setOnClickListener {
                dismissActivePopup(null, notifyCancel = true)
            }
        }

        headerBar.addView(titleView)
        headerBar.addView(closeBtn)
        rootLayout.addView(headerBar)

        val webContainer = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        }

        val progressBar = ProgressBar(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        }

        val webView = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.setSupportZoom(true)
            // Standard Android Chrome Mobile User-Agent (without '; wv') so Google OAuth 2.0 allows sign-in
            settings.userAgentString =
                "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
        }

        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        fun isLoopbackRedirect(targetUrl: String): Boolean {
            if (targetUrl.startsWith(redirectPrefix)) return true
            return try {
                val uri = Uri.parse(targetUrl)
                val host = uri.host?.lowercase() ?: ""
                (host == "127.0.0.1" || host == "localhost") &&
                        (targetUrl.contains("code=") || targetUrl.contains("error="))
            } catch (_: Exception) {
                false
            }
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                val targetUrl = request?.url?.toString() ?: return false
                if (isLoopbackRedirect(targetUrl)) {
                    dismissActivePopup(targetUrl, notifyCancel = false)
                    return true
                }
                return false
            }

            @Deprecated("Deprecated in Java")
            override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                val targetUrl = url ?: return false
                if (isLoopbackRedirect(targetUrl)) {
                    dismissActivePopup(targetUrl, notifyCancel = false)
                    return true
                }
                return false
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                progressBar.visibility = View.GONE
                if (url != null && isLoopbackRedirect(url)) {
                    dismissActivePopup(url, notifyCancel = false)
                }
            }
        }

        webContainer.addView(webView)
        webContainer.addView(progressBar)
        rootLayout.addView(webContainer)

        dialog.setContentView(rootLayout)
        dialog.setOnCancelListener {
            dismissActivePopup(null, notifyCancel = true)
        }
        dialog.setOnDismissListener {
            if (!isCompleted) {
                dismissActivePopup(null, notifyCancel = true)
            }
        }

        activeDialog = dialog
        dialog.show()
        webView.loadUrl(authUrl)
    }

    private fun dismissActivePopup(callbackUrl: String?, notifyCancel: Boolean) {
        if (isCompleted && callbackUrl == null && !notifyCancel) {
            return
        }
        isCompleted = true
        val res = pendingResult
        pendingResult = nilResult()
        val dlg = activeDialog
        activeDialog = null

        runOnUiThread {
            try {
                if (dlg != null && dlg.isShowing) {
                    dlg.dismiss()
                }
            } catch (_: Exception) {
            }
            if (callbackUrl != null) {
                res?.success(callbackUrl)
            } else if (notifyCancel) {
                res?.success(null)
            }
        }
    }

    private fun nilResult(): MethodChannel.Result? = null
}
