package de.letzgo.stede.data

import android.content.Context
import android.content.SharedPreferences
import java.io.File

/** Dateicache und Einstellungen — Gegenstück zu Application Support und UserDefaults. */
object Store {
    lateinit var context: Context
    lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        this.context = context.applicationContext
        prefs = context.getSharedPreferences("stede", Context.MODE_PRIVATE)
    }

    fun file(folder: String, name: String): File = File(File(context.filesDir, folder).apply { mkdirs() }, name)
    fun read(folder: String, name: String): String? = file(folder, name).takeIf { it.exists() }?.readText()
    fun write(folder: String, name: String, text: String) = file(folder, name).writeText(text)
    fun asset(name: String): String = context.assets.open(name).bufferedReader().use { it.readText() }

    fun string(key: String, default: String) = prefs.getString(key, default) ?: default
    fun setString(key: String, value: String) = prefs.edit().putString(key, value).apply()
    fun int(key: String, default: Int = 0) = prefs.getInt(key, default)
    fun setInt(key: String, value: Int) = prefs.edit().putInt(key, value).apply()
    fun stringSet(key: String): Set<String> = prefs.getStringSet(key, emptySet()) ?: emptySet()
    fun setStringSet(key: String, value: Set<String>) = prefs.edit().putStringSet(key, value).apply()
    fun bool(key: String, default: Boolean) = prefs.getBoolean(key, default)
    fun setBool(key: String, value: Boolean) = prefs.edit().putBoolean(key, value).apply()
}
