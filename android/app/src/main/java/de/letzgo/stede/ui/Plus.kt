package de.letzgo.stede.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.android.billingclient.api.*
import de.letzgo.stede.data.Brand
import de.letzgo.stede.data.Feature
import de.letzgo.stede.data.Features
import de.letzgo.stede.data.Store
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Tab-Wechsel aus der Tiefe (Schloss in der Tagesleiste → Plus) — beobachtet von StedeApp. */
object AppNav { var plusRequested by mutableIntStateOf(0) }

/**
 * Baustein `plus` („loog+“) über Google Play: Einmalkauf `<paket>.plus.lifetime` und Monatsabo
 * `<paket>.plus.monthly` — wie PlusStore in iOS. Der heutige Tag ist immer frei; ohne Kauf bleiben
 * Tagesleiste und Kalender auf heute. Der Status kommt von Play, lokal nur zwischengespeichert für den Start.
 */
object PlusStore : PurchasesUpdatedListener {
    private const val KEY = "plus.unlocked"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var client: BillingClient? = null

    var unlocked by mutableStateOf(Store.bool(KEY, false)); private set
    var lifetime by mutableStateOf<ProductDetails?>(null); private set
    var monthly by mutableStateOf<ProductDetails?>(null); private set
    var loading by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null); private set

    /** Ohne den Baustein ist jeder Tag frei. */
    val canChangeDay get() = !Features.has(Feature.Plus) || unlocked

    private fun id(kind: String) = "${Store.context.packageName}.plus.$kind"

    fun start(context: Context) {
        if (!Features.has(Feature.Plus) || client != null) return
        client = BillingClient.newBuilder(context.applicationContext).setListener(this)
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build()).build()
            .also { c ->
                c.startConnection(object : BillingClientStateListener {
                    override fun onBillingSetupFinished(result: BillingResult) { if (result.responseCode == BillingClient.BillingResponseCode.OK) scope.launch { load() } }
                    override fun onBillingServiceDisconnected() {}
                })
            }
    }

    suspend fun load() {
        val c = client ?: return
        loading = true
        runCatching {
            lifetime = c.queryProductDetails(QueryProductDetailsParams.newBuilder().setProductList(listOf(
                QueryProductDetailsParams.Product.newBuilder().setProductId(id("lifetime")).setProductType(BillingClient.ProductType.INAPP).build())).build())
                .productDetailsList?.firstOrNull()
            monthly = c.queryProductDetails(QueryProductDetailsParams.newBuilder().setProductList(listOf(
                QueryProductDetailsParams.Product.newBuilder().setProductId(id("monthly")).setProductType(BillingClient.ProductType.SUBS).build())).build())
                .productDetailsList?.firstOrNull()
        }
        refresh()
        loading = false
    }

    /** Aktive Käufe neu lesen (Erstattung, abgelaufenes Abo, anderes Gerät). */
    suspend fun refresh(): Boolean {
        val c = client ?: return false
        val purchases = runCatching {
            c.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()).purchasesList +
                c.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build()).purchasesList
        }.getOrNull() ?: return unlocked
        purchases.filter { !it.isAcknowledged && it.purchaseState == Purchase.PurchaseState.PURCHASED }.forEach { acknowledge(it) }
        set(purchases.any { p -> p.purchaseState == Purchase.PurchaseState.PURCHASED && p.products.any { it == id("lifetime") || it == id("monthly") } })
        return unlocked
    }

    fun buy(activity: Activity, product: ProductDetails) {
        val c = client ?: return
        error = null
        val params = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(product)
            .apply { product.subscriptionOfferDetails?.firstOrNull()?.offerToken?.let { setOfferToken(it) } }.build()
        val result = c.launchBillingFlow(activity, BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(params)).build())
        if (result.responseCode != BillingClient.BillingResponseCode.OK) error = "Der Kauf konnte nicht gestartet werden."
    }

    fun restore() = scope.launch { error = null; if (!refresh()) error = "Es wurde kein früherer Kauf gefunden." }

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> scope.launch { purchases?.forEach { acknowledge(it) }; refresh() }
            BillingClient.BillingResponseCode.USER_CANCELED -> {}
            else -> error = "Der Kauf konnte nicht abgeschlossen werden."
        }
    }

    private suspend fun acknowledge(p: Purchase) {
        if (p.isAcknowledged || p.purchaseState != Purchase.PurchaseState.PURCHASED) return
        runCatching { client?.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(p.purchaseToken).build()) }
    }

    private fun set(value: Boolean) { unlocked = value; Store.setBool(KEY, value) }
}

