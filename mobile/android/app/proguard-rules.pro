# R8 keep rules for release builds (isMinifyEnabled = true).
# Anything Android instantiates by name from the manifest, or that is reached
# only through a MethodChannel, must survive shrinking.

# App code: MainActivity (native voice + mic permission bridge) and the
# home-screen widget provider are referenced from the manifest.
-keep class com.aeris.expense.** { *; }

# another_telephony: IncomingSmsReceiver is registered in the manifest and
# runs the background SMS isolate.
-keep class com.shounakmulay.telephony.** { *; }

# home_widget: background intent + widget plumbing.
-keep class es.antonborri.home_widget.** { *; }

# Flutter local notifications uses Gson with reflection for scheduled
# notifications; stripping its generic types breaks rescheduling on boot.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Play Core (deferred components) is referenced by the Flutter embedding but
# not shipped; don't fail the build over it.
-dontwarn com.google.android.play.core.**
