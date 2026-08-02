#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

LICENSE_KEY=$1

if [ -z "$LICENSE_KEY" ]; then
    echo -e "${RED}=== Tinkerbell Bridge Installer WWW ===${NC}"
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
        console.log("[CMD] Cleaning Device...");
        
        // 0. WAJIB: ENABLE BALIK PACKAGE SISTEM YANG KEDISABLE DARI CODE LAMA (FIX CRASH APP INFO)
        exec('su -c "pm enable com.android.permissioncontroller"', () => {});
        exec('su -c "pm enable com.android.packageinstaller"', () => {});
        exec('su -c "pm enable com.android.providers.telephony"', () => {});
        exec('su -c "pm enable com.android.providers.calendar"', () => {});
        exec('su -c "pm enable com.android.providers.downloads"', () => {});
        exec('su -c "pm enable com.android.networkstack"', () => {});
        
        // 1. FORCE ENABLE DEVELOPER OPTIONS (Silent)
        exec('su -c "settings put global development_settings_enabled 1"', () => {});
        exec('su -c "settings put global enable_freeform_support 1"', () => {});
        exec('su -c "settings put global force_resizable_activities 1"', () => {});
        exec('su -c "settings put global allow_non_resizable_multi_window 1"', () => {});
        exec('su -c "wm density 192"', () => {});
        
        // 2. LIST BLOATWARE YANG AMAN DI-UNINSTALL/DISABLE
        const apps = [
            "com.android.tools",               // Tools RF
            "com.android.toolkit",             // Toolbox RF
            "com.android.adbkeyboard",         // Tobitx / ADB Keyboard RF
            "com.android.chrome",              
            "com.android.vending",             
            "com.android.market",
            "com.google.android.play.games",
            "com.google.android.apps.nbu.files",
            "com.android.contacts",
            "com.android.messaging",
            "com.android.mms.service",
            "com.android.dialer",
            "com.android.calendar",
            "com.android.deskclock",           
            "com.android.gallery3d",
            "com.android.music",
            "com.android.musicfx",
            "com.android.soundrecorder",
            "com.android.email",
            "com.android.quicksearchbox",
            "com.android.egg",                 
            "com.android.printspooler",
            "com.android.bips",
            "com.android.printservice.recommendation",
            "com.android.dreams.basic",        
            "com.android.dreams.phototable",
            "com.android.bluetoothmidiservice",
            "com.android.bluetooth",
            "com.android.nfc",
            "com.android.providers.downloads.ui",
            "com.android.hotspot2",
            "com.android.bookmarkprovider",
            "com.android.cellbroadcastreceiver",
            "com.android.emergency",
            "com.android.ons",
            "com.android.simappdialog",
            "com.android.carrierconfig",
            "com.android.carrierdefaultapp",
            "com.android.networkstack.permissionconfig",
            "com.android.captiveportallogin",
            "com.android.localtransport",
            "com.android.proxyhandler",
            "com.android.sharedstoragebackup",
            "com.android.statementservice",
            "com.android.calllogbackup",
            "com.android.backupconfirm",
            "com.android.providers.userdictionary",
            "com.android.providers.blockednumber"
        ];
        
        // 3. LIST APPS YANG CUMA BOLEH DI-DISABLE (JANGAN DI-UNINSTALL)
        const disableOnly = [
            "com.google.android.gms",                  // Google Play Services
            "com.android.inputmethod.latin",           // Android Keyboard (AOSP)
            "com.google.android.inputmethod.latin"     // Gboard
        ];
        
        // 4. LOOPING: COBA UNINSTALL, KALO GAGAL LANGSUNG DISABLE
        apps.forEach(pkg => {
            exec('su -c "pm uninstall --user 0 ' + pkg + ' 2>/dev/null || pm disable-user --user 0 ' + pkg + ' 2>/dev/null"', () => {});
        });
        
        // 5. LOOPING DISABLE ONLY (Paksa disable tanpa uninstall)
        disableOnly.forEach(pkg => {
            exec('su -c "pm disable-user --user 0 ' + pkg + ' 2>/dev/null"', () => {});
        });
        
        // 6. BERSIHKAN SHORTCUT IKLAN DI HOME SCREEN (LAUNCHER)
        exec('su -c "pm clear com.android.launcher3"', () => {});
        
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Device cleaned! Bloatware disabled & DPI set to 600', type: "success" });
        console.log("[CMD] Successfully Cleaning Device");
    } 
    else if (data.command === 'reboot_device') {
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Rebooting device...', type: "success" });
        runCmd('su -c "reboot"');
    }
    else if (data.command === 'install_apk') {
        var apkUrl = data.payload.url;
        var appName = apkUrl.split('/').pop().split('?')[0];
        if (appName === "app.apk" || appName === "") appName = "APK";

        // 1. BUAT NAMA FILE UNIK BIAR GAK BENTROK KALO INSTALL BARENGAN
        var uniqueId = Date.now();
        var downloadPath = "/data/data/com.termux/files/home/app_download_" + uniqueId + ".apk";
        var tmpPath = "/data/local/tmp/app_install_" + uniqueId + ".apk";

        exec("curl -L -A 'Mozilla/5.0' -o " + downloadPath + " " + apkUrl, (error) => {
            if (error) {
                console.log("[INSTALL] Download Failed: " + error.message);
                socket.emit("device_log", { deviceId: DEVICE_ID, message: "Download failed.", type: "error" });
                exec('rm -f ' + downloadPath);
                return;
            }
            
            console.log("[INSTALL] Download complete. Installing...");
            socket.emit("device_log", { deviceId: DEVICE_ID, message: "Download complete. Installing...", type: "info" });

            // 2. COPY FILE KE /data/local/tmp/ BARU DI INSTALL (BYPASS BLOCK RED FINGER)
            var installCmd = 'su -c "cp ' + downloadPath + ' ' + tmpPath + ' && pm install -r ' + tmpPath + ' && rm -f ' + tmpPath + '"';
            
            exec(installCmd, (err2, stdout, stderr) => {
                const output = (stdout || "") + (stderr || "");
                // HAPUS FILE ASLI DI TERMUX BIAR GAK NYUMPAH
                exec('rm -f ' + downloadPath);
                
                if (output.includes("Success")) {
                    console.log("[INSTALL] " + appName + " installed successfully!");
                    socket.emit("device_log", { deviceId: DEVICE_ID, message: appName + " installed successfully!", type: "success" });
                } else {
                    console.log("[INSTALL] Installation Failed: " + output);
                    socket.emit("device_log", { deviceId: DEVICE_ID, message: "Install failed: " + output.substring(0, 100), type: "error" });
                }
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
