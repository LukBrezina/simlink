plugins {
    id("com.android.application") version "8.7.3" apply false
    // Kotlin 2.3.x: matches the metadata version Hotwire Native 1.2.8 was built with.
    id("org.jetbrains.kotlin.android") version "2.3.0" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.3.0" apply false
}
