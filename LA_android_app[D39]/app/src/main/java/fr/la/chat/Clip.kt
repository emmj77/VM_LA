package fr.la.chat

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream

/**
 * Enregistre un court WAV PCM 16 kHz mono (ce que l oreille lit de facon FIABLE, la ou l AAC
 * compresse trop). Sert a la validation vocale et au mot d eveil -- jamais le tour complet.
 */
object Clip {
  fun recordWav(@Suppress("UNUSED_PARAMETER") ctx: Context, ms: Int): ByteArray? {
    val sr = 16000
    val min = AudioRecord.getMinBufferSize(sr, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
    if (min <= 0) return null
    val bufSize = maxOf(min, 4096)
    val rec = try {
      AudioRecord(MediaRecorder.AudioSource.MIC, sr, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufSize)
    } catch (e: Exception) { Log.w("Jarvis", "AudioRecord refuse", e); return null }
    if (rec.state != AudioRecord.STATE_INITIALIZED) { rec.release(); return null }
    val pcm = ByteArrayOutputStream()
    try {
      rec.startRecording()
      val tmp = ByteArray(bufSize)
      val end = System.currentTimeMillis() + ms
      while (System.currentTimeMillis() < end) {
        val n = rec.read(tmp, 0, tmp.size)
        if (n > 0) pcm.write(tmp, 0, n) else if (n < 0) break
      }
    } catch (e: Exception) {
      Log.w("Jarvis", "lecture micro (clip)", e)
    } finally {
      try { rec.stop() } catch (e: Exception) {}
      try { rec.release() } catch (e: Exception) {}
    }
    val data = pcm.toByteArray()
    if (data.isEmpty()) return null
    val out = ByteArrayOutputStream()
    val d = DataOutputStream(out)
    d.writeBytes("RIFF"); d.writeInt(36 + data.size); d.writeBytes("WAVE")
    d.writeBytes("fmt "); d.writeInt(16); d.writeShort(1); d.writeShort(1)
    d.writeInt(sr); d.writeInt(sr * 2); d.writeShort(2); d.writeShort(16)
    d.writeBytes("data"); d.writeInt(data.size); d.write(data)
    d.flush()
    return out.toByteArray()
  }
}
