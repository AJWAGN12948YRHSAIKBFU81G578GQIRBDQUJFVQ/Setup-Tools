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

# PAKAI 'EOF' (KUTIP SATU) SUPAYA BASH GAK MERUSAK KODE NODE.JS LU!
cat << 'EOF' > bridge.js
const { io } = require("socket.io-client");
const { exec, execSync } = require("child_process");
const fs = require("fs");

// AMBIL URL & KEY DARI ARGUMENT (100% AMAN DARI BASH)
const VPS_URL = process.argv[2]; 
const LICENSE_KEY = process.argv[3];

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
    let model = getProp("ro.product.model") || "RF";
    // Pake Android ID biar stabil walaupun RF di-reboot
    let androidId = "";
    try {
        androidId = execSync("su -c 'settings get secure android_id'").toString().trim();
    } catch (e) {
        androidId = Math.floor(Math.random() * 9000 + 1000).toString();
    }
    DEVICE_ID = model + "-" + androidId;
    fs.writeFileSync(idFile, DEVICE_ID);
}

console.log("Hardware ID: " + DEVICE_ID);
console.log("Connecting to Tinkerbell Dashboard...");

const socket = io(VPS_URL, {
    reconnection: true,
    reconnectionDelay: 2000,
    auth: { licenseKey: LICENSE_KEY, deviceId: DEVICE_ID }
});

// PREFIX FILTER DEFAULT
let currentPrefixes = ['com.roblox'];
try {
    if (fs.existsSync('prefix.txt')) {
        const savedPrefix = fs.readFileSync('prefix.txt', 'utf8').trim();
        if (savedPrefix) {
            currentPrefixes = savedPrefix.split('\n').map(p => p.trim()).filter(p => p);
        }
    }
} catch (e) {}

socket.on("connect", () => {
    console.log("[✓] Connected to Dashboard!");
    socket.emit("device_connect", { ip: "Cloud Phone", maxPackages: 10 });
    syncPackages();
});

const runCmd = (cmd) => {
    exec(cmd, (error, stdout, stderr) => {
        if (error) console.log("Cmd error: " + error.message);
    });
};