private fun Context.activity(): Activity? = when (this) { is Activity -> this; is ContextWrapper -> baseContext.activity(); else -> null }

/** Tab „<App>+“ wie PlusView: Angebote, Status, Wiederherstellen, Rechtliches. */
@Composable
fun PlusScreen() {
    val name = Brand.current.plusName
    val context = LocalContext.current
    val openUrl = rememberOpenUrl()
    LaunchedEffect(Unit) { PlusStore.start(context); PlusStore.load() }
    Scaffold(topBar = { StedeTopBar(name) }, containerColor = C.sand) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            item {
                StedeCard(highlighted = true) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        IconChip(Icons.Default.AutoAwesome, C.teal)
                        Text(name, fontSize = 30.sp, fontWeight = FontWeight.Bold, color = C.text)
                    }
                    Text("Alle Tage statt nur heute", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text, modifier = Modifier.padding(top = 8.dp))
                    Text("Der heutige Tag bleibt immer kostenfrei. Mit $name blätterst du durch beliebige Tage — vor und zurück.", color = C.secondary, modifier = Modifier.padding(top = 4.dp))
                }
            }
            if (PlusStore.unlocked) item {
                StedeCard(highlighted = true) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Default.Verified, null, tint = C.green)
                        Text("$name ist aktiv", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.green)
                    }
                    Text("Danke! Alle Tage sind freigeschaltet.", color = C.secondary, modifier = Modifier.padding(top = 4.dp))
                }
            } else {
                listOfNotNull(PlusStore.lifetime, PlusStore.monthly).forEach { p ->
                    item(key = p.productId) { OfferCard(p) { context.activity()?.let { PlusStore.buy(it, p) } } }
                }
                if (PlusStore.lifetime == null && PlusStore.monthly == null) item {
                    InfoCard(if (PlusStore.loading) "Angebote werden geladen …" else "Die Angebote sind gerade nicht erreichbar.")
                }
            }
            PlusStore.error?.let { item { Text(it, color = C.red, fontSize = 13.sp) } }
            item {
                StedeCard {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Default.Build, null, tint = C.secondary, modifier = Modifier.size(18.dp))
                        Text("Bald in $name", fontWeight = FontWeight.SemiBold, color = C.text)
                    }
                    Text("Weitere Zusatzfunktionen sind in Arbeit. Sie kommen ohne Aufpreis dazu.", color = C.secondary, modifier = Modifier.padding(top = 6.dp))
                }
            }
            if (!PlusStore.unlocked) item {
                TextButton(onClick = { PlusStore.restore() }, Modifier.fillMaxWidth()) { Text("Käufe wiederherstellen", fontWeight = FontWeight.SemiBold, color = C.ink) }
            }
            item {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Brand.current.privacyUrl?.let { url -> Text("Datenschutz", fontSize = 12.sp, color = C.ink, modifier = Modifier.clickable { openUrl(url) }) }
                    Text("$name monatlich läuft einen Monat und verlängert sich automatisch, bis du es in Google Play kündigst. $name einmalig ist ein einmaliger Kauf ohne Laufzeit.",
                        fontSize = 11.sp, color = C.secondary, textAlign = TextAlign.Center)
                }
            }
        }
    }
}

@Composable
private fun OfferCard(p: ProductDetails, buy: () -> Unit) {
    val sub = p.subscriptionOfferDetails?.firstOrNull()?.pricingPhases?.pricingPhaseList?.lastOrNull()
    val price = sub?.let { "${it.formattedPrice}/Monat" } ?: p.oneTimePurchaseOfferDetails?.formattedPrice ?: ""
    StedeCard {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(p.name, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                Text(p.description, color = C.secondary, fontSize = 14.sp)
            }
            Text(price, fontWeight = FontWeight.Bold, fontSize = 18.sp, color = C.text)
        }
        Button(onClick = buy, Modifier.fillMaxWidth().padding(top = 12.dp), shape = RoundedCornerShape(50),
            colors = ButtonDefaults.buttonColors(containerColor = C.deep, contentColor = Color.White)) {
            Text(if (sub != null) "Abo starten" else "Kaufen", fontWeight = FontWeight.SemiBold)
        }
    }
}
