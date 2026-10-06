# Flutter's own embedding and plugin registrant are reached reflectively.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# The sqflite/connectivity/signature plugins use platform channels by name.
-keep class androidx.lifecycle.DefaultLifecycleObserver

# Models are serialised by field name via json_serializable-free hand-written
# fromJson, so obfuscation is safe. Keep annotations we read reflectively.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
