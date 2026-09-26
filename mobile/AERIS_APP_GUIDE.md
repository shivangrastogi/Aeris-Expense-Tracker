# AERIS Expense — Complete App Guide & GUI Design Brief

> **Purpose of this document:** a complete, screen-by-screen, option-by-option description of the AERIS Expense mobile app — everything that exists today, how each piece works, plus recommended additions and a reorganised structure. Hand this to a design tool/designer to produce a brand-new GUI. **Hard requirement: every screen must ship in both Light and Dark mode** (plus follow-system), with all components themed from tokens — no hardcoded colors in final designs.

---

## 1. What AERIS is

AERIS is a **privacy-first, India-focused personal expense tracker** for Android (Flutter). Its three pillars:

1. **Zero-effort capture** — bank/UPI SMS are parsed on-device into transactions automatically; voice and one-line natural-language entry cover cash.
2. **End-to-end encryption** — transaction data, budgets, goals, loans, and the profile photo are AES-GCM encrypted on the phone before they touch Firestore. The server can never read amounts or merchants.
3. **Gamified discipline** — a tamagotchi-like mascot (Aeris), Aura points, streaks, challenges, budget "bosses", and a growing garden make daily money hygiene feel like a game, not a chore.

**Brand mood:** calm, trustworthy fintech with playful gamified accents. Teal is the identity color; green/red are reserved strictly for money-in/money-out so they always read as financial signal, never decoration.

---

## 2. Design System & Theming (requirements for the new GUI)

### 2.1 Color tokens (current)

| Token | Value | Use |
|---|---|---|
| `seed` | `#0EA5A4` (teal) | Brand, primary actions, selected states |
| `credit` | `#22C55E` (green) | Money in ONLY |
| `debit` | `#EF4444` (red) | Money out ONLY |
| `warning` | `#F59E0B` (amber) | Budget risk, pending states |
| `info` | `#3B82F6` (blue) | Informational chips |
| `surfaceTintLight` | `#F7FAFA` | Light background tint |
| `surfaceTintDark` | `#0B1416` | Dark background tint |
| Hero gradient | `#0EA5A4 → #0F766E` | Hero spend card, celebrations |
| Violet gradient | `#8B5CF6 → #6366F1` | Secondary accent cards (voice FAB, no-streak banner) |
| Streak gradient | `#EA580C → #F97316` (orange) | Active streak banner |
| Category palette | 12 colors (teal, amber, violet, pink, green, red, blue, mint, purple, orange, cyan, lime) | Donut/radar/bars — must survive both modes |

### 2.2 Dark + Light mode (mandatory)

- Both themes are generated from the same seed via Material 3 `ColorScheme.fromSeed`. The new GUI must define **every** surface, text, divider, chip, and chart color as a token with light/dark values.
- Gradient cards (hero, streak, violet) keep their gradients in both modes — text on them is always white/white70.
- Charts need per-mode grid/label colors (currently grey at 12% alpha for gridlines).
- The user can pick a custom **accent color** in "Customize dashboard" — the whole theme re-seeds from it. The design must tolerate any accent hue.
- Status/dynamic colors (credit green, debit red, warning amber) stay identical across modes for recognisability — only adjust luminance if contrast fails.

### 2.3 Typography & shape

- Google Fonts based text theme (current); large money figures use heavy weights (w800–w900) with tight letter-spacing (−0.5) at 30–38 px.
- Cards: rounded ~20 px radius, soft elevation. Bottom sheets: drag handle + 18–24 px padding.
- Numbers everywhere format as Indian rupees: `₹1,23,456` with compact forms (`₹1.2L`, `₹45K`) in tight spaces.

### 2.4 Motion language

- **Entrance:** sections fade-in + slide-up 8%, 350 ms, easeOutCubic — but **only once per session per section** (a `PlayOnce` mechanism prevents replays on scroll/rebuild).
- **Counts:** money figures tween from previous value to the new value (never from zero) over 650 ms.
- **Charts:** donut slice "pops out" 12 px when tapped; budget ring sweeps in over 900 ms.
- **Skeletons:** every async surface has a shimmer skeleton, never a bare spinner (Home, Analytics, Insights).
- Avoid heavy continuous/looping animations — performance on mid-range Androids is a core constraint.

---

## 3. Entry Flow

### 3.1 Splash screen
- Glowing wallet mark, then the wordmark **"A.E.R.I.S"** types out glyph-by-glyph, a tagline, and a slim indeterminate progress bar with a "please wait" line — the cold start reads as a deliberate loader, not a frozen spinner.

