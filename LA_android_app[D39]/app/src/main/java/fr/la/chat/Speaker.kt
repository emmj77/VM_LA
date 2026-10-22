package fr.la.chat

import android.annotation.SuppressLint
import android.content.Context
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.util.ArrayDeque
import java.util.concurrent.Executors

/**
 * La voix du poste, jouée en local, au fil du tour.
 *
 * MediaPlayer ne peut pas lire l'adresse https du poste (pile réseau du système, donc pas le
 * vérificateur épinglé) : chaque wav est téléchargé par Bridge, puis joué depuis le cache.
 * Les noms sont relus sous /spoken pendant le tour : le tour s'entend au fur et à mesure.
 */
@SuppressLint("StaticFieldLeak") // ctx est TOUJOURS applicationContext, jamais une activité
object Speaker {

  private val main = Handler(Looper.getMainLooper())
  private val net = Executors.newSingleThreadExecutor { r -> Thread(r, "jarvis-audio").apply { isDaemon = true } }

  private val queue = ArrayDeque<String>()
  private val heard = HashSet<String>()
  private var player: MediaPlayer? = null
  private var current: File? = null
  private var generation = 0
  @Volatile private var turnOpen = false
  private var hadTurn = false
  private var idleSent = true
  private var polling = false
  /** Événements poussés vers l'UI : {"type":"playing"|"idle"} et {"type":"speaking","on":bool}. */
  private val listeners = java.util.concurrent.CopyOnWriteArrayList<(JSONObject) -> Unit>()

  fun addListener(l: (JSONObject) -> Unit) {
    listeners.addIfAbsent(l)
  }

  fun removeListener(l: (JSONObject) -> Unit) {
    listeners.remove(l)
  }

  private var ctx: Context? = null

  private val poll = object : Runnable {
    override fun run() {
      val c = ctx ?: return
      if (!turnOpen) return
      net.execute {
        val names = Bridge.spoken(c)
        main.post {
          names.forEach { enqueue(c, it) }
          if (turnOpen) main.postDelayed(this, 700)
        }
      }
    }
  }

  fun beginTurn(c: Context) {
    val app = c.applicationContext
    main.post {
      ctx = app
      queue.clear()
      heard.clear()
      turnOpen = true
      hadTurn = true
      idleSent = true
      if (!polling) {
        polling = true
        main.removeCallbacks(poll)
        main.postDelayed(poll, 700)
      }
      emit("playing")
    }
  }

  fun endTurn() {
    turnOpen = false
    main.removeCallbacks(poll)
    polling = false
    maybeIdle()
  }

  fun enqueue(c: Context, name: String) {
    if (name.isEmpty()) return
    ctx = c.applicationContext
    main.post {
      if (!heard.add(name)) return@post
      queue.addLast(name)
      playNext()
    }
  }

  fun enqueueAll(c: Context, names: List<String>) {
    names.forEach { enqueue(c, it) }
  }

  private fun playNext() {
    if (player != null) return
    val c = ctx
    if (c == null) return
    val name = queue.pollFirst() ?: run { maybeIdle(); return }
    val mine = ++generation
    net.execute {
      try {
        val file = Bridge.audioFile(c, name)
        main.post {
          if (mine != generation) {
            file.delete()
            return@post
          }
          playFile(file)
        }
      } catch (e: Exception) {
        Log.w("Jarvis", "wav $name non téléchargé : ${e.message}")
        main.post { if (mine == generation) playNext() }
      }
    }
  }

  private fun playFile(file: File) {
    try {
      val p = MediaPlayer()
      player = p
      current = file
      p.setAudioAttributes(
        android.media.AudioAttributes.Builder()
          .setUsage(android.media.AudioAttributes.USAGE_ASSISTANT)
          .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH)
          .build()
      )
      p.setDataSource(file.absolutePath)
      p.setOnPreparedListener { it.start(); idleSent = false; emitSpeak(true) }
      p.setOnCompletionListener { releasePlayer(); playNext() }
      p.setOnErrorListener { _, what, extra ->
        Log.w("Jarvis", "lecteur : what=$what extra=$extra")
        releasePlayer()
        playNext()
        true
      }
      p.prepareAsync()
    } catch (e: Exception) {
      Log.w("Jarvis", "lecture impossible : ${e.message}")
      releasePlayer()
      playNext()
    }
  }

  private fun releasePlayer() {
    player?.let {
      try {
        it.release()
      } catch (e: Exception) {
        Log.w("Jarvis", "libération du lecteur refusée", e)
      }
    }
    player = null
    current?.delete()
    current = null
  }

  /** L'UI n'apprend le silence qu'une fois, 400 ms après le dernier wav. */
  private fun maybeIdle() {
    main.postDelayed({
      if (player == null && queue.isEmpty() && !idleSent) {
        idleSent = true
        emit("idle")
        emitSpeak(false)
      }
    }, 400)
  }

  /** Arrêt demandé : le tour est interrompu, la file se vide, un téléchargement en vol est perdu. */
  fun stop() {
    generation++
    queue.clear()
    main.post {
      releasePlayer()
      idleSent = true
      emitSpeak(false)
    }
  }

  fun isPlaying(): Boolean = player != null || queue.isNotEmpty()

  private fun emit(type: String) {
    val o = JSONObject().put("type", type)
    listeners.forEach { it(o) }
  }

  /** La parole commence / s'arrête : alimente la pastille « Agent One parle ». */
  private fun emitSpeak(on: Boolean) {
    val o = JSONObject().put("type", "speaking").put("on", on)
    listeners.forEach { it(o) }
  }
}
