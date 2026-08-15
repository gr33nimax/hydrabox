# Keep file present so release minification/shrinking has an explicit project rules file.
# Consumer rules from bundled AARs are still applied automatically.
-keep class go.HydraNativeLoader { *; }

# Flutter reaches MainActivity through the Android manifest and the generated
# Pigeon setup installs handlers before Dart bootstraps. Keep the complete app
# control plane stable in minified builds; native libraries dominate APK size,
# while losing any of these entry points makes a release-only channel-error.
-keep class io.hydrabox.client.** { *; }

# gomobile registers this API through JNI. Keep the generated class and native
# method names stable in every minified verification/release build.
-keep class io.nekohasekai.libbox.Libbox { *; }
-keep class go.Seq { *; }
-keep class go.Universe { *; }