### 3.2 Onboarding (first launch only)
- A swipeable welcome tour (gated by a stored `onboarded` flag): introduces AERIS, the Aeris mascot, **SMS auto-import** (with the privacy explanation Play Store requires before requesting SMS permission), and budgets. Skippable; finishes into the app.

### 3.3 Authentication
- **Login** — email + password. On success the same password unlocks the encryption vault in the background, so the user lands directly on Home (no second password prompt).
- **Sign up** — name, email, password. Generates the encryption keys and shows a **Recovery Key** the user must confirm they saved (it's the only way back in if they forget the password — copy-to-clipboard + "I've saved it" checkbox).
- **OTP screen** — phone-verification flow (verification id driven).
- **Key Gate** — an invisible layer between auth and the app: verifies the encryption vault is unlocked (memory → secure-storage cache → Firestore key check). Only if all fail does it show a manual "Unlock your data" password screen.
- **App Lock Gate** — optional biometric / device-PIN lock over the whole app (enabled in Settings).

---

## 4. Navigation Shell

A Material 3 `NavigationBar` with **7 tabs** (labels show on the selected tab only):

| # | Tab | Icon | Screen |
|---|---|---|---|
| 1 | Home | home | Dashboard |
| 2 | Txns | list_alt | Transactions |
| 3 | Charts | analytics | Analytics |
| 4 | Budgets | savings | Budgets |
| 5 | Lent | handshake | Money lent/borrowed |
| 6 | AI | tips_and_updates | AI Insights |
| 7 | Me | person | Profile |

**Context FABs:** Home shows a violet **microphone FAB** (voice capture). Transactions shows an extended **"Add"** FAB opening a sheet: *Quick add* (type one sentence) / *Add expense* / *Add income*.

> **Design suggestion (see §16):** consider 5 primary tabs + a "More" hub, or a center docked FAB, if 7 feels crowded in the new GUI.

---

## 5. Tab 1 — HOME (the dashboard)

Top to bottom, every element:

### 5.1 Greeting header (top row)
- **"Hi, {Name}"** — first name, first letter auto-capitalised, with a time-aware greeting.
- **Inbox icon** → Review SMS imports screen.
- **Bell icon** → one-tap SMS auto-import permission request.
- **Aeris mascot button** (animated face, 40 px) → opens the **AI Assistant** chat. A one-time coach tooltip points at it on first run ("Tap Aeris to ask about your money").

### 5.2 Range selector
- A chip that switches every money figure app-wide between **This month / Last month / Last 3 months / This year** (a single global provider all screens watch).

### 5.3 Daily check-in card
- One tap per day claims **+15 Aura** plus a growing streak bonus (+5/day, capped +60). Builds the `checkinStreak`. Already-claimed state shows as done for the day. Streak is **cloud-synced** (survives reinstall, restores on login).

### 5.4 Import progress banner (conditional)
- While an SMS backfill batch is being scanned/encrypted, a slim progress chip shows "Importing… n/of". Disappears when done.

### 5.5 Hero spend card (teal gradient)
- Label "Spent · {range}".
- The **amount** (₹, 38 px, animated count-up) with the **privacy eye** button *inline right of the amount* — toggles masking of every amount in the app (`₹•••••`).
- **Month-over-month badge** — "↓ 12%" green when spending less than last month, red when more.
- **🔥 Streak chip** — current check-in streak.
- Tapping the card opens Transactions filtered to expenses.

### 5.6 Streak banner card (always visible)
- Orange gradient when a streak is active; indigo-violet when no streak yet.
- Fire icon + "{n} days" headline + motivational line.
- **Weekly dots** — 7 circles labelled S M T W T F S, **week starts Saturday**; filled with a check for each checked-in day, ring outline for today, dimmed for future days.
- When **no monthly budget exists**: a "Set budget" button (with piggy icon) sits on the right — opens the total-budget bottom sheet (amount field → saves a single overall monthly cap). The button disappears once a budget exists.

### 5.7 Monthly budget ring card (only when a budget exists)
- **Animated ring** (116 px) showing % of budget used; ring color blends toward red past 80%.
- Rows: **Spent / Budget / Left (or Over)** with color-coded values.
- The cap is the explicit **total monthly budget** if set, otherwise the sum of per-category caps.

### 5.8 Aeris level card
- The avatar/mascot with **level** (derived from lifetime Aura), evolution stage, and a mood reflecting real finances (over budget → sad; saving → excited). Tapping opens **Aeris World**.

### 5.9 Forecast card
- From the AI prediction engine: projected month-end spend, plus a count of budgets at risk ("2 budgets likely to exceed within 7 days") — amber tinted when risky.

### 5.10 Quote carousel
- Rotating money-wisdom quotes (light delight element).

### 5.11 Goals card
- Snapshot of savings goals (emoji, progress bar, saved/target). Tap → Goals screen.

### 5.12 Subscriptions card
- Auto-detected recurring payments (Netflix, rent, EMIs…) with next-due hints. Tap → Subscriptions & bills screen.

### 5.13 Recent activity
- Last few transactions as compact tiles (category icon, merchant, time, ± amount). Tap a tile → Transaction detail.

### 5.14 Customization
- Every optional card (Aeris, forecast, quote, goals, subs) can be hidden from **Customize dashboard** (in Aeris World); Home honours the hidden set.
- Pull-to-refresh re-syncs the transaction stream.

---

## 6. Tab 2 — TRANSACTIONS

- **Full transaction list**, newest first, grouped with date headers. Each tile: category icon + color, merchant/note, source chip (SMS/manual/voice), time, signed colored amount.
- **Filters:** direction (income/expense) and category — the screen can be opened pre-filtered (e.g. tapping the hero card opens expenses; tapping a donut slice opens that category).
- **Privacy eye** respected — amounts mask app-wide.
- **Add flows (FAB sheet):**
  - **Quick add** — type/dictate one sentence: *"spent 200 on chai yesterday"*, *"got 5000 salary"*. On-device NLP extracts amount, direction, merchant, category, date; user confirms a parsed preview card before saving.
  - **Add expense / Add income** — classic form: amount, merchant, category picker, date, note, account.
- **Voice capture (Home FAB)** — full-screen, ChatGPT-voice-mode style: an animated orb reacts to speech; speak one or **many** transactions naturally; on-device parsing produces editable entry cards; save all in one tap.
- **Transaction detail screen** — full info (amount, merchant, category, date, account, SMS body if imported), edit category (teaches a merchant→category rule for future auto-categorisation), edit fields, delete.
- **Statement import** — upload a bank statement file and bulk-import parsed rows (deduped like SMS).

---

## 7. Tab 3 — CHARTS (Analytics)

All charts respect the global range selector; heavy charts are pre-built one screen ahead so scrolling never shows blanks.

1. **Spending by category — interactive donut.** Slices labelled *outside* with angled leader lines that follow each slice's direction (clock-face style) + percentages; collision-avoidance keeps labels readable. Tap a slice → it pops out, the center shows that category's amount/share, and an animated **detail card** flips into view below (amount, % of spend, txn count, avg/txn, "View transactions" drill-in).
2. **Daily spend** — bar chart of debits per day, tooltips in ₹.
3. **Spending heatmap** — calendar-style intensity grid of daily spending.
4. **Trend chart** — interactive line with zoom/pan/crosshair across months.
5. **Income vs expense** — two horizontal bars + Net figure (green/red).
6. **Top merchants** — ranked horizontal bars of where money actually went.
7. **Cumulative spend** — area line accumulating over the range with tidy ₹ axis steps.
8. **Category mix radar** — top-6 categories on a polygon radar (needs ≥3 categories).

---

## 8. Tab 4 — BUDGETS

- **Total monthly budget** — one overall cap (editable/deletable via dialog). Takes precedence over category sums everywhere (home ring, widget, projections).
- **Per-category budgets** — list with progress bars vs current spend; add/edit via Budget Edit screen (category + monthly cap).
- **Auto-suggest** — proposes caps from spending history (per-category EMA), rounded to tidy ₹100/500/1000 steps; user picks which to apply.
- **Budget alerts** — when reminders are on, a daily-rate-limited notification fires if any budget is over or projected to exceed within ~5 days.

---

## 9. Tab 5 — LENT (money with friends)

- **Summary card:** "Owed to you" (green) | "You owe" (red) — pending entries only.
- **Pending section** — each entry: friend-initial avatar, name, *You lent / You borrowed*, date, note, amount, amber **Pending** chip.
- **Settled section** — struck-through name, green **Received** chip.
- **Add (FAB):** segmented *I gave money / I borrowed*, friend's name, amount, optional note.
- **Tap an entry:** *Mark as received* (or *paid back*) → moves to Settled · *Mark as pending again* (undo) · *Delete*.
- Stored **encrypted** (friend names are personal data); separate from transactions to avoid double-counting the original UPI debit.

---

## 10. Tab 6 — AI (Insights)

All computed **on-device** — no data leaves the phone for these:

- **Month estimate** — hero prediction card: expected total spend this month.
- **Budget projections** — per budget: on-track / will exceed in N days / already over.
- **Anomalies** — unusual transactions (amount spikes vs history).
- **Recurring payments** — auto-detected subscriptions/EMIs with cadence.
- **Recommendations** — actionable nudges (severity-tinted), e.g. "Food is 2× last month".
- **Cashflow** — income vs spend pacing for the month against stated monthly income.
- **Mascot card** — Aeris speaks the top insight; tapping cycles through more lines.
- **"Ask Aeris" → AI Assistant** — chat screen that answers questions about your own data ("how much on food last week?", "biggest expense this month?").

---

## 11. Tab 7 — ME (Profile)

- **Profile card** — avatar, name, email, monthly income.
  - **Tap avatar** → sheet: **View profile picture** (full-screen, pinch-zoom, tap to close) / **Change profile picture** (gallery or camera → saved immediately, end-to-end encrypted).
  - **Edit (pencil)** → Edit Profile: name, phone, monthly income, photo (with remove option).
- **Your month in money · Wrapped** — Spotify-Wrapped-style swipeable monthly recap (top category, biggest splurge, best no-spend run…), computed on-device, share-able.
- **Aeris World** — gamification hub (see §12).
- **Accounts** — bank accounts auto-detected from SMS (bank + masked number) with per-account balances/usage.
- **Import bank statement** — file-based bulk import.
- **Review SMS imports** — every parsed SMS with its resulting transaction; **block senders** (promos/spam) so they never import again; blocked list syncs to the background isolate.
- **Settings** (see §13).
- **Sign out** (destructive-styled).

---

## 12. AERIS WORLD (gamification hub)

The play layer. Currency: **Aura** — earned deterministically (each rewardable event pays exactly once, so balances can never drift), **cloud-synced** so it survives reinstalls.

**Earning Aura:** welcome bonus (+50) · daily check-in (+15 + streak bonus) · completing a goal (+200) · finishing a month within total budget (+100) · every no-spend day (+10) · winning challenges (custom reward) · categorising transactions.

**Sections:**
- **Avatar store** — spend Aura to unlock avatar skins; equip one; avatars **evolve** in stages with level (level = f(lifetime Aura)); mood reflects real finances.
- **Challenges** — create personal challenges ("No food delivery for 7 days", "Keep shopping under ₹2,000 this week"); evaluated automatically against live transactions; win → Aura.
- **Bosses** — every budgeted category is a "boss"; the cap is its shield, spending chips it away; end the month within cap → boss defeated.
- **Garden** — a calm custom-painted world that grows with Aura (~every 120 Aura plants/upgrades something), gentle breeze sway, fully offline. The "zen mode" of the app.
- **Future Self** — projection of where current saving habits lead (motivational visualisation).
- **Customize dashboard** — show/hide Home cards; pick the app **accent color** (re-seeds the entire theme).

---

## 13. SETTINGS (every option)

| Option | What it does |
|---|---|
| **Read bank SMS automatically** (switch) | Requests SMS permission. If Android has permanently blocked the prompt (common after a prior deny on Realme/Xiaomi), it explains why and opens the app's system settings page instead. On grant, live SMS listening starts **immediately**. Turning off routes to system settings (apps can't self-revoke). |
| **Backfill last 90 days** | Full inbox re-scan → parse → dedupe → encrypt → import, with progress. Pre-checks SMS permission and says so if missing; reports "imported N" vs "nothing new" distinctly. |
| **Allow background activity** (shown once SMS is on) | One-tap battery-optimisation exemption so the SMS receiver keeps firing when the app is closed; plus an OEM hint row (Realme/Xiaomi: Auto-launch + battery Unrestricted) linking to app settings. |
| **Smart reminders** (switch) | Weekly summary + bill-due nudges from detected recurring payments + daily check-in reminder + budget-risk alerts. |
| **Export to Excel** | Generates a styled .xlsx (summary, categories, monthly trend, merchants, full ledger) and opens the share sheet. |
| **App lock** (switch) | Biometric/PIN gate over the app; verifies a successful auth before enabling. |
| **Encrypt existing data** (legacy accounts) | One-time upgrade to E2E encryption; shows the Recovery Key flow. |
| **Encrypted backup / Restore** | Passphrase-encrypted export of all data; restore requires the exact passphrase. |
| **Blocked senders** | Managed via Review SMS imports; honoured by both foreground and background import paths. |

