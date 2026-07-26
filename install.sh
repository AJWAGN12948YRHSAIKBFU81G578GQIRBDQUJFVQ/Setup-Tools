#!/bin/bash

GREEN='\033[0;32m'
NC='\033[0m'

export DEBIAN_FRONTEND=noninteractive

echo -e "${GREEN}=== Tinkerbell Bridge Installer ===${NC}"
echo "Fixing & Updating packages..."
dpkg --configure -a
pkg update -y
pkg upgrade -y -o Dpkg::Options::="--force-confold"

echo "Installing Node.js..."
pkg install nodejs -y -o Dpkg::Options::="--force-confold"

echo "Setting up storage..."
termux-setup-storage

echo "Creating bridge folder..."
cd ~
mkdir -p tinkerbell-bridge
cd tinkerbell-bridge

echo "Initializing NPM..."
npm init -y

echo "Installing Socket.io Client..."
npm install socket.io-client

if [ ! -f device_id.txt ]; then
    MODEL=$(getprop ro.product.model | tr ' ' '-')
    RAND=$(shuf -i 1000-9999 -n 1)
    echo "${MODEL}-${RAND}" > device_id.txt
fi

cat << 'EOF' > bridge.js
const { io } = require("socket.io-client");
const fs = require("fs");
const { execSync } = require("child_process");

const VPS_URL = "GANTI_DENGAN_URL_NGROK_LU"; 

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
    DEVICE_ID = `${model}-${randomSuffix}`;
    fs.writeFileSync(idFile, DEVICE_ID);
}

console.log("Device ID: " + DEVICE_ID);
console.log("Connecting to Tinkerbell Dashboard...");

const socket = io(VPS_URL, {
    reconnection: true,
});

socket.on("connect", () => {
    console.log("[✓] Connected to Dashboard!");
    socket.emit("device_connect", {
        deviceId: DEVICE_ID,
        ip: "Cloud Phone",
        maxPackages: 10
    });
});

socket.on("execute_command", (data) => {
    console.log(`[CMD] Received: ${data.command}`);
    socket.emit("device_log", {
        deviceId: DEVICE_ID,
        message: `Command ${data.command} executed!`,
        type: "success"
    });
});

socket.on("disconnect", () => {
    console.log("Disconnected...");
});
EOF

echo -e "${GREEN}Starting Tinkerbell Bridge...${NC}"
node bridge.js
