package fr.la.chat

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.core.content.FileProvider
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/**
 * L'enveloppe native : une WebView qui porte l'interface, et une passerelle qui lui donne le
 * micro, le haut-parleur, les photos, la bulle et le service.
 *
 * La page ne parle au poste que par cette passerelle : elle ne connait ni le certificat ni
 * l'adresse, et n'ouvre aucune connexion elle-même.
 */
class ChatActivity : Activity() {

  private lateinit var web: WebView
  private lateinit var recorder: Recorder
  private var pendingAction: (() -> Unit)? = null
  private var photoUri: Uri? = null
  private var dead = false

  private val net = Executors.newSingleThreadExecutor { r -> Thread(r, "jarvis-image").apply { isDaemon = true } }

  private val turnListener: (JSONObject) -> Unit = { push(it) }
  private val audioListener: (JSONObject) -> Unit = { push(it) }
  @Volatile private var syncing = false

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    recorder = Recorder(this)
    web = WebView(this)
    setContentView(web)
    configure()
    web.loadUrl("file:///android_asset/index.html")

    TurnEngine.addListener(turnListener)
    Speaker.addListener(audioListener)

    if (Bridge.prefs(this).getBoolean("jarvis", false)) {
      window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    autoStartBubble()
    askStartupPermissions()
    onNewIntent(intent)
  }

