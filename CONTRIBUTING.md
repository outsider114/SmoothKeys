# Contributing

Please open an issue before proposing a substantial change. Keep fixes focused
and include a regression test where practical.

On macOS 13 or later with Xcode Command Line Tools:

```bash
bash scripts/build_app.sh
outputs/SmoothKeys.app/Contents/MacOS/SmoothKeys --self-test-keyboard
outputs/SmoothKeys.app/Contents/MacOS/SmoothKeys --self-test
```

The scroll self-test requires a logged-in macOS desktop session. It does not
replace testing with a real mouse, trackpad, and external keyboard. For input
changes, check that the built-in keyboard and trackpad remain unaffected,
including device reconnection and UI/background transitions.

Do not commit local settings, logs, signing identities, certificates, secrets,
or build outputs. Redact personal information in screenshots and issue reports.
Contributions are provided under the repository's CC BY-NC 4.0 license;
preserve applicable third-party attribution and modification notices.
