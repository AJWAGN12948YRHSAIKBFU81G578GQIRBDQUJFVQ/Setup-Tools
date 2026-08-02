#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

LICENSE_KEY=$1

if [ -z "$LICENSE_KEY" ]; then
    echo -e "${RED}=== Tinkerbell Bridge Installer AWIKGOK ===${NC}"
    echo "Please enter your License Key from the Dashboard:"
    read -p "Key: " LICENSE_KEY < /dev/tty
fi

LICENSE_KEY=$(echo $LICENSE_KEY | tr -d ' ' | head -n1 | tr -d '\r\n')

if [[ ! "$LICENSE_KEY" =~ ^TINKERBELL-[A-Z0-9]{4}-[A-Z0-9]{4}$ ]]; then
    echo -e "${RED}Invalid Key Format. It should look like TINKERBELL-XXXX-XXXX${NC}"
    exit 1
fi

VPS_URL="https://predict-banked-exclusive.ngrok-free.dev" 

echo -e "${GREEN}=== Validating License Key ===${NC}"
VALIDATION=$(curl -s -X POST -H "Content-Type: application/json" -H "ngrok-skip-browser-warning: true" -d "{\"licenseKey\":\"$LICENSE_KEY\"}" "$VPS_URL/api/validate-key")

if [[ "$VALIDATION" != *"License valid"* ]]; then
    ERROR_MSG=$(echo $VALIDATION | grep -o '"message":"[^"]*' | cut -d'"' -f4)
    echo -e "${RED}Validation Failed: ${ERROR_MSG:-Invalid License Key}${NC}"
    exit 1
fi

echo -e "${GREEN}License Valid! Proceeding with installation...${NC}"

echo -e "${GREEN}=== Cleaning Previous Installation ===${NC}"
rm -rf ~/tinkerbell-bridge

echo -e "${GREEN}=== Installing Required Packages ===${NC}"
pkg uninstall nodejs -y > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive pkg install -y openssl nodejs-lts unzip -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" < /dev/null

echo -e "${GREEN}=== Setting Up Bridge Environment ===${NC}"
cd ~
mkdir -p tinkerbell-bridge
cd tinkerbell-bridge

npm init -y > /dev/null 2>&1
npm install socket.io-client > /dev/null 2>&1

# KITA BALIKIN KE CAT EOF ASLI LU, TAPI GUA PASTIKAN VARIABEL BASH GAK NGANGGU KODE NODE.JS
cat << EOF > bridge.js
const { io } = require("socket.io-client");
const { exec, execSync } = require("child_process");
const fs = require("fs");

const VPS_URL = "$VPS_URL"; 
const LICENSE_KEY = "$LICENSE_KEY";

function getProp(prop) {
    try {
        return execSync("getprop " + prop).toString().trim();
    } catch (e) {
        return "";
    }
}

let DEVICE_ID = "";
const idFile = "device_id.txt";

if (fs.existsSync(idFile)) {
    DEVICE_ID = fs.readFileSync(idFile, "utf8").trim();
} else {
    let model = getProp("ro.product.model") || "Unknown";
    let serial = getProp("ro.serialno") || getProp("ro.boot.serialno") || "";
    if (serial === "") {
        serial = Math.floor(Math.random() * 9000 + 1000).toString();
    }
    DEVICE_ID = model + "-" + serial;
    fs.writeFileSync(idFile, DEVICE_ID);
}

console.log("Hardware ID: " + DEVICE_ID);
console.log("Connecting to Tinkerbell Dashboard...");

const socket = io(VPS_URL, {
    reconnection: true,
    reconnectionDelay: 2000,
    auth: { licenseKey: LICENSE_KEY, deviceId: DEVICE_ID }
});

socket.on("connect", () => {
    console.log("[✓] Connected to Dashboard!");
    socket.emit("device_connect", { ip: "Cloud Phone", maxPackages: 10 });
});

socket.on("connect_error", (err) => {
    console.log("[!] Connection Failed: " + err.message);
    if (err.message.includes("Authentication failed") || err.message.includes("Invalid License Key") || err.message.includes("Device limit reached") || err.message.includes("License not activated")) {
        process.exit(1);
    }
});

const runCmd = (cmd) => {
    exec(cmd, (error, stdout, stderr) => {
        if (error) console.log("Cmd error: " + error.message);
    });
};

