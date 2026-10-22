package fr.la.chat

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.cert.Certificate
import java.security.cert.CertificateExpiredException
import java.security.cert.CertificateFactory
import java.security.cert.CertificateNotYetValidException
import java.security.cert.X509Certificate
import javax.net.ssl.HttpsURLConnection

/**
 * Le pont vu du téléphone : un client léger, sans modèle ni clé.
 *
 * Le certificat auto-signé du poste est épinglé : la vérification de nom est remplacée par la
 * comparaison du certificat reçu à celui embarqué dans res/raw/bridge_cert. Le nom (CN=LA) ne
 * peut pas correspondre à l'IP appelée ; exiger le certificat est le contrôle qui compte.
 */
object Bridge {

  const val PREFS = "la"
  const val KEY_URL = "url"
  const val KEY_STATE = "state"
  const val KEY_FALLBACK = "fallback"

  // Adresse du poste dans le réseau Tailscale (fixe, traverse le NAT de l'opérateur).
  const val DEFAULT_URL = "https://100.66.81.33:8766"

  private const val TAG = "Jarvis"
  private const val CONNECT_MS = 6000
  private const val READ_MS = 180_000

  @Volatile private var pinned: Certificate? = null

  fun prefs(c: Context): SharedPreferences = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  fun normalize(raw: String): String {
    var u = raw.trim()
    if (u.isEmpty()) return DEFAULT_URL
    if (!u.startsWith("http://") && !u.startsWith("https://")) u = "https://$u"
    while (u.endsWith("/")) u = u.dropLast(1)
    return u
  }

  fun address(c: Context): String {
    val u = prefs(c).getString(KEY_URL, DEFAULT_URL) ?: DEFAULT_URL
    return normalize(u)
  }

  fun setAddress(c: Context, url: String) {
    prefs(c).edit().putString(KEY_URL, normalize(url)).apply()
  }

  fun fallbackEnabled(c: Context): Boolean = prefs(c).getBoolean(KEY_FALLBACK, false)

  fun setFallback(c: Context, on: Boolean) {
    prefs(c).edit().putBoolean(KEY_FALLBACK, on).apply()
  }

  /** Le certificat épinglé, lu une fois. Absent ou illisible = toutes les connexions refusées. */
  fun cert(c: Context): Certificate? {
    pinned?.let { return it }
    return try {
      c.resources.openRawResource(R.raw.bridge_cert).use { input ->
        val x = CertificateFactory.getInstance("X.509").generateCertificate(input)
        pinned = x
        x
      }
    } catch (e: Exception) {
      Log.w(TAG, "certificat épinglé illisible : toutes les connexions seront refusées", e)
      null
    }
  }

  /** Une panne d'expiration se lit comme une panne réseau : on peut au moins la nommer. */
  fun certExpired(c: Context): Boolean {
    val x = cert(c)
    if (x !is X509Certificate) return false
    return try {
      x.checkValidity()
      false
    } catch (e: CertificateExpiredException) {
      true
    } catch (e: CertificateNotYetValidException) {
      Log.w(TAG, "certificat pas encore valide : horloge du téléphone en avance ?")
      false
    } catch (e: Exception) {
      false
    }
  }

  private fun open(c: Context, url: String): HttpURLConnection {
    val h = URL(url).openConnection() as HttpURLConnection
    if (h is HttpsURLConnection) {
      h.hostnameVerifier = javax.net.ssl.HostnameVerifier { _, session ->
        try {
          val chain = session.peerCertificates
          val expected = cert(c)
          chain.isNotEmpty() && expected != null && expected == chain[0]
        } catch (e: Exception) {
          false
        }
      }
    }
    h.connectTimeout = CONNECT_MS
    h.readTimeout = READ_MS
    return h
  }

  class Reply(val code: Int, val payload: String) {
    fun ok() = code < 400
  }

