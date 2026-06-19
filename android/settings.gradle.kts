pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "SMSForAgents"
include(":app")

// FCM is optional, but the Google Services Gradle plugin requires
// app/google-services.json to exist at configuration time. If you haven't dropped
// in your own Firebase config yet, seed it from the committed placeholder so the
// build still works — push stays off (the phone uses its fallback poll) until you
// replace it with a real file. See android/README.md › "Enable FCM push".
val googleServices = File(rootDir, "app/google-services.json")
if (!googleServices.exists()) {
    File(rootDir, "app/google-services.json.example").copyTo(googleServices)
}
