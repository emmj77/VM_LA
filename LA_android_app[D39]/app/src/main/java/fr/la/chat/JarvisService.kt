package fr.la.chat

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Point
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * Le service d'arrière-plan : la bulle flottante, l'écoute quand l'écran change d'application,
 * et le battement /ping qui garde l'état du poste visible dans la notification.
 *
 * Trois gestes, tranchés une fois : toucher ouvre l'application, appui maintenu parle, un
 * mouvement déplace la bulle. Un déplacement n'est pas un clic.
 */
class JarvisService : Service() {

  private lateinit var wm: WindowManager
  private var bubble: LinearLayout? = null
  private var head: FrameLayout? = null
  private var ring: GradientDrawable? = null
  private var badge: TextView? = null
  private var preview: TextView? = null
  private var recorder: Recorder? = null

  private var recording = false
  private var moved = false
  private var unread = 0
  private var lastStatus = ""

  private val h = Handler(Looper.getMainLooper())
  private val net = Executors.newSingleThreadExecutor { r -> Thread(r, "jarvis-service").apply { isDaemon = true } }

  private var x0 = 0f
  private var y0 = 0f
  private var px0 = 0
  private var py0 = 0
  private var trigger: Runnable? = null

  private val turnListener: (JSONObject) -> Unit = { onTurnEvent(it) }
  private val audioListener: (JSONObject) -> Unit = { if (it.optString("type") == "idle") setRing(R.color.ov_ring) }

  private val hidePreview = Runnable {
    preview?.visibility = View.GONE
    clamp()
  }

