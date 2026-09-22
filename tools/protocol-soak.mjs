#!/usr/bin/env node
/**
 * Redacting ADB inventory for the client protocol soak run.
 *
 * It deliberately records only hashes of profile labels: subscription details belong on the
 * device and in the private raw UI dump, never in a report or terminal summary.
 */
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const args = process.argv.slice(2);
const value = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
const out = value("--out", "device-runs/protocol-soak");
const serial = value("--serial", null);
const dryRun = args.includes("--dry-run");
const adbPrefix = serial ? ["-s", serial] : [];
const uiRemote = "/sdcard/hydrabox-protocol-inventory.xml";

const adb = (arguments_, options = {}) => execFileSync(
    "adb",
    [...adbPrefix, ...arguments_],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], ...options },
);
const hash = (value_) => createHash("sha256").update(value_).digest("hex").slice(0, 12);
const writeJson = (name, value_) => writeFileSync(join(out, name), `${JSON.stringify(value_, null, 2)}\n`);
const sleep = (milliseconds) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds);

function dumpUi(localName) {
    const local = join(out, localName);
    adb(["shell", "uiautomator", "dump", uiRemote]);
    adb(["pull", uiRemote, local]);
    return readFileSync(local, "utf8");
}

function awaitServerList() {
    for (let attempt = 0; attempt < 30; attempt += 1) {
        const xml = dumpUi("protocol-inventory.xml");
        if (xml.includes("Измерить задержку")) return xml;
        sleep(300);
    }
    throw new Error("server list did not appear within 9 seconds");
}

function nodes(xml) {
    return [...xml.matchAll(/<node\b([^>]*)>/g)].map((match) => Object.fromEntries(
        [...match[1].matchAll(/([\w-]+)="([^"]*)"/g)].map((attribute) => [attribute[1], attribute[2]]),
    ));
}

function boundsCenter(bounds) {
    const values = [...bounds.matchAll(/\d+/g)].map((value_) => Number(value_[0]));
    return { x: Math.round((values[0] + values[2]) / 2), y: Math.round((values[1] + values[3]) / 2) };
}

function classify(label) {
    const known = ["AnyTLS", "Hysteria", "Naive", "OpenVPN", "Shadowsocks", "Trojan", "TrustTunnel", "TUIC", "VLESS", "VMess", "WireGuard", "AWG", "VK"];
    return known.filter((protocol) => label.toLowerCase().includes(protocol.toLowerCase()));
}

function profileRows(xml) {
    // Server title rows live in the list's left column. Their adjacent latency text is excluded.
    return nodes(xml)
        .filter((node) => node.class === "android.widget.TextView" && node.text && node.bounds)
        .filter((node) => {
            const [left, top] = [...node.bounds.matchAll(/\d+/g)].map((value_) => Number(value_[0]));
            return left === 204 && top >= 500 && top < 2000;
        })
        .map((node, index) => ({
            index,
            labelHash: hash(node.text),
            protocolHints: classify(node.text),
            tap: boundsCenter(node.bounds),
        }));
}

function awaitText(text, timeoutMillis = 15000) {
    const deadline = Date.now() + timeoutMillis;
    while (Date.now() < deadline) {
        const xml = dumpUi(`state-${Date.now()}.xml`);
        if (xml.includes(text)) return true;
        sleep(500);
    }
    return false;
}

function tunCounters() {
    // Samsung denies `ip link` to shell while a VPN is active; /proc/net/dev remains readable.
    const devices = adb(["shell", "cat", "/proc/net/dev"]);
    const row = devices.split("\n").find((line) => /^\s*tun\d*:/.test(line));
    if (!row) return null;
    const values = row.split(/[:\s]+/).filter(Boolean);
    return { name: values[0], rxBytes: Number(values[1]), txBytes: Number(values[9]) };
}

function tunInterfaces() {
    const tun = tunCounters();
    return tun ? [tun.name] : [];
}

function collectPprof(name) {
    try { adb(["forward", "tcp:19091", "tcp:9091"]); } catch { /* existing forward is reusable */ }
    for (const path of ["debug/pprof/", "debug/pprof/goroutine?debug=1", "debug/pprof/heap"]) {
        const safe = path.replaceAll(/[/?=&]/g, "_");
        try {
            const body = execFileSync("curl", ["-fsS", "--max-time", "5", `http://127.0.0.1:19091/${path}`], { stdio: ["ignore", "pipe", "ignore"] });
            writeFileSync(join(out, `${name}-${safe}.pprof`), body);
            writeFileSync(join(out, `${name}-${safe}.status`), "200\n");
        } catch {
            writeFileSync(join(out, `${name}-${safe}.status`), "unavailable\n");
        }
    }
}

function assertVpnMode() {
    adb(["shell", "input", "tap", "900", "2200"]);
    for (let attempt = 0; attempt < 30; attempt += 1) {
        const settings = dumpUi("vpn-mode-preflight.xml");
        if (settings.includes("Локальный прокси вместо системного туннеля")) {
            if (settings.includes("Порт прокси")) throw new Error("proxy-only mode is active; a VPN/TUN matrix would be invalid");
            return;
        }
        sleep(300);
    }
    throw new Error("settings screen did not appear within 9 seconds");
}

