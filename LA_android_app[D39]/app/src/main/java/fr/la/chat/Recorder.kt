package fr.la.chat

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import java.io.File

/**
 * Le micro natif : AAC mono 16 kHz dans un m4a, le format que le pont accepte (audio/mp4).
 * Un seul enregistreur à la fois ; toute panne rend un message, jamais un silence.
 */
class Recorder(private val ctx: Context) {

  private var rec: MediaRecorder? = null
  private var file: File? = null
  var startedAt = 0L
    private set

  fun isRecording(): Boolean = rec != null

  fun start(): String? {
    if (rec != null) return null
    val f = File(ctx.cacheDir, "voice.m4a")
    return try {
      val r = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(ctx) else @Suppress("DEPRECATION") MediaRecorder()
      r.setAudioSource(MediaRecorder.AudioSource.MIC)
      r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
      r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
      r.setAudioSamplingRate(16000)
      r.setAudioChannels(1)
      r.setAudioEncodingBitRate(96000)
      r.setOutputFile(f.absolutePath)
      r.prepare()
      r.start()
      rec = r
      file = f
      startedAt = System.currentTimeMillis()
      null
    } catch (e: Exception) {
      Log.w("Jarvis", "micro refusé", e)
      release()
      e.message ?: "micro indisponible"
    }
  }

  /** Rend les octets du tour, ou null si rien n'a été enregistré. */
  fun stop(): ByteArray? {
    val r = rec ?: return null
    val f = file
    rec = null
    var stopped = true
    try {
      r.stop()
    } catch (e: Exception) {
      stopped = false
      Log.w("Jarvis", "arrêt de l'enregistreur refusé", e)
    }
    try {
      r.release()
    } catch (e: Exception) {
      Log.w("Jarvis", "libération de l'enregistreur refusée", e)
    }
    if (!stopped || f == null || !f.exists() || f.length() == 0L) return null
    return try {
      f.readBytes()
    } catch (e: Exception) {
      Log.w("Jarvis", "lecture du m4a impossible", e)
      null
    }
  }

  fun cancel() {
    rec?.let {
      try {
        it.stop()
      } catch (e: Exception) {
        // trop court pour être arrêté proprement : on libère, c'est tout
      }
      try {
        it.release()
      } catch (e: Exception) {
        Log.w("Jarvis", "libération refusée", e)
      }
    }
    rec = null
    file?.delete()
    file = null
  }

  private fun release() {
    try {
      rec?.release()
    } catch (e: Exception) {
      Log.w("Jarvis", "libération refusée", e)
    }
    rec = null
  }
}
