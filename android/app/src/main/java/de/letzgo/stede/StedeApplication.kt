package de.letzgo.stede

import android.app.Application
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import de.letzgo.stede.data.Store

class StedeApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Store.init(this)
        PDFBoxResourceLoader.init(applicationContext)
    }
}