  /** Statut et corps restent séparés : un 500 portant du JSON n'est pas une réponse ordinaire. */
  private fun exchange(c: Context, base: String, route: String, body: ByteArray?, type: String?): Reply {
    val h = open(c, base + route)
    try {
      if (body == null) {
        h.requestMethod = "GET"
      } else {
        h.requestMethod = "POST"
        h.doOutput = true
        h.setRequestProperty("Content-Type", type ?: "application/octet-stream")
        h.setFixedLengthStreamingMode(body.size)
        h.outputStream.use { o: OutputStream ->
          o.write(body)
          o.flush()
        }
      }
      val code = h.responseCode
      val stream: InputStream? = if (code >= 400) h.errorStream else h.inputStream
      val text = if (stream == null) "" else String(readBytes(stream), StandardCharsets.UTF_8)
      return Reply(code, text)
    } finally {
      h.disconnect()
    }
  }

  private fun call(c: Context, base: String, route: String, body: ByteArray?, type: String?): String {
    val r = exchange(c, base, route, body, type)
    if (!r.ok()) throw IOException("le poste a rendu ${r.code}")
    return r.payload
  }

  fun get(c: Context, route: String): String = call(c, address(c), route, null, null)

  fun post(c: Context, route: String, body: ByteArray, type: String): String =
    call(c, address(c), route, body, type)

  fun say(c: Context, text: String): String {
    val body = JSONObject().put("text", text).put("channel", "app").toString()
      .toByteArray(StandardCharsets.UTF_8)
    return turn(c, "/user_say", body, "application/json; charset=utf-8")
  }

  fun voice(c: Context, audio: ByteArray, mime: String): String =
    turn(c, "/user_voice?channel=app", audio, mime)

  fun image(c: Context, img: ByteArray, mime: String): String = turn(c, "/image", img, mime)


  /** Une commande de chat (/new, /stop, /delegate ...) : route /command du pont. */
  fun command(c: Context, line: String): String {
    val body = JSONObject().put("line", line).toString().toByteArray(StandardCharsets.UTF_8)
    return post(c, "/command", body, "application/json")
  }

  /** L'approbation en attente (texte + geste), pour la montrer dans l'app. */
  fun approval(c: Context): String = get(c, "/approval")

  fun approve(c: Context): String = post(c, "/approve", ByteArray(0), "application/json")

  fun deny(c: Context): String = post(c, "/deny", ByteArray(0), "application/json")

  /** Transcrit un court audio (le petit modele capte un mot), SANS lancer de tour. */
  fun hear(c: Context, audio: ByteArray, mime: String): String = post(c, "/transcribe", audio, mime)

  /** Lit une phrase et rend le nom du wav (le haut-parleur le joue). */
  fun speak(c: Context, text: String): String {
    val body = JSONObject().put("text", text).toString().toByteArray(StandardCharsets.UTF_8)
    return post(c, "/voice_text", body, "application/json")
  }

  /** L'APK servie par le poste, telechargee dans le cache pour l'installeur systeme. */
  fun downloadApk(c: Context): File {
    val dir = File(c.cacheDir, "update").apply { mkdirs() }
    val dst = File(dir, "LA-app.apk")
    val h = open(c, address(c) + "/LA-app.apk")
    try {
      if (h.responseCode >= 400) throw IOException("apk ${h.responseCode}")
      h.inputStream.use { input -> FileOutputStream(dst).use { o -> input.copyTo(o, 32 * 1024) } }
      return dst
    } finally {
      h.disconnect()
    }
  }

  /**
   * Un tour, avec le repli d'adresse quand le MOTEUR a échoué (showError contenant "engine").
   * Une panne réseau ne rejoue jamais : elle ne dit pas si le tour a tourné.
   */
  private fun turn(c: Context, route: String, body: ByteArray, type: String): String {
    val base = address(c)
    val first = exchange(c, base, route, body, type)
    if (fallbackEnabled(c) && retryable(first.payload)) {
      for (e in engines(c)) {
        if (e.active && e.alias.isNotEmpty()) {
          val changed = try {
            take(c, e.alias)
          } catch (x: IOException) {
            Log.w(TAG, "repli sur ${e.alias} échoué", x)
            return first.payload
          }
          if (field(changed, "showError").isNotEmpty()) {
            Log.w(TAG, "le poste a refusé le repli sur ${e.alias}")
            return first.payload
          }
          prefs(c).edit().putString(KEY_STATE, "repli sur ${e.alias}").apply()
          return call(c, base, route, body, type)
        }
      }
    }
    if (!first.ok()) throw IOException("le poste a rendu ${first.code}")
    return first.payload
  }