---

## 14. System Integrations

### 14.1 SMS auto-import pipeline
1. **Live:** incoming SMS → broadcast receiver (works app-closed via background isolate) → on-device parser (banks, UPI, cards, wallets; amount/merchant/direction/reference) → encrypt → Firestore.
2. **Startup incremental sync:** scans only since the last high-water mark (with a 2 h overlap), deferred 4 s after launch so the dashboard paints first.
3. **Manual backfill:** full 90-day rescan from Settings.
4. **Dedupe:** HMAC dedupe tags (reference/UTR-based when present), a 1000-entry local cache to avoid network checks, plus a Firestore ledger as cross-device truth.
5. **Blocked senders** are skipped everywhere.

### 14.2 Android home-screen widget
- Shows **🔥 streak** (count + nudge line), a divider, then **Budget left** (₹ amount, progress bar, "Spent X of Y"). Resizable, updates whenever data changes (debounced), taps open the app.

### 14.3 Notifications
- Budget risk alert (max 1/day) · daily check-in reminder · weekly summary · bill-due nudges.

---

## 15. Security & Privacy model

- **E2E encryption:** a Data Encryption Key encrypts every payload (AES-GCM) on-device; the DEK is wrapped by a Key-Encryption-Key derived from the login password; a **Recovery Key** is the fallback unwrap. Firestore stores only ciphertext blobs + minimal plaintext metadata (timestamps for ordering).
- Decryption is cached per-doc and heavy batches run on a **background isolate** so the UI never blocks.
- **App lock** (biometric) and the **privacy eye** (mask all amounts) cover shoulder-surfing.
- Firestore rules: each user can read/write only their own `users/{uid}` tree.
- Gamification stats (streak/Aura) are deliberately plaintext so they restore before the vault unlocks.

