# xTR

**xTR** is a lightweight Android mobile app that embeds **Xray** and uses the **VLESS + Reality** protocol for secure tunneling.
It is built for fast deployment and simple configuration: add YAML files with your server credentials, build the APK, and run.

---

## App Overview

* Engine: embedded `libxray.so` binary inside `app/src/main/jniLibs/arm64-v8a/`
* Protocol: `vless` outbound with `reality` stream settings
* Tunnel type: Android `VpnService` + local proxy forwarding
* Inbound proxy: local SOCKS at `127.0.0.1:10808` and HTTP at `127.0.0.1:10809`
* Outbound traffic: routed through Xray to your configured VLESS server

This app is not a browser or system VPN manager; it starts a local tunnel engine and keeps the session running while active.

---

## Technical details

### Tunneling and engine

xTR uses Android's `VpnService` to create a TUN interface and redirect device traffic through the embedded Xray process.
The app generates a runtime `config.json` from YAML asset files and starts Xray with that configuration.

The local proxy stack is:

* `socks` inbound on port `10808`
* `http` inbound on port `10809`
* `vless` outbound with `reality` settings

This means the app can work with apps that support SOCKS or HTTP proxies, and the tunnel is established using Xray's protocol engine.

### Supported protocols

* VLESS
* Reality stream settings
* TLS-style masking with `servername`, `public-key`, and `short-id`
* `flow` support (for example `xtls-rprx-vision`)

---

## Compatibility

* Tested on more than 20 Android devices
* Verified on Samsung Galaxy series and Google Pixel devices
* Works on Android 7.0+ (API 24+) with `arm64-v8a`
* Requires devices that support `VpnService`

---

## Configuration files

xTR loads configuration files from `app/src/main/assets`.
Put YAML files there and name them like `config1.yaml`, `config2.yaml`, or any other `.yaml`/`.yml` filename.

The app scans the assets folder for YAML files and loads them in alphabetical order.
You can switch between server configs while the service is active using the `CHANGE SERVER` button.

### Required YAML fields

The app parses the following values from the YAML content:

* `uuid`
* `server`
* `port`
* `servername`
* `flow`
* `public-key`
* `short-id`

A Clash Verge-style YAML layout is compatible as long as those values exist in the file.

Example config content:

```yaml
proxies:
  - name: client-example-1
    type: vless
    server: 111.22.3.44
    port: 443
    uuid: xxxxxxxx-yyyy-yyyy-aaaa-exampleexample
    network: tcp
    tls: true
    udp: true
    servername: example.com
    flow: xtls-rprx-vision
    client-fingerprint: chrome
    reality-opts:
      public-key: xxxxxxxxyyyyyyyyaaaaexampleexample
      short-id: exampleexample

proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - client-example-1

rules:
  - MATCH,Proxy
```

Add the YAML files to `app/src/main/assets` before building.

---

## Installation

### Requirements

* Android Studio
* Android SDK for API 24+
* A compatible Android device or emulator
* Your Xray / VLESS / Reality credentials

### Build steps

1. Clone the repository:

   ```bash
   git clone https://github.com/alexshescp/xtr.git
   ```

2. Open the project in Android Studio
3. Add your `.yaml` config files to `app/src/main/assets`
4. Build the APK via `Build → Build APK(s)`
5. Install the APK on your Android device

---

## Server-side installation

For server-side deployment and client management, see `server-side/readme.md`.

---

## Project structure

* Kotlin-based Android application
* Gradle build system
* Simple UI with connect/stop and server switching
* Asset-driven configuration

---

## Disclaimer

This project is provided for educational and personal use only.
Users are responsible for complying with local laws and regulations.

---

## License

MIT License
