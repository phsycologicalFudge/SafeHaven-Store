package com.colourswift.safehaven

object EngineNative {
    init {
        System.loadLibrary("safehaven_engine")
    }

    external fun init(baseUrl: String, dataDir: String): Int
    external fun call(method: String, args: String): String
}
