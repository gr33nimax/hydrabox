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

# javax.lang.model существует только в JDK: ссылки приходят из
# annotation-processor-аннотаций и в APK недостижимы.
-dontwarn javax.lang.model.**

# AndroidJUnitRunner resolves this class before test code starts.
-keep class androidx.tracing.Trace { *; }

# Инструментальные тесты исполняются против минифицированного release-APK
# (testBuildType = "release"). AndroidJUnitRunner и его зависимости обращаются
# к Kotlin stdlib напрямую, поэтому stdlib сохраняется целиком. Размер APK
# определяют нативные библиотеки, вклад stdlib пренебрежим.
-keep class kotlin.** { *; }
