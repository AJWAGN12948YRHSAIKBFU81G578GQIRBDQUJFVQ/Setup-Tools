#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}=== Tinkerbell Bridge Installer ===${NC}"
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
const { execSync } = require("child_process");

const VPS_URL = "$VPS_URL"; 
const LICENSE_KEY = "$LICENSE_KEY";

let model = "Unknown";
let serial = "Unknown";
let androidId = "Unknown";

try { model = execSync("getprop ro.product.model").toString().trim(); } catch (e) {}
try { serial = execSync("getprop ro.serialno").toString().trim(); } catch (e) {}
try { androidId = execSync("settings get secure android_id").toString().trim(); } catch (e) {}

const DEVICE_ID = \`\${model}-\${serial}-\${androidId}\`;

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
        console.log("[!] Please check your License Key or reset it from the dashboard.");
        process.exit(1);
    }
});

socket.on("execute_command", (data) => {
    console.log(`[CMD] Received: ${data.command}`);
    
    if (data.command === 'clean_device') {
        console.log("Cleaning device & setting up...");
        try {
            execSync('su -c "settings put global enable_freeform_support 1"');
            execSync('su -c "settings put global force_resizable_activities 1"');
            execSync('su -c "settings put global allow_non_resizable_multi_window 1"');
            
            execSync('su -c "wm density 600"');
            
            const bloatware = [
                'com.google.android.youtube', 'com.google.android.apps.photos', 
                'com.android.chrome', 'com.google.android.apps.maps', 
                'com.google.android.gm', 'com.google.android.videos', 
                'com.google.android.music', 'com.google.android.apps.docs',
                'com.google.android.apps.magazines', 'com.miui.player'
            ];
            bloatware.forEach(pkg => {
                execSync(`su -c "pm uninstall -k --user 0 ${pkg}" > /dev/null 2>&1`);
            });

            socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Device cleaned & DPI set to 600 successfully', type: "success" });
            console.log("Device cleaned successfully!");
        } catch (e) {
            socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Clean Device Failed. Root access required in Termux.', type: "error" });
            console.log("Clean failed: " + e.message);
        }
    } 
    else if (data.command === 'reboot_device') {
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Rebooting device...', type: "success" });
        console.log("Rebooting device...");
        execSync('su -c "reboot"');
    }
    else if (data.command === 'reset_device') {
        socket.emit("device_log", { deviceId: DEVICE_ID, message: 'Factory Resetting device...', type: "success" });
        console.log("Factory resetting device...");
        execSync('su -c "pm clear com.roblox.client" > /dev/null 2>&1');
    }
    else {
        socket.emit("device_log", { deviceId: DEVICE_ID, message: `Command ${data.command} executed!`, type: "success" });
    }
});

socket.on("disconnect", () => { console.log("Disconnected. Reconnecting..."); });
EOF

echo -e "${GREEN}=== Starting Tinkerbell Bridge ===${NC}"
while true; do
    node bridge.js
    echo "[!] Connection lost. Reconnecting in 5 seconds..."
    sleep 5
done
