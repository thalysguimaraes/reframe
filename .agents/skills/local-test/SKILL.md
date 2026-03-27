---
name: local-test
description: Build the latest local Reframe macOS app, validate the embedded system extension, and replace /Applications/Reframe.app for manual testing. Use when asked to install a fresh local build into Applications, refresh the tester's app bundle, or prepare a local bundle that satisfies the app's /Applications requirement.
---

# Local Test

Use this skill when the user wants the current local Reframe build installed in
`/Applications` so the app and embedded virtual camera system extension can be
tested outside Xcode.

## Workflow

1. Work from the repo root.
2. Run `./.agents/skills/local-test/scripts/build_and_install.sh`.
3. Let the script handle the full loop:
   - run `xcodegen generate`
   - build the `Reframe` scheme
   - validate the built bundle with `./Scripts/validate-sysext.sh`
   - stop any running `Reframe` process
   - replace `/Applications/Reframe.app`
   - verify the installed bundle signature
4. Report the installed version/build plus the exact failure if signing,
   provisioning, or the app group configuration blocks the build.

## Defaults

- Default build configuration is `Release` because this is the closest local
  equivalent to the shipped app.
- Override with environment variables only when the task explicitly calls for
  it:
  - `CONFIGURATION=Debug`
  - `DERIVED_DATA_PATH=/custom/path`
  - `INSTALL_PATH=/Applications/Reframe.app`
  - `LAUNCH_AFTER_INSTALL=1`

## Commands

```bash
./.agents/skills/local-test/scripts/build_and_install.sh
```

```bash
CONFIGURATION=Debug ./.agents/skills/local-test/scripts/build_and_install.sh
```

## Notes

- Do not invent another install location unless the user explicitly requests it;
  `SystemExtensionManager` expects the app bundle to live under
  `/Applications`.
- Prefer the bundled script over ad-hoc shell snippets so the build, validation,
  and replacement steps stay consistent across runs.
