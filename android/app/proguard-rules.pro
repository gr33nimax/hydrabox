# Keep file present so release minification/shrinking has an explicit project rules file.
# Consumer rules from bundled AARs are still applied automatically.
-keep class go.HydraNativeLoader { *; }

# gomobile registers this API through JNI. Keep the generated class and native
# method names stable in every minified verification/release build.
-keep class io.nekohasekai.libbox.Libbox { *; }
-keep class go.Seq { *; }
-keep class go.Universe { *; }
