---
name: update-dmg
description: Generate and publish an updated Reframe DMG from the current local app build, and replace the GitHub release asset manually so Releases serves the newest installer. Use when asked to refresh the downloadable installer or replace a stale DMG on an existing release.
---

# Update DMG

Use this skill when the downloadable installer on GitHub Releases needs to be
refreshed from a local build.

## Current Repo Expectation

- `README.md` tells users to download a DMG from GitHub Releases.
- The DMG is built locally and uploaded manually with `gh`.
- Future runs of this skill should keep the published release asset aligned
  with the latest local build.

## Workflow

1. Inspect the current release/tag state and the existing DMG asset.
2. Build or reuse the local app bundle you want to ship.
3. Generate the DMG with
   `./.agents/skills/update-dmg/scripts/build_release_dmg.sh`.
4. Publish or replace the DMG asset with
   `./.agents/skills/update-dmg/scripts/publish_release_asset.sh`.
5. Verify that the latest GitHub release exposes the fresh DMG asset.

## Commands

```bash
./.agents/skills/update-dmg/scripts/build_release_dmg.sh /Applications/Reframe.app build/Reframe-0.1.0.dmg
```

```bash
./.agents/skills/update-dmg/scripts/publish_release_asset.sh v0.1.0 build/Reframe.dmg
```

## Notes

- Prefer the built-in `hdiutil` path over third-party DMG tooling.
- When Apple notarization credentials are available, notarize and staple the
  DMG in the same run.
- Match the existing release asset name when replacing a published DMG so
  `gh release upload --clobber` overwrites it cleanly.