  private val tick = object : Runnable {
    override fun run() {
      heartbeat()
      h.postDelayed(this, 25_000)
    }
  }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onCreate() {
    super.onCreate()
    running = true
    channel()
    wm = getSystemService(WINDOW_SERVICE) as WindowManager
    recorder = Recorder(this)
    TurnEngine.addListener(turnListener)
    Speaker.addListener(audioListener)
    showBubble()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent?.action == ACTION_STOP) {
      stopSelf()
      return START_NOT_STICKY
    }
    foreground()
    if (intent?.action == ACTION_REFRESH) {
      // L'autorisation d'overlay vient peut-être d'être accordée : on (re)pose la bulle.
      showBubble()
      return START_STICKY
    }
    showBubble()
    h.removeCallbacks(tick)
    h.postDelayed(tick, 1200)
    return START_STICKY
  }

  override fun onDestroy() {
    running = false
    h.removeCallbacksAndMessages(null)
    TurnEngine.removeListener(turnListener)
    Speaker.removeListener(audioListener)
    bubble?.let {
      try {
        wm.removeView(it)
      } catch (e: Exception) {
        Log.w("Jarvis", "retrait de la bulle refusé", e)
      }
    }
    bubble = null
    head = null
    preview = null
    badge = null
    recorder?.cancel()
    recorder = null
    Speaker.stop()
    super.onDestroy()
  }

  // ------------------------------------------------------------------ notification

  private fun channel() {
    val m = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
    m.createNotificationChannel(
      NotificationChannel(CHANNEL, getString(R.string.notif_channel), NotificationManager.IMPORTANCE_LOW)
    )
  }

  private fun notification(text: String): Notification {
    val open = PendingIntent.getActivity(
      this, 1, Intent(this, ChatActivity::class.java),
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    val stop = PendingIntent.getService(
      this, 2, Intent(this, JarvisService::class.java).setAction(ACTION_STOP),
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    return Notification.Builder(this, CHANNEL)
      .setContentTitle(getString(R.string.notif_title))
      .setContentText(text)
      .setSmallIcon(android.R.drawable.ic_btn_speak_now)
      .setOngoing(true)
      .setContentIntent(open)
      .addAction(
        Notification.Action.Builder(
          android.graphics.drawable.Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
          getString(R.string.notif_stop), stop
        ).build()
      )
      .build()
  }

  private fun foreground() {
    val n = notification(getString(R.string.notif_text))
    try {
      if (Build.VERSION.SDK_INT >= 30) {
        startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
      } else {
        startForeground(NOTIF_ID, n)
      }
    } catch (e: Exception) {
      // Micro non accordé ou démarrage refusé : le service reste visible, sans type micro.
      Log.w("Jarvis", "avant-plan microphone refusé", e)
      try {
        startForeground(NOTIF_ID, n)
      } catch (x: Exception) {
        Log.w("Jarvis", "avant-plan impossible", x)
        stopSelf()
      }
    }
  }

  private fun updateNotification(text: String) {
    if (text == lastStatus) return
    lastStatus = text
    try {
      (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIF_ID, notification(text))
    } catch (e: Exception) {
      Log.w("Jarvis", "notification non mise à jour", e)
    }
  }

  /** Le battement : l'état du poste, sans route de flux (le pont n'en a pas). */
  private fun heartbeat() {
    net.execute {
      try {
        Bridge.get(this, "/ping")
        Bridge.prefs(this).edit().putBoolean("up", true).apply()
        updateNotification("En ligne · ${Bridge.address(this)}")
      } catch (e: Exception) {
        Bridge.prefs(this).edit().putBoolean("up", false).apply()
        updateNotification("Injoignable · ${Bridge.address(this)}")
      }
    }
  }

  // ------------------------------------------------------------------ la bulle

  @SuppressLint("ClickableViewAccessibility")
  private fun showBubble() {
    if (bubble != null) return
    if (!Settings.canDrawOverlays(this)) {
      updateNotification("Bulle inactive : autorise l'affichage par-dessus les autres applis")
      return
    }

    val root = LinearLayout(this)
    root.orientation = LinearLayout.VERTICAL
    root.gravity = Gravity.CENTER_HORIZONTAL
    root.contentDescription = getString(R.string.bubble_desc)

    val disc = FrameLayout(this)
    ring = oval(color(R.color.ov_head_bg))
    setRing(R.color.ov_ring)
    disc.background = ring
    root.addView(disc, LinearLayout.LayoutParams(dp(64), dp(64)))

    val mic = ImageView(this)
    mic.setImageResource(R.drawable.ic_mic)
    mic.setColorFilter(color(R.color.ov_text))
    mic.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    disc.addView(mic, FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER))

    badge = TextView(this).apply {
      background = ContextCompat.getDrawable(this@JarvisService, R.drawable.ov_badge)
      setTextColor(0xFF0A0B0F.toInt())
      textSize = 10f
      typeface = Typeface.DEFAULT_BOLD
      gravity = Gravity.CENTER
      visibility = View.GONE
    }
    disc.addView(badge, FrameLayout.LayoutParams(dp(20), dp(20), Gravity.TOP or Gravity.END))
    head = disc

    preview = TextView(this).apply {
      background = ContextCompat.getDrawable(this@JarvisService, R.drawable.ov_bubble_la)
      setTextColor(color(R.color.ov_text))
      textSize = 13f
      maxWidth = dp(240)
      maxLines = 3
      ellipsize = TextUtils.TruncateAt.END
      setPadding(dp(12), dp(8), dp(12), dp(8))
      visibility = View.GONE
    }
    val pv = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
    pv.topMargin = dp(6)
    root.addView(preview, pv)

    val p = WindowManager.LayoutParams(
      WindowManager.LayoutParams.WRAP_CONTENT,
      WindowManager.LayoutParams.WRAP_CONTENT,
      WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
      WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
      PixelFormat.TRANSLUCENT
    )
    p.gravity = Gravity.TOP or Gravity.START
    p.x = dp(22)
    p.y = dp(280)

    root.setOnTouchListener { v, e ->
      when (e.actionMasked) {
        MotionEvent.ACTION_DOWN -> {
          x0 = e.rawX
          y0 = e.rawY
          val pp = root.layoutParams as WindowManager.LayoutParams
          px0 = pp.x
          py0 = pp.y
          recording = false
          moved = false
          trigger = Runnable {
            recording = true
            startRecording()
          }.also { h.postDelayed(it, 400) }
          true
        }

        MotionEvent.ACTION_MOVE -> {
          val dx = e.rawX - x0
          val dy = e.rawY - y0
          if (Math.abs(dx) > dp(12) || Math.abs(dy) > dp(12)) {
            moved = true
            trigger?.let { h.removeCallbacks(it) }
            trigger = null
            if (!recording) {
              val bw = root.width
              val bh = root.height
              if (bw > 0 && bh > 0) {
                val pp = root.layoutParams as WindowManager.LayoutParams
                pp.x = bound(px0 + dx.toInt(), screen().x - bw)
                pp.y = bound(py0 + dy.toInt(), screen().y - bh)
                wm.updateViewLayout(root, pp)
              }
            }
          }
          true
        }

        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
          trigger?.let { h.removeCallbacks(it) }
          trigger = null
          val spoke = recording
          if (recording) {
            recording = false
            sendVoice()
          }
          if (!moved && !spoke && e.actionMasked == MotionEvent.ACTION_UP) v.performClick()
          true
        }

        else -> false
      }
    }

    root.setOnClickListener { openApp() }

    try {
      wm.addView(root, p)
      bubble = root
    } catch (e: Exception) {
      Log.w("Jarvis", "bulle refusée par le système", e)
      bubble = null
    }
  }

  private fun oval(fill: Int) = GradientDrawable().apply {
    shape = GradientDrawable.OVAL
    setColor(fill)
  }

  private fun setRing(res: Int) {
    ring?.setStroke(dp(3), color(res))
  }

  private fun color(res: Int) = ContextCompat.getColor(this, res)

  private fun updateBadge() {
    val b = badge ?: return
    if (unread > 0) {
      b.text = String.format(java.util.Locale.ROOT, "%d", unread.coerceAtMost(9))
      b.visibility = View.VISIBLE
    } else {
      b.visibility = View.GONE
    }
  }

  private fun showPreview(text: String, sticky: Boolean) {
    val p = preview ?: return
    h.removeCallbacks(hidePreview)
    p.text = text
    p.visibility = View.VISIBLE
    clamp()
    if (!sticky) h.postDelayed(hidePreview, 7000)
  }

  private fun clamp() {
    val b = bubble ?: return
    b.post {
      if (bubble == null) return@post
      val bw = b.width
      val bh = b.height
      if (bw <= 0 || bh <= 0) return@post
      val p = b.layoutParams as WindowManager.LayoutParams
      val nx = bound(p.x, screen().x - bw)
      val ny = bound(p.y, screen().y - bh)
      if (nx != p.x || ny != p.y) {
        p.x = nx
        p.y = ny
        wm.updateViewLayout(b, p)
      }
    }
  }

  private fun openApp() {
    val i = Intent(this, ChatActivity::class.java)
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    try {
      startActivity(i)
    } catch (e: Exception) {
      showPreview("Application indisponible", false)
    }
    preview?.visibility = View.GONE
    unread = 0
    updateBadge()
  }

  // ------------------------------------------------------------------ la voix

  private fun startRecording() {
    if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
      setRing(R.color.ov_ring)
      showPreview(getString(R.string.mic_denied), false)
      return
    }
    val err = recorder?.start()
    if (err != null) {
      setRing(R.color.ov_ring)
      showPreview(getString(R.string.mic_failed, err), false)
      return
    }
    setRing(R.color.ov_ring_run)
    showPreview(getString(R.string.listening), true)
  }

  private fun sendVoice() {
    val bytes = recorder?.stop()
    if (bytes == null || bytes.size < 1200) {
      setRing(R.color.ov_ring)
      showPreview(getString(R.string.nothing_recorded), false)
      return
    }
    setRing(R.color.ov_ring_send)
    showPreview(getString(R.string.sending), true)
    TurnEngine.sendVoice(this, bytes)
  }

  private fun onTurnEvent(o: JSONObject) {
    when (o.optString("type")) {
      "turnStart" -> {
        setRing(R.color.ov_ring_send)
        if (preview?.visibility != View.VISIBLE) showPreview(getString(R.string.thinking), true)
      }

      "turn" -> {
        setRing(R.color.ov_ring)
        val r = o.optString("response", "").trim()
        val code = o.optInt("code", 0)
        val text = when {
          o.optBoolean("queued", false) -> "Message mis en file pour le prochain tour"
          r.isEmpty() && code != 0 -> "Le poste a rendu le code $code"
          r.isEmpty() -> "Réponse vide"
          else -> r
        }
        showPreview(text, false)
        if (!ChatActivity.visible) {
          unread++
          updateBadge()
        }
      }

      "error" -> {
        setRing(R.color.ov_ring)
        showPreview(o.optString("message", getString(R.string.station_silent)), false)
      }

      "stopped" -> setRing(R.color.ov_ring)
    }
  }

  // ------------------------------------------------------------------ géométrie

  private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

  private fun screen(): Point {
    if (Build.VERSION.SDK_INT >= 30) {
      val b: Rect = wm.currentWindowMetrics.bounds
      return Point(b.width(), b.height())
    }
    return Point(resources.displayMetrics.widthPixels, resources.displayMetrics.heightPixels)
  }

  private fun bound(v: Int, max: Int): Int = Math.max(0, Math.min(v, Math.max(0, max)))

  companion object {
    const val ACTION_STOP = "fr.la.chat.SERVICE_STOP"
    const val ACTION_REFRESH = "fr.la.chat.SERVICE_REFRESH"
    private const val CHANNEL = "jarvis-bubble"
    private const val NOTIF_ID = 7

    @Volatile var running = false
      private set
  }
}
