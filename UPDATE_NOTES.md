# Al-Amin Baitul Maal - update notes

## Set-up after copying these files
1. `flutter pub get`  (a new package, `crypto`, is used for Wi-Fi sync)
2. `flutter analyze`
3. `flutter test`
4. Run: `flutter run` (Android / Windows / Chrome)

I could not run Flutter in my environment. Nothing here has been compiled or executed yet:
please run steps 2 and 3 and send back any error text.

## Latest round (analyzer clean-up)
- All 49 tests passed; the analyzer reported no errors. Fixed the analyzer warnings: dead code and unneeded `!` in the cloud sync
  download, unused helpers/fields/imports, a few "BuildContext after await" and brace-style hints.
- Replaced the deprecated Radio list tiles (Cash/Bank, Due/Advance, user pick) with `SimpleRadioTile` (lib/screens/simple_radio.dart),
  so a future Flutter update cannot break them. Same look and behaviour.
- Removed an unused old copy of the Qarz borrower ledger screen (qarza_borrower_ledger.dart); nothing used it.
- Left as is: info notices about older code style that do not affect behaviour.

## Slow first launch on the phone
A first Android build with Firebase, Drift/SQLite and native assets commonly takes 5-10 minutes; later runs should take 1-2 minutes.
If every run takes ~10 minutes: do not run `flutter clean` between runs; keep the project out of OneDrive-synced folders; exclude the
project, `C:\src\flutter`, `%LOCALAPPDATA%\Pub\Cache` and `%USERPROFILE%\.gradle` from antivirus real-time scanning; make sure the
internet is reachable (the SQLite download hook retries when it cannot reach github.com); and run `flutter run -v` to see which step is slow.

## Previous round (dashboard, funds, reports, vouchers)
- Home screen: slimmer one-row header, tighter spacing, Today's Received as three small cards in one row, so everything fits at once.
  Qarz-e-Hassanah is centred and blue.
- Funds Ledgers screen (swipe left) now also shows the income / expense charts.
- Reports: new "All Time" period, selected by default (first record to today). Other presets and the date-range picker still work.
- Total Funds register: receipts can be opened, viewed and printed. Qarz, Sadqa-e-Fitr expenditure and Zakaat expenditure show
  "You are not authorised to access this transaction."
- Zakaat expenditure forms (one-time and monthly): three "Verified by" selectors added again (no Reason / Verification report); they
  print on the voucher. The Qarz and Zakaat verifier rows no longer overflow (stacked on phones, side by side on wide screens).
- Reprint error "Unable to guess the image type": a stored signature held the image bytes as text ("[137,80,78,71,...]"). Printing now
  recovers the image from that form (or base64), and prints a blank signature box if a value is not an image.

## Previous round (analyzer / test results)
- `flutter analyze`: no errors. Fixed the warnings that came from my changes (unused drawer helper and import in main.dart,
  doc comment in chart_data.dart). The remaining notices are in older code: deprecated Radio `groupValue`/`onChanged`
  (still works), unused private helpers, and BuildContext-after-await hints. They do not affect behaviour.
- `flutter test`: 42 passed, 1 failed. The failure was a wrong total in my own test (income is 1,600 + 5,000 = 6,600, not 5,600);
  the app code was correct. The test is corrected.

## Previous round (refresh rate and receipt forms)
- Chrome refreshed too often: screen reloads caused by sync are now merged and spaced at least 20 seconds apart, the home screen keeps
  showing the last figures while it reloads (no spinner flicker), and the browser build polls the cloud every 20 s instead of every 5 s.
- Receipt forms (Zakaat, Sadqa-e-Fitr, General Donation, Other Income, Box Collection) use the new layout: numbered collapsible sections
  (1. Donor Details, 2. Payment Details, 3. Remarks), labels above white bordered boxes, "*" on required fields, a narrower date box
  and Cash / Bank Transfer round buttons inside one box (unselected until the user picks).
- The donor name on these receipts is pre-filled with "Abdullah" and is selected on tap so typing replaces it; it can be changed or cleared.
- These receipts now print the rupee sign instead of "INR".

## Previous round (delete / sync / backup)
- IMPORTANT: install this version on EVERY device (phones, Windows, Chrome) before testing a global delete. Older versions
  do not understand the new reset marker.
- Delete entire database: the reset marker is published first, then this device is wiped (and checked: it fails loudly if any
  record is left), then Firebase is cleaned. Every cloud change is now stamped with a database generation; devices ignore
  anything from an older generation, so deleted data (or half-deleted data) can no longer come back as "ghost" records.
