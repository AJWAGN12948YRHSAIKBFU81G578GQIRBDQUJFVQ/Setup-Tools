    else if (data.command === 'install_apk') {
        var apkUrl = data.payload.url;
        var appName = apkUrl.split('/').pop().split('?')[0];
        if (appName === "app.apk" || appName === "") appName = "APK";

        // PATH AMAN YANG BISA DITULIS SAMA TERMUX & DIBACA SAMA ROOT
        var apkPath = "/data/data/com.termux/files/home/app.apk";

        console.log("[INSTALL] Downloading " + appName + "...");
        socket.emit("device_log", { deviceId: DEVICE_ID, message: "Downloading " + appName + "...", type: "info" });

        exec("curl -L -A 'Mozilla/5.0' -o " + apkPath + " " + apkUrl, (error, stdout, stderr) => {
            if (error) {
                console.log("[INSTALL] Download Failed: " + error.message);
                socket.emit("device_log", { deviceId: DEVICE_ID, message: "Download failed.", type: "error" });
                return;
            }
            
            console.log("[INSTALL] Download complete. Installing...");
            socket.emit("device_log", { deviceId: DEVICE_ID, message: "Download complete. Installing...", type: "info" });

            // INSTALL PAKAI ROOT DARI PATH HOME TERMUX
            exec('su -c "pm install ' + apkPath + '"', (err2, stdout2, stderr2) => {
                if (err2) {
                    console.log("[INSTALL] Installation Failed: " + err2.message);
                    socket.emit("device_log", { deviceId: DEVICE_ID, message: "Installation failed.", type: "error" });
                } else {
                    console.log("[INSTALL] " + appName + " installed successfully!");
                    socket.emit("device_log", { deviceId: DEVICE_ID, message: appName + " installed successfully!", type: "success" });
                }
            });
        });
    }