socket.on("execute_command", (data) => {
    console.log("[CMD] Received: " + data.command);
    
    if (data.command === 'clean_device') {
        // 1. FORCE ENABLE DEVELOPER OPTIONS (BIAR GAK PERLU NGETAP 7X BUILD NUMBER)
        runCmd('su -c "settings put global development_settings_enabled 1"');
        
        // 2. SETUP SISTEM BUAT BOTTING (FREEFORM WINDOWS & RESIZABLE)
        runCmd('su -c "settings put global enable_freeform_support 1"');
        runCmd('su -c "settings put global force_resizable_activities 1"');
        runCmd('su -c "settings put global allow_non_resizable_multi_window 1"');
        
        // 3. SET SMALLEST WIDTH / DPI (600)
        runCmd('su -c "wm density 600"');
        
        // 4. LIST BLOATWARE YANG WAJIB DIUNINSTALL (RAM LEGA, GAK GANGGU SISTEM RF)
        const uninstalls = [
            "com.android.chrome",              // Google Chrome
            "com.android.vending",             // Play Store (biar gak auto-update ganggu bot)
            "com.google.android.play.games",   // Play Games
            "com.google.android.apps.nbu.files", // Google Files
            "com.android.contacts",            // Kontak
            "com.android.messaging",           // SMS/Messaging
            "com.android.mms.service",         // MMS Service
            "com.android.dialer",              // Telepon
            "com.android.calendar",            // Kalender
            "com.android.deskclock",           // Jam
            "com.android.gallery3d",           // Galeri
            "com.android.music",               // Musik
            "com.android.soundrecorder",       // Recorder
            "com.android.email",               // Email
            "com.android.quicksearchbox",      // Search Box
            "com.android.egg",                 // Android Easter Egg (sampah)
            "com.android.printspooler",        // Print
            "com.android.bips",                // Print Service
            "com.android.printservice.recommendation",
            "com.android.dreams.basic",        // Screensaver
            "com.android.dreams.phototable",   // Screensaver Photo
            "com.android.bluetoothmidiservice" // Bluetooth MIDI
        ];
        
        uninstalls.forEach(pkg => {
            runCmd('su -c "pm uninstall --user 0 ' + pkg + '"');
        });

        // 5. LIST YANG SAFE DI-DISABLE (Pakai disable-user biar tetap aman)
        const disables = [
            "com.android.providers.downloads.ui", // Download UI
            "com.android.providers.downloads",    // Download Manager
            "com.android.hotspot2",               // Hotspot
            "com.android.bluetooth",              // Bluetooth
            "com.android.nfc"                     // NFC
        ];
        
        disables.forEach(pkg => {
            runCmd('su -c "pm disable-user --user 0 ' + pkg + '"');
        });
        
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Device cleaned, DPI set to 600, bloatware removed!', type: "success" });
    } 
    else if (data.command === 'reboot_device') {
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Rebooting device...', type: "success" });
        runCmd('su -c "reboot"');
    }
    else if (data.command === 'install_apk') {
        var apkUrl = data.payload.url;
        var appName = apkUrl.split('/').pop().split('?')[0];
        if (appName === "app.apk" || appName === "") appName = "APK";

        var downloadPath = "/data/data/com.termux/files/home/app_download";

        exec("rm -rf " + downloadPath, () => {
            console.log("[INSTALL] Downloading " + appName + "...");
            socket.emit("device_log", { deviceId: DEVICE_ID, message: "Downloading " + appName + "...", type: "info" });

            exec("curl -L -A 'Mozilla/5.0' -o " + downloadPath + " " + apkUrl, (error) => {
                if (error) {
                    console.log("[INSTALL] Download Failed: " + error.message);
                    socket.emit("device_log", { deviceId: DEVICE_ID, message: "Download failed.", type: "error" });
                    return;
                }
                
                console.log("[INSTALL] Download complete. Installing...");
                socket.emit("device_log", { deviceId: DEVICE_ID, message: "Download complete. Installing...", type: "info" });

                // BALIK KE PM INSTALL -R BIASA BUAT APK TUNGGAL
                exec('su -c "pm install -r ' + downloadPath + '"', (err2, stdout, stderr) => {
                    const output = (stdout || "") + (stderr || "");
                    if (output.includes("Success")) {
                        console.log("[INSTALL] " + appName + " installed successfully!");
                        socket.emit("device_log", { deviceId: DEVICE_ID, message: appName + " installed successfully!", type: "success" });
                    } else {
                        console.log("[INSTALL] Installation Failed: " + output);
                        socket.emit("device_log", { deviceId: DEVICE_ID, message: "Install failed: " + output.substring(0, 100), type: "error" });
                    }
                    exec('rm -f ' + downloadPath);
                });
            });
        });
    }
    else {
        socket.emit("device_log", { deviceId: DEVICE_ID, message: "Command " + data.command + " executed!", type: "success" });
    }
});

socket.on("disconnect", () => { console.log("Disconnected. Reconnecting..."); });
EOF

echo -e "${GREEN}=== Starting Tinkerbell Bridge ===${NC}"
node bridge.js
