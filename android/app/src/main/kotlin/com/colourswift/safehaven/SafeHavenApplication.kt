package com.colourswift.safehaven

import io.flutter.app.FlutterApplication

class SafeHavenApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        CrashLogService.init(this)
    }
}