function runProfile(index) {
    adb(["shell", "am", "start", "-W", "-n", "io.hydrabox.client/io.hydrabox.platform.android.RuntimeControlActivity"]);
    sleep(300);
    assertVpnMode();
    adb(["shell", "input", "tap", "540", "2200"]);
    awaitServerList();
    // Navigation retains scroll position; make index→row mapping deterministic for every run.
    for (let attempt = 0; attempt < 3; attempt += 1) adb(["shell", "input", "swipe", "540", "700", "540", "1900", "250"]);
    const xml = awaitServerList();
    const profile = profileRows(xml).at(index);
    if (!profile) throw new Error(`profile index ${index} is unavailable`);
    const cycles = Number(value("--cycles", "3"));
    const soakSeconds = Number(value("--soak-seconds", "600"));
    const workloadIntervalSeconds = Number(value("--workload-interval-seconds", "30"));
    const result = { profile, cycles, soakSeconds, workloadIntervalSeconds, connects: [], workload: [], outcome: "inconclusive" };
    const reportName = `profile-${profile.labelHash}.json`;
    const persist = () => writeJson(reportName, result);
    adb(["shell", "input", "tap", String(profile.tap.x), String(profile.tap.y)]);
    sleep(1000);
    adb(["shell", "input", "tap", "170", "2200"]);
    sleep(300);
    for (let cycle = 0; cycle <= cycles; cycle += 1) {
        const started = Date.now();
        adb(["shell", "input", "tap", "540", "838"]);
        const connected = awaitText("Подключено");
        const tuns = connected ? tunInterfaces() : [];
        result.connects.push({ cycle, connected, tunInterfaces: tuns, durationMs: Date.now() - started });
        persist();
        if (!connected || tuns.length === 0) { result.outcome = "fail"; break; }
        collectPprof(`pprof-${profile.labelHash}-cycle-${cycle}`);
        if (cycle < cycles) {
            adb(["shell", "input", "tap", "540", "838"]);
            if (!awaitText("Не подключено")) { result.outcome = "fail"; break; }
        }
    }
    if (result.connects.at(-1)?.connected && result.outcome !== "fail") {
        const deadline = Date.now() + soakSeconds * 1000;
        while (Date.now() < deadline) {
            const started = Date.now();
            const before = tunCounters();
            try {
                execFileSync("adb", [...adbPrefix, "shell", "curl", "-fsS", "--connect-timeout", "10", "--max-time", "20", "-o", "/dev/null", "https://speed.cloudflare.com/__down?bytes=1048576"], { stdio: ["ignore", "ignore", "pipe"] });
                const after = tunCounters();
                const delta = before && after ? { rxBytes: after.rxBytes - before.rxBytes, txBytes: after.txBytes - before.txBytes } : null;
                result.workload.push({ elapsedMs: Date.now() - started, result: delta?.rxBytes > 0 && delta.txBytes > 0 ? "tun-data-plane" : "no-tun-traffic", delta });
            } catch (error) {
                result.workload.push({ elapsedMs: Date.now() - started, result: "request-failed", error: String(error.stderr || "curl failed").trim() });
            }
            persist();
            const remaining = deadline - Date.now();
            if (remaining > 0) sleep(Math.min(workloadIntervalSeconds * 1000, remaining));
        }
        result.outcome = result.workload.some((sample) => sample.result === "tun-data-plane") ? "pass" : "fail";
    }
    if (result.connects.at(-1)?.connected) adb(["shell", "input", "tap", "540", "838"]);
    try { adb(["forward", "--remove", "tcp:19091"]); } catch { /* already removed or never created */ }
    persist();
    return { profile: profile.labelHash, outcome: result.outcome, cycles: result.connects, workloadSamples: result.workload.length };
}

function inventory() {
    mkdirSync(out, { recursive: true });
    if (dryRun) {
        const manifest = { mode: "dry-run", mutatesTunnel: false, secrets: "not collected" };
        writeJson("inventory-redacted.json", manifest);
        return manifest;
    }

    // This opens only the already stored server list; it does not create or start a core.
    adb(["shell", "am", "start", "-W", "-n", "io.hydrabox.client/io.hydrabox.platform.android.RuntimeControlActivity"]);
    sleep(300);
    adb(["shell", "input", "tap", "540", "2200"]);
    let xml = awaitServerList();
    // Navigation preserves scroll state. Reset it so profile indices stay stable between runs.
    for (let attempt = 0; attempt < 3; attempt += 1) adb(["shell", "input", "swipe", "540", "700", "540", "1900", "250"]);
    xml = awaitServerList();
    const manifest = {
        mode: "inventory",
        profileRows: profileRows(xml),
        profileCount: profileRows(xml).length,
        secrets: "labels are hashed; raw UI dump remains in the local evidence directory",
    };
    writeJson("inventory-redacted.json", manifest);
    return { mode: manifest.mode, profileCount: manifest.profileCount, evidence: "inventory-redacted.json" };
}

try {
    mkdirSync(out, { recursive: true });
    console.log(JSON.stringify(args.includes("--profile") ? runProfile(Number(value("--profile", "-1"))) : inventory()));
} catch (error) {
    console.error(JSON.stringify({ error: error.message }));
    process.exitCode = 1;
}