  private fun configure() {
    val s = web.settings
    s.javaScriptEnabled = true
    s.domStorageEnabled = true
    s.allowFileAccess = false            // android_asset reste lisible
    s.allowContentAccess = false
    s.javaScriptCanOpenWindowsAutomatically = false
    s.mediaPlaybackRequiresUserGesture = false
    s.setSupportZoom(false)
    s.builtInZoomControls = false
    web.setBackgroundColor(Color.parseColor("#0A0B0F"))
    web.addJavascriptInterface(JsApi(), "Android")

    web.webChromeClient = object : WebChromeClient() {
      override fun onConsoleMessage(m: ConsoleMessage): Boolean {
        Log.d("JarvisWeb", "${m.message()} (${m.sourceId()}:${m.lineNumber()})")
        return true
      }
    }

    web.webViewClient = object : WebViewClient() {
      // Un lien externe s'ouvre dans le navigateur ; la page de l'app ne navigue jamais.
      override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
        val u = request?.url ?: return false
        if (u.scheme == "http" || u.scheme == "https") {
          try {
            startActivity(Intent(Intent.ACTION_VIEW, u))
          } catch (e: Exception) {
            Log.w("Jarvis", "aucun navigateur pour $u")
          }
          return true
        }
        return false
      }
    }
  }

  /** Comme la v1 : la bulle se pose seule dès que l'utilisateur a autorisé l'overlay. */
  private fun autoStartBubble() {
    if (!Settings.canDrawOverlays(this) || JarvisService.running) return
    try {
      val i = Intent(this, JarvisService::class.java)
      if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
    } catch (e: Exception) {
      Log.w("Jarvis", "auto-démarrage de la bulle refusé", e)
    }
  }

  // ------------------------------------------------------------------ événements vers l'UI

  private fun push(o: JSONObject) {
    if (dead) return
    runOnUiThread {
      if (dead) return@runOnUiThread
      val script = "window.JarvisApply&&window.JarvisApply(${JSONObject.quote(o.toString())})"
      web.evaluateJavascript(script, null)
    }
  }

  private fun stateJson(): JSONObject {
    val o = JSONObject()
      .put("type", "state")
      .put("address", Bridge.address(this))
      .put("fallback", Bridge.fallbackEnabled(this))
      .put("jarvis", Bridge.prefs(this).getBoolean("jarvis", false))
      .put("service", JarvisService.running)
      .put("overlay", Settings.canDrawOverlays(this))
      .put("mic", checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)
      .put("notif", hasNotifPermission())
      .put("running", TurnEngine.running)
      .put("expired", Bridge.certExpired(this))
    return o
  }

  private fun hasNotifPermission(): Boolean =
    Build.VERSION.SDK_INT < 33 ||
      checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

  // ------------------------------------------------------------------ permissions

  private fun askStartupPermissions() {
    val wanted = ArrayList<String>()
    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
      wanted.add(Manifest.permission.RECORD_AUDIO)
    }
    if (Build.VERSION.SDK_INT >= 33 &&
      checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
    ) {
      wanted.add(Manifest.permission.POST_NOTIFICATIONS)
    }
    if (wanted.isNotEmpty()) requestPermissions(wanted.toTypedArray(), REQ_STARTUP)
  }

  private fun withMic(action: () -> Unit) {
    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
      action()
    } else {
      pendingAction = action
      requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQ_MIC)
    }
  }

  override fun onRequestPermissionsResult(request: Int, perms: Array<out String>, grants: IntArray) {
    super.onRequestPermissionsResult(request, perms, grants)
    if (request == REQ_MIC) {
      val ok = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
      val a = pendingAction
      pendingAction = null
      if (ok) a?.invoke()
      else push(JSONObject().put("type", "error").put("message", getString(R.string.mic_denied)))
    }
    push(stateJson())
  }

  // ------------------------------------------------------------------ la passerelle JS

  inner class JsApi {

    @JavascriptInterface
    fun ready() = push(stateJson())

    @JavascriptInterface
    fun state() = push(stateJson())

    @JavascriptInterface
    fun send(text: String) {
      if (text.isBlank()) return
      TurnEngine.sendText(this@ChatActivity, text)
    }

    @JavascriptInterface
    fun startVoice() {
      runOnUiThread {
        if (recorder.isRecording()) return@runOnUiThread
        withMic {
          val err = recorder.start()
          if (err == null) {
            buzz(24)
            push(JSONObject().put("type", "recording").put("on", true))
          } else {
            push(JSONObject().put("type", "error").put("message", getString(R.string.mic_failed, err)))
          }
        }
      }
    }

    @JavascriptInterface
    fun stopVoice() {
      runOnUiThread {
        if (!recorder.isRecording()) return@runOnUiThread
        val bytes = recorder.stop()
        buzz(16)
        push(JSONObject().put("type", "recording").put("on", false))
        if (bytes == null || bytes.size < 1200) {
          push(JSONObject().put("type", "error").put("message", getString(R.string.nothing_recorded)))
        } else {
          push(JSONObject().put("type", "uploading"))
          TurnEngine.sendVoice(this@ChatActivity, bytes)
        }
      }
    }

    @JavascriptInterface
    fun cancelVoice() {
      runOnUiThread {
        recorder.cancel()
        push(JSONObject().put("type", "recording").put("on", false))
      }
    }

    @JavascriptInterface
    fun stopTurn() = TurnEngine.stopTurn(this@ChatActivity)

    @JavascriptInterface
    fun ping() = TurnEngine.ping(this@ChatActivity)

    /** Demarrer ou arreter les residents : la meme route que le bouton de la page. */
    @JavascriptInterface
    fun residents() {
      net.execute {
        val t = runCatching {
          Bridge.post(this@ChatActivity, "/api/residents",
                      "{\"op\":\"toggle\"}".toByteArray(Charsets.UTF_8), "application/json")
        }.getOrElse { "" }
        val o = Bridge.asObject(t)
        val txt = o.optString("text", "").replace("\n", " ")
        // "note 3/3 resident(s) up" : le compte peint la pastille
        val m = Regex("(\\d+)/(\\d+) resident").find(txt)
        val up = m?.groupValues?.get(1)?.toIntOrNull() ?: -1
        val all = m?.groupValues?.get(2)?.toIntOrNull() ?: -1
        runOnUiThread {
          push(JSONObject().put("type", "residentsReport").put("up", up).put("total", all).put("text", txt.take(120)))
          push(JSONObject().put("type", "toast").put("text", txt.take(120)))
        }
      }
    }

    @JavascriptInterface
    fun engines() = TurnEngine.engines(this@ChatActivity)

    /** Une notification système par message (comme une appli de messagerie). */
    @JavascriptInterface
    fun notifyMessage(title: String, body: String) {
      if (!hasNotifPermission() || body.isBlank()) return
      runOnUiThread {
        try {
          val ch = "la_messages"
          val nm = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
          nm.createNotificationChannel(
            android.app.NotificationChannel(ch, "Messages", android.app.NotificationManager.IMPORTANCE_DEFAULT)
          )
          val open = android.app.PendingIntent.getActivity(
            this@ChatActivity, 10, Intent(this@ChatActivity, ChatActivity::class.java),
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
          )
          val n = android.app.Notification.Builder(this@ChatActivity, ch)
            .setContentTitle(title.ifBlank { "Agent One" })
            .setContentText(body)
            .setStyle(android.app.Notification.BigTextStyle().bigText(body))
            .setSmallIcon(android.R.drawable.ic_dialog_email)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
          nm.notify((System.currentTimeMillis() % 100000).toInt(), n)
        } catch (e: Exception) {
          Log.w("Jarvis", "notification impossible", e)
        }
      }
    }

    @JavascriptInterface
    fun plan() = TurnEngine.plan(this@ChatActivity)

    /** Vue unifiée : l'appli lit l'état partagé du poste (mêmes routes que le dashboard/CLI). */
    @JavascriptInterface
    fun refreshShared() {
      if (syncing) return
      syncing = true
      net.execute {
        try {
          pushJsonUi("sharedState", runCatching { Bridge.get(this@ChatActivity, "/state") }.getOrNull())
          pushJsonUi("agentsData", runCatching { Bridge.get(this@ChatActivity, "/agents") }.getOrNull())
          pushJsonUi("history", runCatching { Bridge.get(this@ChatActivity, "/history?turns=25") }.getOrNull())
          pushJsonUi("skills", runCatching { Bridge.get(this@ChatActivity, "/skills") }.getOrNull())
          pushJsonUi("projects", runCatching { Bridge.get(this@ChatActivity, "/projects") }.getOrNull())
          pushJsonUi("toolmap", runCatching { Bridge.get(this@ChatActivity, "/toolmap") }.getOrNull())
          pushJsonUi("approval", runCatching { Bridge.get(this@ChatActivity, "/approval") }.getOrNull())
        } finally {
          syncing = false
        }
      }
    }

    private fun pushJsonUi(type: String, body: String?) {
      if (body.isNullOrBlank()) return
      runOnUiThread {
        try {
          push(JSONObject().put("type", type).put("data", Bridge.asObject(body)))
        } catch (e: Exception) {
          Log.w("Jarvis", "réponse $type illisible", e)
        }
      }
    }

    @JavascriptInterface
    fun command(line: String) {
      val cmd = line.trim()
      if (cmd.isEmpty()) return
      net.execute {
        val data: JSONObject = try {
          Bridge.asObject(Bridge.command(this@ChatActivity, cmd))
        } catch (e: Exception) {
          JSONObject().put("ok", false).put("kind", "note").put("text", "La commande n'a pas repondu (${e.message})")
        }
        runOnUiThread { push(JSONObject().put("type", "command").put("data", data)) }
      }
    }

    @JavascriptInterface
    fun approve() {
      net.execute {
        val data: JSONObject = try {
          Bridge.asObject(Bridge.approve(this@ChatActivity))
        } catch (e: Exception) {
          JSONObject().put("ok", false).put("text", "Approbation non transmise (${e.message})")
        }
        runOnUiThread { push(JSONObject().put("type", "approveResult").put("data", data)) }
      }
    }

    /** La demande en attente, seule, sans les cinq autres routes : le compte a rebours vit. */
    @JavascriptInterface
    fun approval() {
      net.execute {
        try {
          pushJsonUi("approval", Bridge.approval(this@ChatActivity))
        } catch (e: Exception) {
          Log.w("LA", "approval introuvable", e)
        }
      }
    }

    @JavascriptInterface
    fun speak(text: String) {
      val t = text.trim()
      if (t.isEmpty()) return
      net.execute {
        try {
          val o = Bridge.asObject(Bridge.speak(this@ChatActivity, t))
          val a = o.optString("audio", "")
          if (a.isNotEmpty()) runOnUiThread { Speaker.enqueue(this@ChatActivity, a) }
        } catch (e: Exception) { Log.w("Jarvis", "lecture de la phrase", e) }
      }
    }

    @JavascriptInterface
    fun approvalListen(ms: Int) {
      net.execute {
        val wav = Clip.recordWav(this@ChatActivity, if (ms in 1000..15000) ms else 6000)
        if (wav == null) {
          runOnUiThread { push(JSONObject().put("type", "heard").put("text", "").put("error", "micro")) }
          return@execute
        }
        val text = try {
          JSONObject(Bridge.hear(this@ChatActivity, wav, "audio/wav")).optString("text", "")
        } catch (e: Exception) { "" }
        runOnUiThread { push(JSONObject().put("type", "heard").put("text", text)) }
      }
    }

    @JavascriptInterface
    fun setWake(on: Boolean) = runOnUiThread { this@ChatActivity.setWake(on) }

    @JavascriptInterface
    fun deny() {
      net.execute {
        try { Bridge.deny(this@ChatActivity) } catch (e: Exception) { }
        runOnUiThread { push(JSONObject().put("type", "approveResult").put("data", JSONObject().put("ok", true).put("text", "Demande refusee"))) }
      }
    }

    @JavascriptInterface
    fun appVersion() {
      val v = try {
        @Suppress("DEPRECATION")
        val pi = this@ChatActivity.packageManager.getPackageInfo(this@ChatActivity.packageName, 0)
        @Suppress("DEPRECATION")
        pi.versionName ?: "?"
      } catch (e: Exception) { "?" }
      runOnUiThread { push(JSONObject().put("type", "version").put("version", v)) }
    }

    @JavascriptInterface
    fun updateApp() {
      net.execute {
        try {
          runOnUiThread { push(JSONObject().put("type", "update").put("state", "download")) }
          val f = Bridge.downloadApk(this@ChatActivity)
          val uri = FileProvider.getUriForFile(this@ChatActivity, this@ChatActivity.packageName + ".files", f)
          runOnUiThread {
            push(JSONObject().put("type", "update").put("state", "ready"))
            val i = Intent(Intent.ACTION_VIEW).apply {
              setDataAndType(uri, "application/vnd.android.package-archive")
              addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            try {
              this@ChatActivity.startActivity(i)
            } catch (e: Exception) {
              push(JSONObject().put("type", "error").put("message", "Installeur indisponible : autorise l installation d applis inconnues pour LA."))
            }
          }
        } catch (e: Exception) {
          runOnUiThread { push(JSONObject().put("type", "error").put("message", "Telechargement de la MAJ echoue (${e.message})")) }
        }
      }
    }

    @JavascriptInterface
    fun takeEngine(alias: String) = TurnEngine.take(this@ChatActivity, alias)

    @JavascriptInterface
    fun setAddress(url: String) {
      Bridge.setAddress(this@ChatActivity, url)
      push(stateJson())
      TurnEngine.ping(this@ChatActivity)
    }

    @JavascriptInterface
    fun setFallback(on: Boolean) {
      Bridge.setFallback(this@ChatActivity, on)
      push(stateJson())
    }

    @JavascriptInterface
    fun jarvisMode(on: Boolean) {
      Bridge.prefs(this@ChatActivity).edit().putBoolean("jarvis", on).apply()
      runOnUiThread {
        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
      }
      push(stateJson())
    }

    @JavascriptInterface
    fun startService() {
      // API 34 : un service d'avant-plan de type microphone exige le micro accordé.
      if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
        runOnUiThread {
          pendingAction = { startJarvisService() }
          requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQ_MIC)
        }
        return
      }
      startJarvisService()
    }

    private fun startJarvisService() {
      val i = Intent(this@ChatActivity, JarvisService::class.java)
      if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
      push(stateJson())
    }

    @JavascriptInterface
    fun stopService() {
      stopService(Intent(this@ChatActivity, JarvisService::class.java))
      push(stateJson())
    }

    @JavascriptInterface
    fun overlaySettings() {
      val i = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
      try {
        startActivity(i)
      } catch (e: Exception) {
        push(JSONObject().put("type", "error").put("message", "Réglage d'overlay indisponible"))
      }
    }

    @JavascriptInterface
    fun appSettings() {
      try {
        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
      } catch (e: Exception) {
        push(JSONObject().put("type", "error").put("message", "Réglages de l'app indisponibles"))
      }
    }

    @JavascriptInterface
    fun playAudio(name: String) {
      Speaker.enqueue(this@ChatActivity, name)
    }

    @JavascriptInterface
    fun pickImage() = runOnUiThread { chooseImage() }

    @JavascriptInterface
    fun takePhoto() = runOnUiThread { shootPhoto() }

    @JavascriptInterface
    fun vibrate(ms: Int) = buzz(ms)
  }

  // ------------------------------------------------------------------ photos

  private fun chooseImage() {
    val i = Intent(Intent.ACTION_GET_CONTENT).apply {
      type = "image/*"
      addCategory(Intent.CATEGORY_OPENABLE)
    }
    try {
      startActivityForResult(Intent.createChooser(i, "Choisir une image"), REQ_PICK)
    } catch (e: Exception) {
      push(JSONObject().put("type", "error").put("message", "Aucune galerie disponible"))
    }
  }

  private fun shootPhoto() {
    val dir = File(cacheDir, "photos").apply { mkdirs() }
    val f = File(dir, "photo-${System.currentTimeMillis()}.jpg")
    val uri = FileProvider.getUriForFile(this, "$packageName.files", f)
    photoUri = uri
    val i = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
      putExtra(MediaStore.EXTRA_OUTPUT, uri)
      addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
    }
    try {
      startActivityForResult(i, REQ_PHOTO)
    } catch (e: Exception) {
      photoUri = null
      push(JSONObject().put("type", "error").put("message", "Aucune application photo"))
    }
  }

  @Deprecated("startActivityForResult reste suffisant ici, sans dépendance de plus")
  override fun onActivityResult(request: Int, result: Int, data: Intent?) {
    super.onActivityResult(request, result, data)
    if (result != RESULT_OK) {
      photoUri = null
      return
    }
    val uri: Uri? = when (request) {
      REQ_PICK -> data?.data
      REQ_PHOTO -> photoUri
      else -> null
    }
    if (uri == null) return
    if (request == REQ_PHOTO) photoUri = null
    sendImage(uri)
  }

  private fun sendImage(uri: Uri) {
    val ctx = applicationContext
    push(JSONObject().put("type", "user").put("text", "📷 Photo").put("kind", "image"))
    net.execute {
      try {
        val mime = contentResolver.getType(uri) ?: "image/jpeg"
        val bytes = contentResolver.openInputStream(uri)?.use { Bridge.readBytes(it) }
        if (bytes == null || bytes.isEmpty()) {
          push(JSONObject().put("type", "error").put("message", "Image illisible"))
        } else {
          TurnEngine.sendImage(ctx, bytes, mime)
        }
      } catch (e: Exception) {
        push(JSONObject().put("type", "error").put("message", "Image illisible : ${e.message}"))
      }
    }
  }

  // ------------------------------------------------------------------ gestes et cycle de vie

  @Suppress("DEPRECATION")
  @Volatile private var wakeWanted = false
  private var wakeThread: Thread? = null

  /** Option « mot d'éveil » : tant que l'ecran est devant, on ecoute « jarvis / agent one ». */
  fun setWake(on: Boolean) {
    wakeWanted = on
    if (on) startWake()
    ear(on)
  }

  /** Le meme geste ouvre l'oreille de la machine : le bouton est ici, l'ecoute est la-bas. */
  private fun ear(on: Boolean) {
    Thread {
      try { Bridge.command(this, "tool engine.residents op=" + if (on) "listen-on" else "listen-off") }
      catch (e: Exception) { }
    }.also { it.isDaemon = true; it.start() }
  }

  private fun startWake() {
    if (wakeThread?.isAlive == true) return
    wakeThread = Thread {
      while (wakeWanted && visible) {
        try {
          if (recorder.isRecording() || TurnEngine.running) { Thread.sleep(700); continue }
          val wav = Clip.recordWav(this, 2200)
          if (wav == null) { Thread.sleep(500); continue }
          val text = try { JSONObject(Bridge.hear(this, wav, "audio/wav")).optString("text", "") } catch (e: Exception) { "" }
          if (text.isNotEmpty() && isWakeWord(text)) {
            runOnUiThread { JsApi().startVoice(); push(JSONObject().put("type", "wake")) }
            Thread.sleep(4000)
          }
        } catch (e: Exception) { try { Thread.sleep(900) } catch (e2: Exception) {} }
      }
    }.also { it.isDaemon = true; it.start() }
  }

  private fun norm(s: String): String {
    val n = java.text.Normalizer.normalize(s.lowercase(), java.text.Normalizer.Form.NFD)
    return n.replace(Regex("\\p{M}+"), "").replace(Regex("[^a-z ]"), "").trim().replace(Regex("\\s+"), " ")
  }
  private fun lev(a: String, b: String): Int {
    val m = a.length; val n = b.length
    val d = Array(m + 1) { IntArray(n + 1) }
    for (i in 0..m) d[i][0] = i
    for (j in 0..n) d[0][j] = j
    for (i in 1..m) for (j in 1..n)
      d[i][j] = minOf(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + if (a[i-1] == b[j-1]) 0 else 1)
    return d[m][n]
  }
  private fun sim(a: String, b: String): Double {
    val m = maxOf(a.length, b.length); if (m == 0) return 1.0
    return 1.0 - lev(a, b).toDouble() / m
  }
  private fun isWakeWord(t: String): Boolean {
    val n = norm(t).replace(" ", "")
    if (n.isEmpty()) return false
    if (Regex("agent(one|ou|un|une|on)").containsMatchIn(n)) return true
    for (c in listOf("jarvis", "agentone", "ecoute", "heyjarvis")) {
      if (n.contains(c)) return true
      if (n.length >= 4 && sim(n, c) >= 0.62) return true
    }
    return false
  }

  private fun buzz(ms: Int) {
    try {
      val v = if (Build.VERSION.SDK_INT >= 31) {
        (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
      } else {
        getSystemService(VIBRATOR_SERVICE) as Vibrator
      }
      if (v.hasVibrator()) v.vibrate(VibrationEffect.createOneShot(ms.toLong(), VibrationEffect.DEFAULT_AMPLITUDE))
    } catch (e: Exception) {
      Log.w("Jarvis", "vibration refusée", e)
    }
  }

  override fun onNewIntent(intent: Intent?) {
    super.onNewIntent(intent)
    if (intent?.getBooleanExtra("record", false) == true) {
      runOnUiThread { JsApi().startVoice() }
    }
  }

  override fun onResume() {
    super.onResume()
    visible = true
    if (wakeWanted) startWake()
    if (::web.isInitialized) push(stateJson())
    // Retour des réglages d'overlay : la bulle peut maintenant se poser.
    if (JarvisService.running && Settings.canDrawOverlays(this)) {
      try {
        startService(Intent(this, JarvisService::class.java).setAction(JarvisService.ACTION_REFRESH))
      } catch (e: Exception) {
        Log.w("Jarvis", "rafraîchissement de la bulle refusé", e)
      }
    }
  }

  override fun onPause() {
    visible = false
    super.onPause()
  }

  override fun onDestroy() {
    dead = true
    TurnEngine.removeListener(turnListener)
    Speaker.removeListener(audioListener)
    recorder.cancel()
    if (::web.isInitialized) {
      web.removeJavascriptInterface("Android")
      web.destroy()
    }
    super.onDestroy()
  }

  companion object {
    private const val REQ_STARTUP = 10
    private const val REQ_MIC = 11
    private const val REQ_PICK = 41
    private const val REQ_PHOTO = 42

    /** L'écran est-il devant ? La bulle s'en sert pour compter les réponses non lues. */
    @Volatile var visible = false
      private set
  }
}
