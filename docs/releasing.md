# Releasing Direction

A release is Direction signed with the Developer ID certificate, notarized by Apple and stapled, in a DMG that is also notarized. It's published to `updates.givedirection.ai`, where Sparkle finds it. The copies we hand out update themselves. A copy built from source has no update feed, so it updates with `git pull` and a new build.

| Where | What's there |
|---|---|
| `https://updates.givedirection.ai/Direction.dmg` | The newest release, for the website's download link |
| `https://updates.givedirection.ai/Direction-0.3.0.dmg` | Each release, by version |
| `https://updates.givedirection.ai/appcast.xml` | Sparkle's feed. Signed copies check it once a day. |

The files are in the R2 bucket `direction-releases`, on the Cloudflare account that has `givedirection.ai`.

## Once, on the Mac you release from

1. **Developer ID certificate.** In Xcode › Settings › Accounts, add the Apple Account of the developer team, then choose the team › Manage Certificates… › + › **Developer ID Application**. Only the team's Account Holder can make one. Check that it's there:
   ```sh
   security find-identity -v -p codesigning     # "Developer ID Application: … (TEAMID)"
   ```
   The certificate and its private key are in your login keychain. Export them as a `.p12` (Keychain Access › My Certificates › right-click › Export) and keep the file in 1Password, so you can release from another Mac.

2. **Notarization.** Make an App Store Connect API key: App Store Connect › Users and Access › Integrations › App Store Connect API › Team Keys › + (Access: Developer). Download the `.p8` file; it downloads only once. Then save the key in your keychain under the profile `direction-notary`:
   ```sh
   xcrun notarytool store-credentials direction-notary \
     --key ~/Downloads/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```
   Then put the `.p8` in 1Password and delete it from Downloads.

3. **Sparkle's update key.** Every update is signed with an EdDSA key that's in your login keychain under the account `givedirection.ai`, and its public half is in `scripts/release.sh`. If this key is lost, copies already out there can't be updated, so keep its backup in 1Password. To set up another Mac from that backup:
   ```sh
   swift package resolve
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account givedirection.ai -f <backup file>
   ```
   The first release on a Mac asks to let `generate_appcast` use the key. Choose Always Allow.

4. **Cloudflare.** Sign in with `cf auth login` (the account that has `givedirection.ai`).

## Each release

```sh
# What's new, in Markdown: the changelog entry. It becomes Sparkle's "What's new", the GitHub release
# and the version's entry on givedirection.ai/changelog (site/README.md says how it's written).
$EDITOR site/changelog/0.3.6.md

scripts/release.sh 0.3.6          # build, sign, notarize, staple, DMG, feed: about 10 minutes
open build/releases/Direction-0.3.6.dmg   # drag it to Applications and open it; this is what people get
scripts/publish-release.sh 0.3.6  # upload the DMG, then the feed; tag v0.3.6, make the GitHub release, deploy the changelog
```

- **The tag and GitHub release.** `publish-release.sh` tags the commit `release.sh` built (`build/releases/Direction-<version>.commit`) as `v<version>` and pushes only the tag. Then it makes the GitHub release, with the changelog entry as its notes and the DMG attached, and redeploys the site with the new changelog entry. Without `site/changelog/<version>.md` it publishes the update and stops there.

- **Versions.** The version you give is what people see. The build number is the number of commits on `HEAD`, so it goes up with every release. Sparkle compares build numbers, so release from the same branch each time.
- **`build/releases`** keeps every DMG and `appcast.xml`, and `generate_appcast` rebuilds the feed from what's there. If the folder is lost, the next feed lists only the new release. Sparkle only needs the newest, so this is fine.
- **Dry run.** `DIRECTION_SIGNING_IDENTITY=- scripts/release.sh 0.3.0` signs ad hoc and stops before notarizing. It checks the packaging without a certificate.
- **When Apple says no**, the notary log is in `build/dist/notary-log-*.json`. It names each file and what's wrong with it.

## What's in a signed copy

`scripts/build-app.sh` puts Sparkle.framework in `Contents/Frameworks`. It also takes out the search paths SwiftPM leaves into the build folder, so the app doesn't carry them. `scripts/release.sh` then:

- writes the version, `SUFeedURL`, `SUPublicEDKey` and `SUEnableAutomaticChecks` into the copy's Info.plist;
- signs from the inside out with the hardened runtime and a secure timestamp: Sparkle's Installer and Downloader services, Autoupdate and Updater.app, the framework, the resource bundles, the `direction` helper (`dev.direction.editor.helper`), and then the app.

Direction needs no entitlements. It isn't sandboxed, it runs the editor, Python and ffmpeg as their own processes, and it asks for speech recognition through its Info.plist.

A copy signed with the Developer ID is a different app to macOS than one built from source. So the first time you open one after the other, macOS asks again for speech recognition and for your folders, and Direction asks again for the OpenRouter key in the keychain.
