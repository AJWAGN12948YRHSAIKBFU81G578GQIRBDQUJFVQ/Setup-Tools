#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

LICENSE_KEY=$1

if [ -z "$LICENSE_KEY" ]; then
    echo -e "${RED}=== Tinkerbell Bridge Installer NEMPEK ===${NC}"
    echo "Please enter your License Key from the Dashboard:"
    read -p "Key: " LICENSE_KEY < /dev/tty
fi

LICENSE_KEY=$(echo $LICENSE_KEY | tr -d ' ' | head -n1 | tr -d '\r\n')

if [[ ! "$LICENSE_KEY" =~ ^TINKERBELL-[A-Z0-9]{4}-[A-Z0-9]{4}$ ]]; then
    echo -e "${RED}Invalid Key Format. It should look like TINKERBELL-XXXX-XXXX${NC}"
    exit 1
fi

# GANTI URL INI DENGAN URL BACKEND LU
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
        runCmd("su -c 'settings put global development_settings_enabled 1'");
        runCmd("su -c 'settings put global enable_freeform_support 1'");
        runCmd("su -c 'settings put global force_resizable_activities 1'");
        runCmd("su -c 'settings put global allow_non_resizable_multi_window 1'");
        runCmd("su -c 'wm density 640'");
        
        exec("su -c 'pm list packages -3'", (err, stdout) => {
            if (!err && stdout) {
                stdout.trim().split('\n').forEach(pkgLine => {
                    const pkg = pkgLine.replace('package:', '').trim();
                    if (pkg && pkg !== 'com.termux') {
                        runCmd("su -c 'pm uninstall -k --user 0 " + pkg + "'");
                    }
                });
            }
        });
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Device cleaned & DPI set to 640', type: "success" });
    } 
    else if (data.command === 'reboot_device') {
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Rebooting device...', type: "success" });
        runCmd("su -c 'reboot'");
    }
    else if (data.command === 'reset_device') {
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Wiping ALL apps & storage...', type: "success" });
        // HAPUS TANDA & DI BELAKANG, BIAR PROSES BENER-BENER SELESAI SEBELUM REBOOT
        runCmd("su -c 'pm list packages -3 | cut -d: -f2 | while read pkg; do pm uninstall --user 0 $pkg; done; rm -rf /sdcard/*; rm -rf /storage/emulated/0/*; rm -rf /data/dalvik-cache/*; sleep 2; pm uninstall --user 0 com.termux; reboot'");
    }
    else if (data.command === 'install_apk') {
        var apkUrl = data.payload.url;
        var appName = apkUrl.split('/').pop().split('?')[0];
        if (appName === "app.apk" || appName === "") appName = "APK";

        var downloadPath = "/data/data/com.termux/files/home/app_download";
        var extractPath = "/data/data/com.termux/files/home/app_extract";

        exec("rm -rf " + downloadPath + " " + extractPath, () => {
            console.log("[INSTALL] Downloading " + appName + "...");
            socket.emit("device_log", { deviceId: DEVICE_ID, message: "Downloading " + appName + "...", type: "info" });

            exec("curl -L -A 'Mozilla/5.0' -o " + downloadPath + " " + apkUrl, (error) => {
                if (error) {
                    console.log("[INSTALL] Download Failed: " + error.message);
                    socket.emit("device_log", { deviceId: DEVICE_ID, message: "Download failed.", type: "error" });
                    return;
                }
                
                console.log("[INSTALL] Download complete. Processing...");
                socket.emit("device_log", { deviceId: DEVICE_ID, message: "Download complete. Installing...", type: "info" });

                // METHOD B: PAKAI UNZIP + PM INSTALL-MULTIPLE BUAT SPLIT APK
                if (appName.endsWith(".xapk") || appName.endsWith(".zip")) {
                    exec("unzip -o " + downloadPath + " -d " + extractPath, (err1) => {
                        if (err1) {
                            console.log("[INSTALL] Extraction Failed: " + err1.message);
                            socket.emit("device_log", { deviceId: DEVICE_ID, message: "Extraction failed.", type: "error" });
                            return;
                        }
                        
                        try {
                            const files = fs.readdirSync(extractPath);
                            const apkFiles = files.filter(f => f.endsWith('.apk'));

                            if (apkFiles.length === 0) {
                                socket.emit("device_log", { deviceId: DEVICE_ID, message: "No APK found inside archive.", type: "error" });
                                return;
                            }

                            // GABUNG SEMUA PATH APK PAKAI XARGS BIAR NGGAK KEPANJANGAN (CRASH)
                            const apkPaths = apkFiles.map(f => extractPath + "/" + f).join(" ");
                            const installCmd = 'su -c "pm install-multiple -r ' + apkPaths + '"';

                            exec(installCmd, (err2, stdout, stderr) => {
                                if (err2 || stderr.includes("Failure")) {
                                    console.log("[INSTALL] Installation Failed: " + (stderr || err2.message));
                                    socket.emit("device_log", { deviceId: DEVICE_ID, message: "Installation failed: " + (stderr || "Unknown"), type: "error" });
                                } else {
                                    console.log("[INSTALL] " + appName + " installed successfully!");
                                    socket.emit("device_log", { deviceId: DEVICE_ID, message: appName + " installed successfully!", type: "success" });
                                }
                                exec('rm -rf ' + extractPath + ' ' + downloadPath);
                            });
                        } catch (e) {
                            socket.emit("device_log", { deviceId: DEVICE_ID, message: "Failed to read extracted files.", type: "error" });
                        }
                    });
                } else {
                    // KALO .apk BIASA, LANGSUNG INSTALL
                    exec('su -c "pm install ' + downloadPath + '"', (err2) => {
                        if (err2) {
                            console.log("[INSTALL] Installation Failed: " + err2.message);
                            socket.emit("device_log", { deviceId: DEVICE_ID, message: "Installation failed.", type: "error" });
                        } else {
                            console.log("[INSTALL] " + appName + " installed successfully!");
                            socket.emit("device_log", { deviceId: DEVICE_ID, message: appName + " installed successfully!", type: "success" });
                        }
                        exec('rm -f ' + downloadPath);
                    });
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
