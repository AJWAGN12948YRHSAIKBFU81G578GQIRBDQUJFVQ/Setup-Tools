#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}=== PENTELLLL ===${NC}"
echo "Please enter your License Key from the Dashboard:"
read -p "Key: " LICENSE_KEY < /dev/tty

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
pkg update -y
pkg install nodejs-lts -y

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

let model = "Unknown";
let serial = "Unknown";

try { model = execSync("getprop ro.product.model").toString().trim(); } catch (e) {}
try { serial = execSync("getprop ro.serialno").toString().trim(); } catch (e) {}

if (serial === "" || serial === "unknown") {
    try { serial = execSync("getprop ro.boot.serialno").toString().trim(); } catch (e) {}
}

const DEVICE_ID = model + "-" + serial;

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
        if (error) console.log("Cmd error: " + error.message.split("\n")[0]);
    });
};

socket.on("execute_command", (data) => {
    console.log("[CMD] Received: " + data.command);
    
    const { execSync } = require("child_process");
    const fs = require("fs");
    
    // FUNGSI SILENT BIAR NGGAK NGE-PRINT ERROR PAS HP MATI/REBOOT
    const runCmd = (cmd) => {
        try { 
            execSync(cmd, { stdio: 'ignore' }); 
        } catch (e) {
            // Diem aja kalau gagal
        }
    };

    if (data.command === 'clean_device') {
        console.log("Cleaning device & setting up...");
        
        runCmd('su -c "settings put global enable_freeform_support 1"');
        runCmd('su -c "settings put global force_resizable_activities 1"');
        runCmd('su -c "settings put global allow_non_resizable_multi_window 1"');
        runCmd('su -c "wm density 640"');
        
        try {
            const packages = execSync('su -c "pm list packages -3"', { encoding: 'utf8' }).trim().split('\n');
            packages.forEach(pkgLine => {
                const pkg = pkgLine.replace('package:', '').trim();
                if (pkg && pkg !== 'com.termux') {
                    runCmd('su -c "pm uninstall -k --user 0 ' + pkg + '"');
                }
            });
        } catch (e) {}

        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Device cleaned & DPI set to 640', type: "success" });
    } 
    else if (data.command === 'reboot_device') {
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Rebooting device...', type: "success" });
        // PAKAI SETPROP (SANGAT AMAN DI REDFINGER)
        runCmd('su -c "setprop sys.powerctl reboot"');
    }
    else if (data.command === 'reset_device') {
        console.log("Factory resetting device to fresh state...");
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Wiping ALL apps & storage...', type: "success" });
        
        const wipeScript = "#!/system/bin/sh\n" +
        "pm list packages -3 | cut -d: -f2 | while read pkg; do\n" +
        "    if [ \"$pkg\" != \"com.termux\" ]; then\n" +
        "        pm uninstall --user 0 \"$pkg\"\n" +
        "    fi\n" +
        "done\n" +
        "rm -rf /sdcard/*\n" +
        "rm -rf /storage/emulated/0/*\n" +
        "rm -rf /data/dalvik-cache/*\n" +
        "sleep 2\n" +
        "pm uninstall --user 0 com.termux\n" +
        "setprop sys.powerctl reboot";
        
        try {
            fs.writeFileSync('/data/data/com.termux/files/home/wipe.sh', wipeScript);
            runCmd('su -c "sh /data/data/com.termux/files/home/wipe.sh"');
        } catch (e) {
            console.log("Failed to write wipe script: " + e.message);
        }
    }
    else {
        socket.emit("device_log", { deviceId: DEVICE_ID, message: "Command " + data.command + " executed!", type: "success" });
    }
});

socket.on("disconnect", () => { console.log("Disconnected. Reconnecting..."); });
EOF

echo -e "${GREEN}=== Starting Tinkerbell Bridge ===${NC}"
while true; do
    node bridge.js
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 1 ]; then
        echo "[!] Script stopped due to device limit or invalid license."
        break
    fi
    
    echo "[!] Connection lost. Reconnecting in 5 seconds..."
    sleep 5
done
