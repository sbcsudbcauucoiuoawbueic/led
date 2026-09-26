# Wallet — iOS

A crypto wallet UI for iPhone. SwiftUI shell hosting the interface in a `WKWebView`,
with a native network bridge so live prices work from a `file://` page.

## No Mac? Build on Windows

See **WINDOWS-SIDELOAD.md**: GitHub Actions builds `Wallet.ipa` on a hosted Mac
(`.github/workflows/build-ipa.yml`), and Sideloadly installs it from Windows.

## Run it

```bash
open LedgerWallet.xcodeproj
```

1. Select the **Wallet** scheme and your iPhone (or any iPhone simulator).
2. For a real device: target **Wallet → Signing & Capabilities → Team**, pick your
   Apple ID. Change the bundle id if `com.jckfeet.wallet` is taken.
3. ⌘R.

Deployment target is iOS 16.0, portrait-only, iPhone-only.

## Layout

```
LedgerWallet/
├── LedgerWallet.xcodeproj/
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/Wallet.xcscheme
└── LedgerWallet/
    ├── WalletApp.swift          @main, forces dark mode
    ├── WalletWebView.swift      WKWebView host + URLSession network bridge
    ├── Assets.xcassets/         app icon + accent colour
    └── www/
        └── index.html           the entire UI (one self-contained file)
```

`www` is a **folder reference** (blue in Xcode), so the whole directory is copied
into the bundle and `Bundle.main.url(forResource:"index", withExtension:"html", subdirectory:"www")`
resolves. If you replace it, keep it a folder reference — a yellow group will break the path.

## Editing the UI

All of it is `LedgerWallet/www/index.html`. Open that file in a browser to iterate
without rebuilding; on a desktop browser (mouse, window ≥500px wide) it draws itself inside a
phone bezel scaled to the window height. On any touch device it fills the screen edge to edge. Then ⌘R in Xcode to see it on device.

## Status bar

The app does not draw a status bar — iOS's real one shows through. The web content
runs edge-to-edge (`.ignoresSafeArea()` plus `contentInsetAdjustmentBehavior = .never`),
and the page positions itself with `env(safe-area-inset-top/bottom)`. That is why the
header sits correctly under the Dynamic Island and the tab bar clears the home indicator.

## Hero art

The dotted gradient behind the headline on Home, Earn and Card is painted on a `<canvas>`:
two small light maps sampled from the reference (lit gaps and dark holes) are scaled up, and a
rotated lattice of round holes is punched through the lit layer. It starts at the very top of
the screen, behind the status bar. Header buttons are frosted glass (`backdrop-filter`), and
once you scroll a blurred dark fade appears under the status bar.

## Live prices

`refresh()` in the page pulls `api.coingecko.com/api/v3/coins/markets` for every token
in `CATALOG`.

Because the page is loaded from `file://`, a normal `fetch()` would be refused by CORS.
Instead the page posts `{id, url}` to the `net` script-message handler; `WalletWebView`
fetches it with `URLSession` (no CORS) and calls `window.__netResolve(id, ok, body)`.
In a plain browser the same code path falls back to `fetch()`.

Prices refresh on launch, when the app returns to the foreground, on pull-to-refresh, and
when you tap the "Updated …" line. The last good response is cached in `localStorage`, and
bundled snapshot prices back it up, so the wallet still totals correctly offline — it just
shows "Couldn't update prices".

No API key is needed. CoinGecko's keyless tier allows as few as **5 calls a minute**, so
every CoinGecko request goes through a queue (`cgGet`) capped at 5/min and spaced 1.5 s
apart. A refresh is one top-250 markets call (prices + market list); trending, global cap
and Fear & Greed refresh every 10 minutes. Charts come from Coinbase's public candles
(no key, far higher limits), falling back to CoinGecko and then CryptoCompare. If all
fail the chart says so rather than drawing anything invented.

## Haptics

Other bridges: `open` sends https links (Ledger Support, shop, Discover providers) to Safari,
and `share` turns *Export data* into a .json file in the iOS share sheet. Links opened with
`window.open` also go to Safari. A `haptic` bridge maps `light`, `medium`, `selection`, `success` and `warning`
to the Taptic Engine. Used on tab switches, keypad taps, chart scrubbing, pull-to-refresh
and saves.

