package org.transmutation.ml

import java.io.File

class ModelLoader {
    @JvmStatic
    fun loadWeights(path: String): Map<String, Float> {
        val file = File(path)
        if (!file.exists()) return emptyMap()
        println("Kotlin loading: $path")
        return mapOf("weight_1" to 0.5f)
    }
}