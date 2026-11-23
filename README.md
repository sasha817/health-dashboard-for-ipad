# Health for iPad

SwiftUI dashboard (iPad, landscape-first) for your own Garmin Connect data, using the
[Garmin Connect Personal API](https://developer.garmin.com/gc-developer-program/personal/personal-api).
Blood pressure comes from Apple Health (the Personal API has none).

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
open HealthForiPad.xcodeproj
```

Pick your iPad, set your Team under Signing & Capabilities, run. In the app: Settings → paste your
personal API key (stored in the Keychain only). "Use demo data" works without a key.

## Tests

```bash
xcodebuild test -project HealthForiPad.xcodeproj -scheme HealthForiPad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' CODE_SIGNING_ALLOWED=NO
```

Unit tests cover the Garmin response parser and calendar-day handling (`Tests/ParsingTests.swift`).

## Notes

- Garmin data is cached on the device. A chunk of days counts as downloaded only after every request for it succeeded; failures are shown and retried; see Settings → Data & history for history depth and background download.
- Ideas and known API limits: [ROADMAP.md](ROADMAP.md).
