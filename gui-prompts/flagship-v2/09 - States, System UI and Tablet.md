Using the **AERIS design system already created in this project**, finish the redesign so it is production-complete. Show both Dark and Light.

## 1. States for the key screens (Home, Activity, Transaction detail, Insights, People, Settings)
- **Loading**: skeleton shapes that match the real layout (no spinners on whole screens).
- **Empty**: a short, encouraging explanation + one clear action (e.g. Activity: "No transactions yet — turn on SMS reading or add one").
- **Error**: inline card "Couldn't load — Retry" with the reason in plain words.
- **Offline / syncing**: a small status pill under the header ("Offline — 3 changes will sync", "Syncing…", "Synced ✓") and the unsynced items marked with a small cloud-off icon.
- **Privacy mode**: every amount shown as ₹•••• (Home, lists, charts axis labels hidden), with a subtle eye-off indicator in the header.
- **Large text (1.3×)** variant of Home and a transaction row — nothing clips.

## 2. Feedback components in context
Toasts (floating above the bottom nav: "Saved", "Deleted — Undo", "Split saved — your share is ₹4,000"), confirm dialogs, destructive dialog, inline success banner, pull-to-refresh, the radial menu open state, keyboard-open layouts for Add transaction and Split sheet.

## 3. System UI
- **Android notifications** (shade cards with the "A" small icon): "Rent due tomorrow — ₹12,000 · your share ₹4,000", "Low balance on SBI ••8208 — ₹850 left", "Amit owes you ₹4,000 — Remind", "New: Swiggy −₹486 · tap to review", weekly recap with a mini summary.
- **Android 12+ splash**: the "A" icon on graphite.
- **Themed icon** (Android 13 monochrome) and the launcher icon on a home screen next to the widgets.
- **Permission dialogs** preceded by AERIS explainer sheets.

## 4. Tablet & foldable (1280 × 800 dp landscape, and an unfolded 2208 × 1840 px foldable)
- Navigation becomes a left **navigation rail** (Home, Activity, Insights, Me, + Add).
- Home: two columns — hero + balances + setup on the left; where-it-went, momentum, recent on the right.
- Activity: **list–detail** two-pane (list left, transaction detail right).
- Insights: charts in a 2-column grid.
- Settings: categories list left, detail page right.
- Sheets become centred dialogs (max 560 dp wide).

## 5. Screen map
A final overview board: every screen as a thumbnail grouped by flow (Launch & sign-in · Home & capture · Activity · Insights · Money & people · Me & settings · World & town · System), with arrows for the main journeys: first launch → onboarding → Home; SMS arrives → notification → review → detail; pay rent → auto-split → payback matched → settled.
