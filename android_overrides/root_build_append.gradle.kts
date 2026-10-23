
// Ép mọi plugin Android build với compileSdk 36 (flutter_blue_plus 1.34 còn để 33).
subprojects {
    val bumpSdk = {
        val ext = extensions.findByName("android")
        if (ext != null && name != "app") {
            ext.javaClass.methods
                .firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
                ?.invoke(ext, 36)
        }
    }
    if (state.executed) bumpSdk() else afterEvaluate { bumpSdk() }
}