## What it does

- **Home** — empty state until you add crypto, then *Total balance* with 24h change,
  a "Updated N min ago" sync line, an eye toggle to hide amounts, and **Buy · Swap · Send**.
  Pull down to refresh (the page stretches and springs back, no spinner). Tap the balance for Analytics.
- **Token pages** — real price history for 1D / 1W / 1M / 1Y / ALL, from Coinbase first,
  then CoinGecko, then CryptoCompare. Charts are cached on the device and shown offline
  with their age.
  Drag across the chart to scrub (price and time update, with haptic ticks). Your own
  buys/sends show as dots on the line; the slider icon hides them. Your balance card shows
  average entry price and unrealised/realised return.
- **Analytics** — portfolio value over time (current holdings at historical prices),
  profit & loss, asset allocation, link to history.
- **Transaction history** — every add, buy, send and edit, grouped by day.
- **Market** — live top 100, total market cap, Fear & Greed mood, trending, favourites.
- **Swap** — pick what to send (from your balances) and what to receive, type an amount or
  *Use max*, flip with ⇅. *View quotes* shows the live market rate; *Swap* moves the balance
  across and logs it in history (a send at market price plus a receive at market price, so
  P&L stays correct). The Swap button on a token page pre-fills that token.
- **Search** — real search across the catalog and the live top 100.
- **Settings** (gear on the profile screen), laid out like Ledger Wallet:
  - *General*: Preferred currency (USD, EUR, GBP, CAD, AUD, JPY, CHF — converted with
    CoinGecko exchange rates), Date format, App lock (4-digit passcode), Regional market
    indicator (Eastern shows increases in red), Recommendations, Haptic feedback, Hide balances.
  - *Help*: Ledger Support link, Export data, Import data, Clear cache (keeps balances),
    Reset settings (keeps balances), Reset Wallet (erases everything).
  - *About*: version, where the data comes from, what is stored.
- **Other buttons**: Backup exports your data, Help opens Settings › Help, Connect / Add a
  Ledger explains that device pairing isn't possible here and offers to add crypto by hand,
  Buy a Ledger / Buy now / Referral / Card / Discover providers open their Ledger pages,
  Simulate rewards estimates yearly rewards on what you hold at the Earn rates.

## Your holdings

Stored in `localStorage` inside the app's own data store (survives relaunch, wiped if
you delete the app):

| key | contents |
|---|---|
| `wallet.holdings` | balances, `{"BTC": 0.5}` |
| `wallet.ops` | history: `{t, s, type: in/out, label, amt, px}` — `px` is the price used for cost basis |
| `wallet.prices`, `wallet.top`, `wallet.trending`, `wallet.global`, `wallet.fng` | last good API responses, for offline |
| `wallet.hide`, `wallet.favs`, `wallet.chartActivity` | preferences |
| `wallet.settings` | Settings: currency, date format, market indicator, toggles, passcode hash |
| `wallet.fx` | exchange rates for the preferred currency |

The app lock is a privacy screen, not encryption: it keeps people from casually opening the
app, but the data itself sits unencrypted in the app's storage.

P&L uses the **average-cost method**: buys raise your cost basis at the entry price you
enter (defaults to market); sends and sales realise gain or loss against the average.
Deleting an asset removes its history too, so a mistaken entry leaves no phantom P&L.
Balances saved by older builds are migrated into history automatically on first launch.

Add via the **+** next to *Crypto*, **Buy**, or **Add … to wallet** on any token screen.
Buy lets you set the price you paid. Tap your balance card on a token page to edit or
delete it.

This tracks balances you type in. It does not hold keys, connect to a chain, or move
funds — there is nothing here that can spend anything.

## Notes

- Type is Inter (UI) and Inter Tight (headlines), SIL OFL 1.1, bundled in `www/fonts/` —
  fitted against a screenshot of the real app. The headline size is `--hero` at the top
  of the stylesheet if you want to nudge it.
- Coin logos: 23 bundled from `cryptocurrency-icons` (CC0, in `www/icons/`), everything
  else loaded from CoinGecko's image URLs, with drawn geometric fallbacks when offline.
  The app icon, device art and card art are original.
- Market data beyond the live price call is a snapshot captured from the reference
  recording, so the ranked list reads realistically before the first refresh lands.
