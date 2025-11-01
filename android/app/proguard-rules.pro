# Keep ML Kit Text Recognition and Barcode classes (all scripts)
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Keep internal ML Kit vision/common classes
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-dontwarn com.google.android.gms.internal.mlkit_vision_common.**

# Keep internal ML Kit text classes
-keep class com.google.android.gms.internal.mlkit_vision_text.** { *; }
-dontwarn com.google.android.gms.internal.mlkit_vision_text.**

# Keep ML Kit barcode classes
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-dontwarn com.google.android.gms.internal.mlkit_vision_barcode.**
-keep class com.google.mlkit.vision.barcode.** { *; }

# Keep internal ML Kit object detection classes
-keep class com.google.android.gms.internal.mlkit_object_detection.** { *; }
-dontwarn com.google.android.gms.internal.mlkit_object_detection.**
-keep class com.google.android.gms.internal.mlkit_vision_object_detection.** { *; }
-dontwarn com.google.android.gms.internal.mlkit_vision_object_detection.**
-keep class com.google.mlkit.vision.objects.** { *; }

# Keep ODML image classes
-keep class com.google.android.odml.image.** { *; }
-dontwarn com.google.android.odml.image.**

# Keep androidx.camera and zxing (used by some scanners)
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**
-keep class com.google.zxing.** { *; }
-dontwarn com.google.zxing.**

# Prevent obfuscation of MobileScanner generated code paths
-keep class dev.steenbakker.mobile_scanner.** { *; }
-dontwarn dev.steenbakker.mobile_scanner.**
