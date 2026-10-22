package fr.la.chat

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * Le tour : une demande part, le journal et le raisonnement sont sondés pendant qu'il tourne,
 * puis la réponse et ses wav reviennent. Un seul tour à la fois — deux tours écriraient la
 * même base sur le poste.
 *
 * Le pont n'a pas de route de flux : /journal, /thinking et /spoken sont les seules sources
 * vivantes, et elles repartent à zéro à chaque tour.
 */
object TurnEngine {

  private const val TAG = "Jarvis"

  private val exec = Executors.newSingleThreadExecutor { r -> Thread(r, "jarvis-turn").apply { isDaemon = true } }
  private val poller = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "jarvis-poll").apply { isDaemon = true } }
  private val main = Handler(Looper.getMainLooper())
  private val listeners = CopyOnWriteArrayList<(JSONObject) -> Unit>()

  @Volatile var running = false
    private set

  private var generation = 0
  private var pollFuture: ScheduledFuture<*>? = null
  private var lastTools = ""
  private var lastThinking = ""

  fun addListener(l: (JSONObject) -> Unit) {
    listeners.addIfAbsent(l)
  }

  fun removeListener(l: (JSONObject) -> Unit) {
    listeners.remove(l)
  }

  private fun emit(o: JSONObject) {
    main.post {
      for (l in listeners) {
        try {
          l(o)
        } catch (e: Exception) {
          Log.w(TAG, "écouteur d'événement en échec", e)
        }
      }
    }
  }

  fun sendText(c: Context, text: String) {
    if (text.isBlank()) return
    start(c, "text", text, "/user_say", text.toByteArray(Charsets.UTF_8), "text/plain; charset=utf-8")
  }

  fun sendVoice(c: Context, audio: ByteArray, mime: String = "audio/mp4") {
    if (audio.isEmpty()) {
      emit(err("Enregistrement vide"))
      return
    }
    start(c, "voice", null, "/user_voice", audio, mime)
  }

  fun sendImage(c: Context, img: ByteArray, mime: String) {
    if (img.isEmpty()) {
      emit(err("Image vide"))
      return
    }
    start(c, "image", null, "/image", img, mime)
  }

  /** /stop pose un mot côté poste : le sommeil du tour le voit. Il ne tue rien. */
  fun stopTurn(c: Context) {
    Speaker.stop()
    exec.execute {
      try {
        Bridge.stop(c)
        emit(JSONObject().put("type", "stopped"))
      } catch (e: Exception) {
        emit(err("Arrêt non transmis : ${e.message}"))
      }
    }
  }

  private fun start(
    c: Context,
    mode: String,
    userText: String?,
    route: String,
    body: ByteArray,
    mime: String
  ) {
    if (running) {
      emit(err("Un tour tourne déjà"))
      return
    }
    running = true
    lastTools = ""
    lastThinking = ""
    val ctx = c.applicationContext
    val mine = ++generation

    emit(JSONObject().put("type", "turnStart").put("mode", mode).put("text", userText ?: ""))

    Speaker.beginTurn(ctx)
    startPolling(ctx, mine)

    exec.execute {
      try {
        val raw = when (route) {
          "/user_say" -> Bridge.say(ctx, String(body, Charsets.UTF_8))
          "/user_voice" -> Bridge.voice(ctx, body, mime)
          else -> Bridge.image(ctx, body, mime)
        }
        val o = Bridge.asObject(raw)
        val audios = ArrayList<String>()
        o.optJSONArray("audios")?.let { a ->
          for (i in 0 until a.length()) {
            val n = a.optString(i, "")
            if (n.isNotEmpty()) audios.add(n)
          }
        }
        if (audios.isEmpty()) {
          val last = o.optString("audio", "")
          if (last.isNotEmpty()) audios.add(last)
        }
        val event = JSONObject()
          .put("type", "turn")
          .put("mode", mode)
          .put("request", o.optString("request", ""))
          .put("response", o.optString("response", ""))
          .put("code", o.optInt("code", 0))
          .put("queued", o.optBoolean("queued", false))
          .put("audio", o.optString("audio", ""))
          .put("audios", JSONArray(audios))
        if (o.optBoolean("queued", false)) {
          event.put("note", o.optString("note", ""))
        }
        emit(event)

        Speaker.endTurn()
        audios.forEach { Speaker.enqueue(ctx, it) }
      } catch (e: Exception) {
        Log.w(TAG, "tour en échec", e)
        Speaker.endTurn()
        emit(err(humanError(e)))
      } finally {
        running = false
        pollFuture?.cancel(false)
        pollFuture = null
      }
    }
  }

  private fun startPolling(ctx: Context, mine: Int) {
    pollFuture?.cancel(false)
    pollFuture = poller.scheduleWithFixedDelay({
      if (mine != generation) return@scheduleWithFixedDelay
      try {
        val tools = Bridge.lines(ctx, "/journal")
        val tj = tools.joinToString("\u0001")
        if (tj != lastTools) {
          lastTools = tj
          emit(JSONObject().put("type", "tools").put("items", JSONArray(tools)))
        }
        val think = Bridge.lines(ctx, "/thinking")
        val kj = think.joinToString("\u0001")
        if (kj != lastThinking) {
          lastThinking = kj
          emit(JSONObject().put("type", "thinking").put("items", JSONArray(think)))
        }
      } catch (e: Exception) {
        // pendant un tour, une lecture manquée n'arrête rien : le prochain pas réessaie
        Log.w(TAG, "sondage du tour manqué", e)
      }
    }, 400, 900, TimeUnit.MILLISECONDS)
  }

  fun ping(c: Context) {
    val ctx = c.applicationContext
    exec.execute {
      try {
        val o = Bridge.asObject(Bridge.get(ctx, "/ping"))
        emit(
          JSONObject()
            .put("type", "ping")
            .put("online", true)
            .put("address", o.optString("address", ""))
            .put("loop", o.optString("loop", ""))
            .put("ts", o.optString("ts", ""))
            .put("target", Bridge.address(ctx))
            .put("expired", Bridge.certExpired(ctx))
        )
      } catch (e: Exception) {
        emit(
          JSONObject()
            .put("type", "ping")
            .put("online", false)
            .put("target", Bridge.address(ctx))
            .put("expired", Bridge.certExpired(ctx))
            .put("message", humanError(e))
        )
      }
    }
  }

  fun engines(c: Context) {
    val ctx = c.applicationContext
    exec.execute {
      try {
        val items = JSONArray()
        for (e in Bridge.engines(ctx)) {
          items.put(JSONObject().put("alias", e.alias).put("model", e.model).put("active", e.active))
        }
        emit(JSONObject().put("type", "engines").put("items", items))
      } catch (e: Exception) {
        emit(err(humanError(e)))
      }
    }
  }

  fun take(c: Context, alias: String) {
    val ctx = c.applicationContext
    exec.execute {
      try {
        val raw = Bridge.take(ctx, alias)
        val refused = Bridge.field(raw, "showError")
        if (refused.isNotEmpty()) emit(err("Adresse refusée : $refused"))
        else emit(JSONObject().put("type", "engine").put("alias", alias))
        engines(ctx)
      } catch (e: Exception) {
        emit(err(humanError(e)))
      }
    }
  }

  fun plan(c: Context) {
    val ctx = c.applicationContext
    exec.execute {
      try {
        val o = Bridge.asObject(Bridge.get(ctx, "/plan"))
        val text = o.optString("plan", o.optString("result", ""))
        emit(JSONObject().put("type", "plan").put("text", text))
      } catch (e: Exception) {
        emit(err(humanError(e)))
      }
    }
  }

  private fun err(message: String) = JSONObject().put("type", "error").put("message", message)

  private fun humanError(e: Exception): String {
    val m = e.message ?: e.javaClass.simpleName
    return "Le poste n'a pas répondu ($m). Vérifie Tailscale et l'adresse du pont."
  }
}
