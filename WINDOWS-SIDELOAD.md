# Build the IPA and sideload it — from Windows

Apple's compiler only runs on macOS, so the app is built on a free GitHub-hosted Mac,
then signed and installed from your Windows PC with Sideloadly.

## 1. Put the project on GitHub (once)

1. Sign in at github.com → **New repository** → name it (e.g. `wallet-ios`) → **Private** → Create.
2. Unzip `Wallet-iOS.zip`. Open the `LedgerWallet` folder — you should see
   `LedgerWallet.xcodeproj`, `LedgerWallet`, `.github`, `README.md`.
3. On the new repo page click **uploading an existing file**, select everything *inside*
   that folder (including `.github`) and drag it in → **Commit changes**.

   If the `.github` folder didn't come through (the Actions tab says there are no
   workflows): **Add file → Create new file**, type the name
   `.github/workflows/build-ipa.yml`, paste the contents of that file, commit.

   Or with Git for Windows, from inside the `LedgerWallet` folder:
   ```
   git init -b main
   git add .
   git commit -m "Wallet"
   git remote add origin https://github.com/<you>/wallet-ios.git
   git push -u origin main
   ```

## 2. Build the IPA

1. Repo → **Actions** tab → enable workflows if asked.
2. **Build IPA** → **Run workflow** → Run. It takes about 3–6 minutes.
3. Open the finished run (green tick) → **Artifacts** → download **Wallet-ipa**.
   GitHub hands you a .zip; extract it to get **Wallet.ipa**.

   A red ✗ means the build failed; open the run and the failed step shows the error.

## 3. Install on your iPhone with Sideloadly (Windows)

1. Install **iTunes** and **iCloud** from Apple's website (the web-download versions, not
   the Microsoft Store ones — Sideloadly needs them to talk to the phone).
2. Install **Sideloadly** from sideloadly.io.
3. Plug the iPhone in with a cable, unlock it, tap **Trust This Computer**.
4. In Sideloadly: drag in **Wallet.ipa**, pick your iPhone, enter your Apple ID → **Start**.
   (A throwaway Apple ID works fine. Sideloadly signs the app with a free certificate.)
5. On the iPhone:
   - iOS 16+: **Settings → Privacy & Security → Developer Mode** → On → restart → confirm.
   - **Settings → General → VPN & Device Management** → your Apple ID → **Trust**.
6. Open **Wallet** from the home screen.

## Things to know

- **7-day limit.** Apps signed with a free Apple ID stop opening after 7 days. Re-run
  Sideloadly with the same IPA to renew (your balances are kept). A paid Apple Developer
  account ($99/yr) signs for a year.
- A free Apple ID can have at most 3 sideloaded apps installed at once.
- **Updating the app:** replace the files in the repo (or push), run the workflow again,
  install the new IPA over the old one. Data is kept as long as the bundle ID stays
  `com.jckfeet.wallet`.
- Nothing in the build needs your Apple ID or any secret — the IPA is unsigned until
  Sideloadly signs it on your PC.