---

## 16. RECOMMENDED ADDITIONS & REORGANISATION (for the new GUI)

Things that don't exist yet but should be designed in:

### 16.1 Navigation
- **Option A (recommended):** 5 tabs — Home · Txns · Charts · Lent · Me — with Budgets merged into Home/Charts as a destination and AI Insights surfaced as a Home card + assistant entry. A center-docked "+" FAB for add flows.
- **Option B:** keep 7 tabs with selected-label-only (current behaviour) but enlarge touch targets.

### 16.2 Missing features worth designing
1. **Theme toggle in Settings** — Light / Dark / System (currently follows system only). *Design both modes for every screen regardless.*
2. **Transaction search** — search bar over merchant/note/amount with recent-search chips.
3. **Split & remind in Lent** — split one amount across multiple friends; per-entry due date with an optional reminder notification; share a payment-request message (UPI deep link) via WhatsApp.
4. **Partial repayments in Lent** — "received ₹500 of ₹2,000" progress per entry.
5. **Category manager** — user-defined categories with icon + color picker.
6. **Monthly report** — auto-generated end-of-month summary notification + shareable report page (extends Wrapped).
7. **Tags** — freeform tags on transactions (e.g. #trip-goa) with tag-filtered analytics.
8. **Calculator-style amount pad** — in add flows, inline `250+120` arithmetic.
9. **Onboarding personalisation step** — ask monthly income + a starter budget during the tour.
10. **Accessibility** — large-font audit, semantic labels on charts (spoken summaries), min 4.5:1 contrast in both modes.
11. **Empty/error/offline states** for every screen — design them explicitly (the app is offline-first; show a quiet "syncing…" pill, never a blocking error).
12. **iOS parity** — design assuming an eventual iOS build (no Android-only idioms in core flows).

### 16.3 Visual upgrade directions
- Bigger, bolder hero numbers; soft glassmorphism on gradient cards; consistent 8-pt spacing grid.
- A unified **"money chip"** component (signed, colored, compact) reused everywhere amounts appear.
- Chart palette tuned per mode (slightly desaturated in dark).
- Celebrate moments: confetti on boss defeat / goal completion / streak milestones (7, 30, 100 days).

---

## 17. Component inventory (for the design system)

Cards: gradient hero · streak banner · budget ring · stat card · chart card · insight card · goal card · loan tile · transaction tile · mascot card.
Controls: range selector chip · segmented buttons · privacy eye · FABs (mic, add) · bottom sheets (add txn, add loan, set budget, avatar options, photo source) · snackbars · progress chips.
Specials: animated count · skeleton shimmer · weekly streak dots · interactive donut with leader-line labels · heatmap grid · radar · animated voice orb · typing splash wordmark · Aeris mascot (5 moods: happy, neutral, worried, alert, excited) · garden canvas.

Every component above needs a **light and a dark** specification.
