import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

// Structural guard; a device test is still needed for VK's live page.
const source = readFileSync(new URL("../platform/android/src/androidMain/kotlin/io/hydrabox/platform/android/ChallengeOverlay.kt", import.meta.url), "utf8");
assert.ok(!/update\s*=\s*\{[\s\S]*?loadUrl\(/.test(source),
    "recomposition must not reload the captcha after a redirect or form submission");
assert.equal((source.match(/loadUrl\(challenge\.url\)/g) ?? []).length, 1,
    "load the challenge once per WebView; retry and challenge identity own recreation");
assert.ok(source.includes("CircularProgressIndicator("),
    "show a visible loading indicator while the page is blank");
assert.ok(source.indexOf("if (loading) {", source.indexOf("val reason = failure")) > source.indexOf("AndroidView("),
    "loading content must follow the WebView as an overlay, not resize it from above");
console.log("captcha overlay structural checks passed");