  /** Prendre une adresse : le corps est fabriqué par le parseur, donc échappé. */
  fun take(c: Context, alias: String): String {
    val body = JSONObject().put("alias", alias).toString().toByteArray(StandardCharsets.UTF_8)
    return call(c, address(c), "/engine", body, "application/json")
  }

  class Engine(val alias: String, val model: String, val active: Boolean)

  fun engines(c: Context): List<Engine> {
    val out = ArrayList<Engine>()
    try {
      val j = get(c, "/engine").trim()
      val a: JSONArray? = if (j.startsWith("[")) JSONArray(j) else asObject(j).optJSONArray("engines")
      if (a == null) return out
      for (i in 0 until a.length()) {
        val o = a.optJSONObject(i) ?: continue
        out.add(Engine(o.optString("alias", ""), o.optString("model", ""), o.optBoolean("active", false)))
      }
    } catch (e: Exception) {
      Log.w(TAG, "les adresses du poste sont illisibles", e)
    }
    return out
  }

  /** Les wav du tour en cours, dans l'ordre où ils ont été dits. */
  fun spoken(c: Context): List<String> {
    val out = ArrayList<String>()
    try {
      val j = get(c, "/spoken").trim()
      val a: JSONArray? = if (j.startsWith("[")) JSONArray(j) else asObject(j).optJSONArray("spoken")
      if (a == null) return out
      for (i in 0 until a.length()) {
        val n = a.optString(i, "").trim()
        if (n.isNotEmpty()) out.add(n)
      }
    } catch (e: Exception) {
      Log.w(TAG, "liste /spoken illisible", e)
    }
    return out
  }

  /** Les lignes du journal du tour (tableau JSON de chaînes). */
  fun lines(c: Context, route: String): List<String> {
    val out = ArrayList<String>()
    try {
      val j = get(c, route).trim()
      val a = if (j.startsWith("[")) JSONArray(j) else JSONArray()
      for (i in 0 until a.length()) {
        val s = a.optString(i, "")
        if (s.isNotBlank()) out.add(s)
      }
    } catch (e: Exception) {
      Log.w(TAG, "$route illisible", e)
    }
    return out
  }

  fun stop(c: Context) {
    post(c, "/stop", ByteArray(0), "text/plain")
  }

  /** Le wav est téléchargé PAR LA PORTE QUI ÉPINGLE, puis joué en local. */
  fun audioFile(c: Context, name: String): File {
    val h = open(c, address(c) + "/audio/" + URLEncoder.encode(name, "UTF-8"))
    try {
      if (h.responseCode >= 400) throw IOException("audio ${h.responseCode}")
      val f = File(c.cacheDir, "reply-${System.nanoTime()}.audio")
      h.inputStream.use { input ->
        FileOutputStream(f).use { o -> input.copyTo(o, 16 * 1024) }
      }
      return f
    } finally {
      h.disconnect()
    }
  }

  fun readBytes(input: InputStream): ByteArray {
    input.use { s ->
      ByteArrayOutputStream().use { b ->
        val buf = ByteArray(16 * 1024)
        while (true) {
          val n = s.read(buf)
          if (n == -1) break
          b.write(buf, 0, n)
        }
        return b.toByteArray()
      }
    }
  }

  /** Toute reponse devient un objet : un objet reste tel quel, une liste va sous items, un texte sous text. */
  fun asObject(json: String?): JSONObject {
    val t = (json ?: "").trim()
    if (t.isEmpty()) return JSONObject()
    return try {
      when {
        t.startsWith("{") -> JSONObject(t)
        t.startsWith("[") -> JSONObject().put("items", JSONArray(t))
        else -> JSONObject().put("text", t)
      }
    } catch (e: Exception) {
      JSONObject().put("text", t)
    }
  }

  /** Champ texte d'un objet JSON, "" s'il manque. */
  fun field(json: String?, key: String): String {
    if (json.isNullOrEmpty()) return ""
    return try {
      asObject(json).optString(key, "")
    } catch (e: Exception) {
      ""
    }
  }

  private fun retryable(payload: String): Boolean {
    val e = field(payload, "showError")
    return e.isNotEmpty() && e.lowercase().contains("engine")
  }
}
