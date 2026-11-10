# Development

## NetPulse (iPhone app)

NetPulse tracks your iPhone's internet connection:

- **Live** – a 0–100 connection strength score with signal bars, the connection type (Wi-Fi, 5G, LTE), the Wi-Fi name, the service provider, response time, jitter and failed checks.
- **Speed** – an on-demand speed test (download, upload, ping, jitter) with history.
- **Consistency** – a response-time timeline over 5 minutes to 24 hours with every drop marked in red, plus uptime and a drop log.
- **Data** – mobile data and Wi-Fi used by day, a data bundle tracker that compares what the phone measured with the balance your provider reports and flags differences, and a log of moves between Wi-Fi and mobile data.

### Run it on your iPhone

1. On a Mac, install Xcode 16 or newer and open `NetPulse/NetPulse.xcodeproj`.
2. Select the **NetPulse** target → **Signing & Capabilities**, pick your Apple ID team, and change the bundle identifier from `com.example.NetPulse` to something unique to you.
3. Plug in your iPhone, choose it as the run destination, and press Run.

A free Apple ID works; apps installed that way need re-installing every 7 days. The app needs iOS 17 or later.

### What to know

- **Strength is a calculated score.** iOS does not let apps read the raw signal level (dBm), so NetPulse scores the connection from how quickly and reliably it responds to a small check every 2 seconds.
- **Wi-Fi name needs two things.** iOS only shares it with apps that have the *Access Wi-Fi Information* capability and location permission. The project already requests both; allow location when the app asks. That capability may not be available to free Apple ID teams. If Xcode reports a signing error about it, remove *Access Wi-Fi Information* under Signing & Capabilities. The app still runs and shows "Not available" for the Wi-Fi name.
- **Provider** is looked up from the connection's public address using Cloudflare (`speed.cloudflare.com/meta`), so it shows the company your traffic leaves through.
- **Data usage is the whole phone's total, not per app.** NetPulse reads the phone's own network counters, which cover all apps and keep counting while NetPulse is closed. iOS does not let apps see which app used the data (Settings › Mobile Service shows that). The counters reset when the phone restarts, so open NetPulse about once a day to avoid missing usage.
- **Wi-Fi band is a label you set.** iOS does not let apps detect the band or move the phone to a different one.
- **Monitoring runs while the app is open.** iOS pauses apps in the background. Turn on "Keep screen awake" on the Live tab for long sessions. Times the app was closed show as blank stretches, not drops.
- **Speed tests use real data** – several hundred MB on a very fast connection.
- All history stays on the phone.

### Where to make changes

| To change | Edit |
| --- | --- |
| Check interval, history length, check servers | `NetPulse/NetPulse/ConnectionMonitor.swift` |
| How strength is scored and how drops are detected | `NetPulse/NetPulse/Models.swift` |
| Speed test length and servers | `NetPulse/NetPulse/SpeedTestEngine.swift` |
| Data usage, bundles and network change log | `NetPulse/NetPulse/DataUsage.swift` |
| Screens | `NetPulse/NetPulse/Views/` |

New Swift files added to the `NetPulse/NetPulse` folder are picked up by Xcode automatically.

### Prototype

`prototype/netpulse-prototype.html` is a browser preview of the four screens using simulated data.

### Build check

`.github/workflows/ios-build.yml` compiles the app on GitHub's macOS runners whenever the app code changes. macOS minutes count 10× against a private repo's free Actions allowance; delete the file if you don't want that.
