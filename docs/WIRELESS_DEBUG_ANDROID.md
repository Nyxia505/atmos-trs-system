# Wireless debugging — Atmos TRS (Android tourist app)

Run and hot-reload the Flutter app on a physical phone over Wi-Fi (no USB after the first pair/connect).

## Prerequisites

- Android **11+** phone (Wireless debugging)
- Same Wi-Fi as this Windows PC
- Android SDK / platform-tools (Flutter doctor already finds them on this machine)
- USB cable only for the optional one-time `usb-tcpip` path, or first-time RSA trust

Package id: `com.atmos.trs`

## Quick start (Android 11+ Wireless debugging)

### On the phone

1. **Settings → About phone** → tap **Build number** 7 times (enable Developer options).
2. **Settings → System → Developer options**:
   - **USB debugging** → ON (still useful)
   - **Wireless debugging** → ON
3. Open **Wireless debugging** → **Pair device with pairing code**.
4. Note:
   - **Pairing** IP:port + 6-digit code
   - **Connection** IP:port shown on the Wireless debugging screen (different port)

### On the PC (repo root)

```powershell
# Optional: see toolchain + devices
.\tools\wireless_debug.ps1 doctor

# 1) Pair (use pairing IP:port from the phone dialog)
.\tools\wireless_debug.ps1 pair -Address 192.168.x.x:xxxxx
# enter the 6-digit code when asked
# or: .\tools\wireless_debug.ps1 pair -Address 192.168.x.x:xxxxx -Code 123456

# 2) Connect (use the Wireless debugging IP:port, NOT the pairing port)
.\tools\wireless_debug.ps1 connect -Address 192.168.x.x:yyyyy

# 3) Run the tourist app
.\tools\wireless_debug.ps1 run
# equivalent: flutter run -d <device_id>
```

After connect, `flutter devices` should list the phone. Hot reload works the same as USB.

## Alternate: classic TCP/IP (any Android with USB once)

```powershell
# Phone plugged in, USB debugging authorized
.\tools\wireless_debug.ps1 usb-tcpip
# unplug cable
.\tools\wireless_debug.ps1 connect -Address <PHONE_IP>:5555
.\tools\wireless_debug.ps1 run
```

Phone IP: **Settings → About phone → Status → IP address**.

## Useful commands

| Command | Purpose |
|--------|---------|
| `.\tools\wireless_debug.ps1 status` | `adb devices` + `flutter devices` |
| `.\tools\wireless_debug.ps1 disconnect` | Drop wireless adb sessions |
| `.\tools\wireless_debug.ps1 run --FlutterArgs '--release'` | Extra flutter flags |

The script sets `ANDROID_HOME` / adds `platform-tools` to **this PowerShell session** only. To make `adb` permanent on PATH:

```powershell
# User PATH (optional, one-time)
[Environment]::SetEnvironmentVariable(
  'Path',
  $env:Path + ';' + "$env:LOCALAPPDATA\Android\Sdk\platform-tools",
  'User'
)
[Environment]::SetEnvironmentVariable('ANDROID_HOME', "$env:LOCALAPPDATA\Android\Sdk", 'User')
```

Restart the terminal after changing User env vars.

## Troubleshooting

| Symptom | Fix |
|--------|-----|
| `unauthorized` | Unlock phone → accept “Allow USB debugging?” |
| `offline` / connect fails | Same Wi-Fi; toggle Wireless debugging off/on; re-pair |
| Pair works, connect fails | You used the **pairing** port — use the main Wireless debugging IP:port |
| Device missing after sleep | Phone Wi-Fi sleep / IP changed → reconnect |
| Flutter doesn’t see phone | `.\tools\wireless_debug.ps1 status` then `flutter devices` |
| Firebase Auth / Google blocked | Add debug SHA fingerprints — see `docs/FIREBASE_ANDROID_SHA.md` |

## Notes

- First install may need USB once if Wireless debugging pairing is flaky.
- Keep Wireless debugging enabled while developing; some OEMs reset it after reboot.
- Do not commit device IPs or pairing codes.
