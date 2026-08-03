#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

LICENSE_KEY=$1

if [ -z "$LICENSE_KEY" ]; then
    echo -e "${RED}=== Tinkerbell Bridge Installer ===${NC}"
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
DEBIAN_FRONTEND=noninteractive pkg install -y openssl nodejs-lts unzip aapt -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" < /dev/null

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
        
        exec('su -c "settings put global development_settings_enabled 1"', () => {});
        exec('su -c "settings put global enable_freeform_support 1"', () => {});
        exec('su -c "settings put global force_resizable_activities 1"', () => {});
        exec('su -c "settings put global allow_non_resizable_multi_window 1"', () => {});
        exec('su -c "wm density 192"', () => {});
        exec('su -c "pm clear com.android.launcher3"', () => {});
        
        // UNINSTALL SEMUA APP PIHAK KETIGA KECUALI TERMUX (PAKE NODEJS LOOP)
        exec('su -c "pm list packages -3"', (err, stdout) => {
            if (!err && stdout) {
                stdout.trim().split('\n').forEach(pkgLine => {
                    const pkg = pkgLine.replace('package:', '').trim();
                    if (pkg && pkg !== 'com.termux') {
                        // COBA UNINSTALL, KALO GAGAL DI-DISABLE, KALO GAGAL DI-HIDE
                        exec('su -c "pm uninstall --user 0 ' + pkg + ' || pm disable-user --user 0 ' + pkg + ' || pm hide ' + pkg + '"', () => {});
                    }
                });
            }
        });
        
        // WIPE FILE SAMPAH
        exec('su -c "rm -rf /sdcard/* /storage/emulated/0/* /data/local/tmp/*"', () => {});
        exec('su -c "rm -rf /data/dalvik-cache/*"', () => {});
        
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Device wiped clean! All apps & files removed.', type: "success" });
        console.log("[CMD] Successfully Cleaning Device");
    } 
    else if (data.command === 'reboot_device') {
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Rebooting device...', type: "success" });
        runCmd('su -c "reboot"');
    }
    else if (data.command === 'install_apk') {
        var apkUrl = data.payload.url;
        var appName = data.payload.name || apkUrl.split('/').pop().split('?')[0];
        if (appName === "app.apk" || appName === "") appName = "APK";
        
        var cloneCount = parseInt(data.payload.count) || 1;
        if (cloneCount > 10) cloneCount = 10; // MAX 10 CLONE
        var isExecutor = data.payload.isExecutor || false;
        
        // FUNCTION BUAT DOWNLOAD, INSTALL & OPEN
        const processInstall = (url, name) => {
            var uniqueId = Date.now() + Math.floor(Math.random() * 1000);
            var downloadPath = "/data/data/com.termux/files/home/app_download_" + uniqueId + ".apk";
            var tmpPath = "/data/local/tmp/app_install_" + uniqueId + ".apk";

            console.log("[INSTALL] Downloading " + name + "...");
            socket.emit("device_log", { deviceId: DEVICE_ID, message: "Downloading " + name + "...", type: "info" });

            exec("curl -L -A 'Mozilla/5.0' -o " + downloadPath + " " + url, (error) => {
                if (error) {
                    console.log("[INSTALL] Download Failed: " + error.message);
                    socket.emit("device_log", { deviceId: DEVICE_ID, message: "Download failed for " + name, type: "error" });
                    exec('rm -f ' + downloadPath);
                    return;
                }
                
                console.log("[INSTALL] Installing " + name + "...");
                var installCmd = 'su -c "cp ' + downloadPath + ' ' + tmpPath + ' && pm install -r ' + tmpPath + '"';
                
                exec(installCmd, (err2, stdout, stderr) => {
                    const output = (stdout || "") + (stderr || "");
                    exec('rm -f ' + downloadPath);
                    
                    if (output.includes("Success")) {
                        console.log("[INSTALL] " + name + " installed successfully!");
                        socket.emit("device_log", { deviceId: DEVICE_ID, message: name + " installed successfully!", type: "success" });
                        
                        // KALO INI EXECUTOR, AUTO OPEN PAKE AAPT + MONKEY
                        if (isExecutor) {
                            exec('su -c "aapt dump badging ' + tmpPath + ' | grep package"', (err3, pkgOut) => {
                                if (!err3 && pkgOut) {
                                    const match = pkgOut.match(/name='([^']+)'/);
                                    if (match && match[1]) {
                                        const pkg = match[1];
                                        console.log("[INSTALL] Auto opening " + pkg + "...");
                                        socket.emit("device_log", { deviceId: DEVICE_ID, message: "Opening " + name + "...", type: "info" });
                                        
                                        // BUKA APK NYA
                                        exec('su -c "monkey -p ' + pkg + ' -c android.intent.category.LAUNCHER 1"', () => {
                                            exec('rm -f ' + tmpPath);
                                        });

                                        // KIRIM PACKAGE NAME KE DASHBOARD
                                        socket.emit("add_package", { deviceId: DEVICE_ID, packageName: pkg });
                                    } else {
                                        exec('rm -f ' + tmpPath);
                                    }
                                } else {
                                    console.log("[INSTALL] AAPT not found or failed to read package.");
                                    exec('rm -f ' + tmpPath);
                                }
                            });
                        } else {
                            exec('rm -f ' + tmpPath);
                        }
                    } else {
                        console.log("[INSTALL] Installation Failed: " + output);
                        socket.emit("device_log", { deviceId: DEVICE_ID, message: "Install failed for " + name + ": " + output.substring(0, 100), type: "error" });
                        exec('rm -f ' + tmpPath);
                    }
                });
            });
        };

        // LOGIKA CLONING
        if (cloneCount > 1) {
            for (let i = 1; i <= cloneCount; i++) {
                let newUrl = apkUrl;
                
                if (apkUrl.includes("{clone}")) {
                    let cloneStr = i < 10 ? '0' + i : i;
                    newUrl = apkUrl.replace("{clone}", cloneStr);
                } 
                else if (apkUrl.endsWith(".apk.apk")) {
                    newUrl = apkUrl.slice(0, -8) + i + ".apk.apk";
                } 
                else if (apkUrl.endsWith(".apk")) {
                    newUrl = apkUrl.slice(0, -4) + i + ".apk";
                } 
                else {
                    newUrl = apkUrl + i;
                }
                
                let cloneName = appName + " (Clone " + i + ")";
                // KASIH JEDA 2 DETIK BIAR INSTALL NYA GAK BENTROK
                setTimeout(() => { processInstall(newUrl, cloneName); }, (i - 1) * 2000);
            }
        } else {
            if (apkUrl.includes("{clone}")) {
                apkUrl = apkUrl.replace("{clone}", "01");
            }
            processInstall(apkUrl, appName);
        }
    }
    else {
        socket.emit("device_log", { deviceId: DEVICE_ID, message: "Command " + data.command + " executed!", type: "success" });
    }
});

socket.on("disconnect", () => { console.log("Disconnected. Reconnecting..."); });
EOF

echo -e "${GREEN}=== Starting Tinkerbell Bridge ===${NC}"
node bridge.js