- Other devices: a live listener on the reset marker clears an online device within moments; an offline device clears itself
  before it uploads or downloads anything when it reconnects. The open screens now refresh by themselves after any sync, and
  after a remote reset the app returns to the home screen with a message.
- Approved transactions showing as unapproved on the laptop: the likely cause was a partial download of the cloud while it was
  being cleaned (transactions arrived, their approval records had already been deleted, and the app treats a missing approval
  as "pending"). Generation filtering now prevents this. I could not reproduce it without your devices, so please test.
- A device that used "Delete local data only" stays paused (it ignores the cloud, including resets) until you press
  Resume Cloud Sync on the Data Management page.
- Wi-Fi sync refuses to connect two devices that are on different database generations.
- Chrome backup before delete: the browser's Save-As window now opens so you choose where to save (Chrome/Edge). Delete only
  continues after the file is written; cancelling the window cancels the delete. Firefox/Safari fall back to a normal download.
  The delete flow now has an explicit "Choose backup location" step.

## Previous round (Reports window and restore fix)
- Restore backup: fixed the error "Invalid argument (params[3]) ... Instance of 'DateTime'". Dates are now written back exactly as
  they were stored (numbers stay numbers, text stays text). Restore still checks the whole backup first and keeps a safety copy.
- Reports window redesigned: menu button (top left) opens a side menu: 1 Detailed Transactions, 2 Generate Formal Balance Sheet,
  3 Income & Expense Charts, then Qarz Borrowers, Recurring Monthly Zakaat, Deleted Receipts, Disproved Transactions, Filters, Summary.
  The main page is now just the summary cards.
- One bordered date-range box (tap to pick a range; Today / This Month / Last Month / This Year shortcuts) on every Reports view.
- Detailed Transactions table: columns are only as wide as their text, long names wrap, amounts coloured, status shown as icon + text.

## Previous round
- Reconciliation: Cash / Bank figures now update on screen instantly after saving (no spinner, no wait).
- Reports: Edit and Delete of a transaction now accept the Admin password as well as the Superuser password.
- Charts (Reports window and Total Funds, below the ledgers): income by month (stacked by head), total income by head,
  expenses by month (stacked), total expenses by head. Only approved transactions. Qarza = loans issued;
  Qarz repayments and waivers are not counted as income or expense.
- Cash / Bank Transfer starts unselected on every income receipt (Monthly Donation, General Donation, Box Collection,
  Other Income, Zakaat, Sadqa-e-Fitr, Qarz repayment). Saving without choosing shows a message.
- Qarz waiver: you now type the amount to waive (limited to the outstanding Qarz and the available Zakaat). The voucher shows
  initial amount borrowed, returned so far, waived earlier, amount waived, and balance after waiver (also when reprinted).
- Zakaat forms (one-time and monthly) no longer have Reason or Verification / Verified-by fields, and the voucher no longer prints them.
  Old records keep any values already saved.

## Earlier changes
- Restore backup: signature images stored in an older format ("[137,80,...]" text) are now read correctly.
  Restore still checks the whole backup first and keeps a safety copy; nothing is deleted if the check fails.
- Rupee sign: PDFs now embed a font that contains the rupee sign (assets/fonts/DejaVuSansCondensed*.ttf).
- Receipts: compact thermal-roll receipts (58 mm default, 80 mm selectable in menu > Receipt Paper). Number and date
  share one row. Vouchers (Zakaat, Qarz, Expense, Waiver) stay A4.
- Reports: monthly chart with a thin line for every income and expense type and two thick lines for total income
  and total expense. Tap a type in the legend to hide or show it.
- Wi-Fi Sync (menu > Wi-Fi Sync): direct sync between two devices on the same Wi-Fi or hotspot.
  Android <-> Android and Windows <-> Android. One device taps START RECEIVING, the other enters the address and code.
- Home: swipe left for the Funds Ledgers screen.
- Earlier changes: single-screen home with menu drawer, Islamic background, 3D buttons, comma-grouped amounts,
  word-case names/addresses, Reports open with Admin or Superuser password.

## Wi-Fi sync notes
- Windows must allow the app through the firewall the first time it starts receiving.
- Port 8765. Both devices need the same Wi-Fi/hotspot. Not available in the web build.
- Devices prove they know the 6-digit code (HMAC), but traffic on the network is not encrypted. Use a network you control.
- Changes go straight between devices and are merged with the same rules as Firebase sync; later cloud sync will not duplicate them.
- With 3+ devices, sync each pair.

## Not verified
- Compilation, `flutter analyze`, `flutter test`.
- Printing on a real thermal printer (paper width, margins).
- Wi-Fi sync between real devices, including Windows firewall behaviour.
