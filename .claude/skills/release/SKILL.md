---
name: release
description: Cut a Gold Master Pro release — version bump, tag push, and verifying the GitHub Actions build attaches the APK and web zip. Use when tagging a new version, publishing an APK for the tester, or diagnosing a release/tag that produced no assets.
---

# Cutting a GMP release

## Before you tag

**Always run `flutter analyze && flutter test` and get both green.** The
release workflow is not a CI gate — it only builds. A tag on code that
doesn't compile costs a failed run *and* a tag deletion that leaves an
unpublished draft release behind.

CI pins Flutter **3.44.7** — check new deps against that, not just against
the local Flutter version.

## The procedure

1. Bump `version:` in `pubspec.yaml` **and** `AppConstants.appVersion` —
   both, in the same commit. A test asserts the version *format*, not the
   value, so a missed bump will not fail the suite.
2. Commit and push.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`

The tag push triggers `.github/workflows/release.yml`, which builds and
attaches `app-release.apk` + `gmp-web.zip` (~6 min).

## Verifying

- Download URL pattern: `releases/download/vX.Y.Z/app-release.apk`
- Verify the assets landed via the public
  `releases/expanded_assets/<tag>` page.

## Traps

- **Deleting a tag turns its release into an unpublished draft** — it does
  not disappear. Clean the draft up manually if you re-tag.
- `deploy-web.yml` needs GitHub Pages enabled (currently not). Its failure
  on every push is expected — don't chase it.