let lastSyncTime = 0;
const syncPackages = () => {
    const now = Date.now();
    if (now - lastSyncTime < 2000) {
        console.log("[SYNC] Debounced. Ignoring request.");
        return;
    }
    lastSyncTime = now;
    
    exec('su -c "pm list packages -3"', (err, stdout) => {
        if (!err && stdout) {
            let allPkgs = stdout.trim().split('\n').map(line => line.replace('package:', '').trim());
            let matchedPkgs = allPkgs.filter(pkg => {
                return currentPrefixes.some(prefix => pkg.toLowerCase().startsWith(prefix.toLowerCase()));
            });
            console.log("[SYNC] Found " + matchedPkgs.length + " packages matching prefix.");
            socket.emit("sync_packages", { deviceId: DEVICE_ID, packages: matchedPkgs });
        }
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
        
        // LOOPING: COBA UNINSTALL, KALO GAGAL LANGSUNG DISABLE
        apps.forEach(pkg => {
            exec('su -c "pm uninstall --user 0 ' + pkg + ' 2>/dev/null || pm disable-user --user 0 ' + pkg + ' 2>/dev/null"', () => {});
        });
        
        // LOOPING DISABLE ONLY (Paksa disable tanpa uninstall)
        disableOnly.forEach(pkg => {
            exec('su -c "pm disable-user --user 0 ' + pkg + ' 2>/dev/null"', () => {});
        });

        // 4. UNINSTALL SEMUA APP PIHAK KETIGA (-3) KECUALI TERMUX (PAKE NODEJS LOOP)
        exec('su -c "pm list packages -3"', (err, stdout) => {
            if (!err && stdout) {
                stdout.trim().split('\n').forEach(pkgLine => {
                    const pkg = pkgLine.replace('package:', '').trim();
                    if (pkg && pkg !== 'com.termux') {
                        exec('su -c "pm uninstall --user 0 ' + pkg + ' || pm disable-user --user 0 ' + pkg + ' || pm hide ' + pkg + '"', () => {});
                    }
                });
            }
        });
        
        // 5. WIPE SEMUA FILE SAMPAH DI PENYIMPANAN INTERNAL (Download, APK, Bot files, dll)
        exec('su -c "rm -rf /sdcard/* /storage/emulated/0/* /data/local/tmp/*"', () => {});
        
        // 6. BERSIHKAN CACHE SISTEM BIAR RAM SEGAR KAYAK BARU BELI
        exec('su -c "rm -rf /data/dalvik-cache/*"', () => {});
        
        // 7. BERSIHKAN SHORTCUT IKLAN DI HOME SCREEN (LAUNCHER)
        exec('su -c "pm clear com.android.launcher3"', () => {});
        
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Device wiped clean! All apps & files removed.', type: "success" });
        console.log("[CMD] Successfully Cleaning Device");
    } 
    else if (data.command === 'reboot_device') {
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Rebooting device...', type: "success" });
        runCmd('su -c "reboot"');
    }    
    else if (data.command === 'open_all_packages') {
        var pkgs = data.payload.packages || [];
        if (pkgs.length === 0) {
            socket.emit("device_log", { deviceId: DEVICE_ID, message: "No packages to open.", type: "error" });
            return;
        }
        console.log("[CMD] Opening " + pkgs.length + " packages...");
        pkgs.forEach((pkg, i) => {
            setTimeout(() => {
                exec('su -c "monkey -p ' + pkg + ' -c android.intent.category.LAUNCHER 1"', () => {});
            }, i * 1000);
        });
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Opened ' + pkgs.length + ' packages successfully!', type: "success" });
    }    
    else if (data.command === 'auto_grid') {
        var pkgs = data.payload.packages || [];
        if (pkgs.length === 0) {
            socket.emit("device_log", { deviceId: DEVICE_ID, message: "No packages to grid.", type: "error" });
            return;
        }
        
        var totalGrid = pkgs.length;
        console.log("[GRID] Starting Auto Grid for " + totalGrid + " apps...");
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Initializing Auto Grid...', type: "grid_start" });
        
        exec('su -c "wm size"', (err, stdout) => {
            if (err) return;
            var sizeStr = stdout.split(' ').pop(); 
            var parts = sizeStr.split('x');
            var w = parseInt(parts[0]);
            var h = parseInt(parts[1]);
            var SW = w < h ? h : w;
            var SH = w < h ? w : h;
            
            // STRICT 2 KOLOM (2x2, 2x3, 2x4, 2x5)
            var cols = 2;
            var rows = Math.ceil(totalGrid / cols);
            
            var OFFSET_TOP = 60; 
            var AVAILABLE_H = SH - OFFSET_TOP;
            var GW = Math.floor(SW / cols);
            var GH = Math.floor(AVAILABLE_H / rows);
            
            pkgs.forEach((pkg, i) => {
                setTimeout(() => {
                    var row = Math.floor(i / cols);
                    var col = i % cols;
                    var L = col * GW;
                    var T = (row * GH) + OFFSET_TOP;
                    var R = (col + 1) * GW;
                    var B = ((row + 1) * GH) + OFFSET_TOP;
                    
                    var prefPath = `/data/data/${pkg}/shared_prefs/${pkg}_preferences.xml`;
                    var activityName = `${pkg}/com.roblox.client.startup.ActivitySplash`;
                    
                    var percent = Math.round(((i + 1) / totalGrid) * 100);
                    var msg = `Gridding ${pkg} [${i+1}/${totalGrid}]`;
                    socket.emit("device_log", { deviceId: DEVICE_ID, message: msg, type: "grid_progress", percent: percent });
                    
                    var cmd = `su -c "
                        am force-stop ${pkg} 2>/dev/null;
                        rm -rf /data/data/${pkg}/cache/* /data/data/${pkg}/code_cache/* 2>/dev/null;
                        chmod 666 ${prefPath} 2>/dev/null;
                        
                        sed -i 's/name=\\"app_cloner_current_window_left\\" value=\\"[^\\"]*\\"/name=\\"app_cloner_current_window_left\\" value=\\"${L}\\"/g' ${prefPath};
                        sed -i 's/name=\\"app_cloner_current_window_top\\" value=\\"[^\\"]*\\"/name=\\"app_cloner_current_window_top\\" value=\\"${T}\\"/g' ${prefPath};
                        sed -i 's/name=\\"app_cloner_current_window_right\\" value=\\"[^\\"]*\\"/name=\\"app_cloner_current_window_right\\" value=\\"${R}\\"/g' ${prefPath};
                        sed -i 's/name=\\"app_cloner_current_window_bottom\\" value=\\"[^\\"]*\\"/name=\\"app_cloner_current_window_bottom\\" value=\\"${B}\\"/g' ${prefPath};
                        
                        chmod 444 ${prefPath} 2>/dev/null;
                        am start --user 0 -n ${activityName} 2>/dev/null
                    "`;
                    
                    exec(cmd, () => {
                        console.log(`[GRID] ✓ ${pkg} gridded successfully!`);
                        if (i === pkgs.length - 1) {
                            socket.emit("device_log", { deviceId: DEVICE_ID, message: 'All apps gridded successfully!', type: "grid_done" });
                        }
                    });
                }, i * 15000); 
            });
        });
    }
    else if (data.command === 'sync_packages') {
        if (data.payload && Array.isArray(data.payload.prefixes)) {
            currentPrefixes = data.payload.prefixes.filter(p => p.trim() !== '');
            fs.writeFileSync('prefix.txt', currentPrefixes.join('\n'));
            console.log("[CMD] Prefix updated & saved: " + JSON.stringify(currentPrefixes));
        }
        console.log("[CMD] Syncing packages...");
        syncPackages();
    }
    else if (data.command === 'install_apk') {
        var apkUrl = data.payload.url;
        var appName = data.payload.name || apkUrl.split('/').pop().split('?')[0];
        if (appName === "app.apk" || appName === "") appName = "APK";
        
        var cloneCount = parseInt(data.payload.count) || 1;
        if (cloneCount > 10) cloneCount = 10;
        var isExecutor = data.payload.isExecutor || false;
        
        const processInstall = (url, name) => {
            var uniqueId = Date.now() + Math.floor(Math.random() * 1000);
            var downloadPath = "/data/data/com.termux/files/home/app_download_" + uniqueId + ".apk";
            var tmpPath = "/data/local/tmp/app_install_" + uniqueId + ".apk";

            console.log("[INSTALL] Downloading " + name + "...");
            socket.emit("device_log", { deviceId: DEVICE_ID, message: "Starting install for " + name, type: "install_start", percent: 0 });
            socket.emit("device_log", { deviceId: DEVICE_ID, message: "Downloading " + name + "...", type: "install_progress", percent: 25 });

            exec("curl -L -A 'Mozilla/5.0' -o " + downloadPath + " " + url, (error) => {
                if (error) {
                    socket.emit("device_log", { deviceId: DEVICE_ID, message: "Download failed for " + name, type: "install_progress", percent: 0 });
                    return;
                }
                
                console.log("[INSTALL] Installing " + name + "...");
                socket.emit("device_log", { deviceId: DEVICE_ID, message: "Installing " + name + "...", type: "install_progress", percent: 75 });
                
                var installCmd = 'su -c "cp ' + downloadPath + ' ' + tmpPath + ' && pm install -r ' + tmpPath + '"';
                
                exec(installCmd, (err2, stdout, stderr) => {
                    const output = (stdout || "") + (stderr || "");
                    exec('rm -f ' + downloadPath);
                    
                    if (output.includes("Success")) {
                        console.log("[INSTALL] " + name + " installed successfully!");
                        socket.emit("device_log", { deviceId: DEVICE_ID, message: name + " installed successfully!", type: "install_progress", percent: 100 });
                        
                        if (isExecutor) {
                            exec('su -c "/data/data/com.termux/files/usr/bin/aapt dump badging ' + tmpPath + ' | grep package"', (err3, pkgOut) => {
                                if (!err3 && pkgOut) {
                                    const match = pkgOut.match(/name='([^']+)'/);
                                    if (match && match[1]) {
                                        const pkg = match[1];
                                        socket.emit("device_log", { deviceId: DEVICE_ID, message: "Opening " + name + "...", type: "install_progress", percent: 100 });
                                        exec('su -c "monkey -p ' + pkg + ' -c android.intent.category.LAUNCHER 1"', () => {
                                            exec('rm -f ' + tmpPath);
                                            syncPackages();
                                        });
                                    } else {
                                        exec('rm -f ' + tmpPath);
                                        syncPackages();
                                    }
                                } else {
                                    exec('rm -f ' + tmpPath);
                                    syncPackages();
                                }
                            });
                        } else {
                            exec('rm -f ' + tmpPath);
                            syncPackages();
                        }
                    } else {
                        socket.emit("device_log", { deviceId: DEVICE_ID, message: "Install failed for " + name, type: "install_progress", percent: 0 });
                        exec('rm -f ' + tmpPath);
                    }
                });
            });
        };

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
node bridge.js "$VPS_URL" "$LICENSE_KEY"
