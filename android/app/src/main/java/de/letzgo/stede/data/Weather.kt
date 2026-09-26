package de.letzgo.stede.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

// MARK: Wetter — Bright Sky (DWD), wie WeatherClient in iOS

@Serializable data class WeatherHour(
    val timestamp: String, val precipitation: Double? = null, @SerialName("pressure_msl") val pressure: Double? = null, val sunshine: Double? = null,
    val temperature: Double? = null, @SerialName("wind_direction") val windDirection: Double? = null, @SerialName("wind_speed") val windSpeed: Double? = null,
    @SerialName("cloud_cover") val cloudCover: Double? = null, @SerialName("relative_humidity") val humidity: Double? = null,
    @SerialName("wind_gust_speed") val gust: Double? = null, val condition: String? = null, val icon: String? = null,
) {
    val time: ZonedDateTime get() = Town.parse(timestamp)!!
    val label: String get() = when (condition) {
        "dry" -> when (icon) { "clear-day", "clear-night" -> "Klar"; "partly-cloudy-day", "partly-cloudy-night" -> "Teils bewölkt"; "cloudy" -> "Bewölkt"; else -> "Trocken" }
        "fog" -> "Nebel"; "rain" -> "Regen"; "sleet" -> "Schneeregen"; "snow" -> "Schnee"; "hail" -> "Hagel"; "thunderstorm" -> "Gewitter"
        else -> when (icon) { "clear-day", "clear-night" -> "Klar"; "partly-cloudy-day", "partly-cloudy-night" -> "Teils bewölkt"; "cloudy" -> "Bewölkt"; else -> "Wetter" }
    }
}
@Serializable private data class WeatherSource(@SerialName("station_name") val stationName: String? = null)
@Serializable private data class WeatherResponse(val weather: List<WeatherHour> = emptyList(), val sources: List<WeatherSource> = emptyList())
@Serializable data class WeatherDay(val hours: List<WeatherHour>, val station: String?) {
    val min get() = hours.mapNotNull { it.temperature }.minOrNull()
    val max get() = hours.mapNotNull { it.temperature }.maxOrNull()
    val rain get() = hours.mapNotNull { it.precipitation }.sum()
    fun current(): WeatherHour? { val now = Town.now(); return hours.lastOrNull { !it.time.isAfter(now) } ?: hours.firstOrNull() }
}

object Weather {
    fun cached(day: LocalDate): WeatherDay? = Store.read("weather", "$day.json")?.let { runCatching { Http.json.decodeFromString<WeatherDay>(it) }.getOrNull() }
    suspend fun load(day: LocalDate): WeatherDay {
        val r = Http.json.decodeFromString<WeatherResponse>(Http.text("https://api.brightsky.dev/weather?lat=53.256&lon=7.927&date=$day&tz=Europe/Berlin"))
        val d = WeatherDay(r.weather.filter { Town.parse(it.timestamp)?.toLocalDate() == day }, r.sources.firstOrNull()?.stationName)
        Store.write("weather", "$day.json", Http.json.encodeToString(WeatherDay.serializer(), d))
        return d
    }
}
