# Keep OkHttp classes for UCrop (used by image_cropper)
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**

# Espressif Provisioning Library
-keep class com.espressif.provisioning.** { *; }
-keep interface com.espressif.provisioning.** { *; }

# Protocol Buffers
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
  <fields>;
  <methods>;
}

# Security classes
-keep class com.espressif.provisioning.security.** { *; }
-keep class com.espressif.provisioning.transport.** { *; }
-keep class com.espressif.provisioning.Session { *; }
-keep class com.espressif.provisioning.Session$** { *; }

# EventBus
-keepclassmembers class ** {
    @org.greenrobot.eventbus.Subscribe <methods>;
}
-keep enum org.greenrobot.eventbus.ThreadMode { *; }

# BLE
-keep class android.bluetooth.** { *; }