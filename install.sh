#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

LICENSE_KEY=$1

if [ -z "$LICENSE_KEY" ]; then
    echo -e "${RED}=== Tinkerbell Bridge Installer ===${NC}"
    echo "Please enter your License Key from the Dashboard:"
    read -p "Key: " LICENSE_KEY
fi

if [[ ! "$LICENSE_KEY" =~ ^TINKERBELL-[A-Z0-9]{4}-[A-Z0-9]{4}$ ]]; then
    echo -e "${RED}Invalid Key Format. It should look like TINKERBELL-XXXX-XXXX${NC}"
    exit 1
fi

echo -e "${GREEN}=== Installing Required Packages ===${NC}"
pkg update -y > /dev/null 2>&1
pkg install nodejs -y > /dev/null 2>&1

echo -e "${GREEN}=== Setting Up Bridge Environment ===${NC}"
cd ~
mkdir -p tinkerbell-bridge
cd tinkerbell-bridge

npm init -y > /dev/null 2>&1
npm install socket.io-client > /dev/null 2>&1

if [ ! -f device_id.txt ]; then
    MODEL=$(getprop ro.product.model | tr ' ' '-')
    RAND=$(shuf -i 1000-9999 -n 1)
    echo "${MODEL}-${RAND}" > device_id.txt
fi

cat << EOF > bridge.js
const { io } = require("socket.io-client");
const fs = require("fs");
const { execSync } = require("child_process");

const VPS_URL = "https://predict-banked-exclusive.ngrok-free.dev"; 
const LICENSE_KEY = "$LICENSE_KEY";

let DEVICE_ID = "";
const idFile = "device_id.txt";

if (fs.existsSync(idFile)) {
    DEVICE_ID = fs.readFileSync(idFile, "utf8").trim();
} else {
    let model = "RF-Device";
    try {
        model = execSync("getprop ro.product.model").toString().trim().replace(/\s+/g, "-");
    } catch (e) {}
    const randomSuffix = Math.floor(Math.random() * 9000 + 1000);
    DEVICE_ID = \`\${model}-\${randomSuffix}\`;
    fs.writeFileSync(idFile, DEVICE_ID);
}

console.log("Device ID: " + DEVICE_ID);
console.log("Connecting to Tinkerbell Dashboard...");

const socket = io(VPS_URL, {
    reconnection: true,
    reconnectionDelay: 2000,
    auth: { licenseKey: LICENSE_KEY, deviceId: DEVICE_ID }
});

socket.on("connect", () => {
    console.log("[✓] Connected to Dashboard!");
    socket.emit("device_connect", {
        ip: "Cloud Phone",
        maxPackages: 10
    });
});

socket.on("connect_error", (err) => {
    console.log("[!] Connection Failed: " + err.message);
    if (err.message.includes("Authentication failed") || err.message.includes("Invalid License Key") || err.message.includes("Device limit reached") || err.message.includes("License not activated")) {
        console.log("[!] Please check your License Key or reset it from the dashboard.");
        process.exit(1);
    }
});

socket.on("execute_command", (data) => {
    console.log(\`[CMD] Received: \${data.command}\`);
    socket.emit("device_log", {
        deviceId: DEVICE_ID,
        message: \`Command \${data.command} executed!\`,
        type: "success"
    });
});

socket.on("disconnect", () => {
    console.log("Disconnected. Reconnecting...");
});
EOF

echo -e "${GREEN}=== Starting Tinkerbell Bridge ===${NC}"
while true; do
    node bridge.js
    echo "[!] Connection lost. Reconnecting in 5 seconds..."
    sleep 5
done
