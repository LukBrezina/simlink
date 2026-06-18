# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class **$$serializer { *; }
-keepclasseswithmembers class sk.brezinovi.simlink.** {
    *** Companion;
}
-keepclasseswithmembers @kotlinx.serialization.Serializable class sk.brezinovi.simlink.** { *; }

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
