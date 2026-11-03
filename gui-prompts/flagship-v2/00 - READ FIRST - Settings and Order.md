# AERIS Flagship Redesign — Claude Design prompt pack

A complete, production-grade redesign of every screen in the AERIS Expense
mobile app. Run the prompts **in order, in the same Claude Design project**, so
every screen shares one design system.

---

## 1. Settings when you create the project

Claude Design's labels may differ slightly. Pick the closest option:

| Setting | Choose | Why |
|---|---|---|
| Project / file type | **Mobile app** (prototype / multi-screen) | Lets you build many linked screens, not one image |
| Platform | **Android** | The app ships on Android; Material conventions (back gesture, system bars) |
| Device / frame | **Pixel 8 — 412 × 915 dp** (20:9) | Matches modern Android phones (your Realme is 20:9) |
| Second frame (later) | **Tablet 1280 × 800 dp** (landscape) | Prompt 09 adds tablet layouts |
| Theme | **Light + Dark** (both) — **Dark first** | The app supports both; dark is the hero look |
| Fidelity | **High / production** (not wireframe) | You want final, buildable UI |
| Design system | **Create new** with Prompt 01, then **reuse it** for 02–09 | Keeps every screen consistent |
| Font | **Plus Jakarta Sans** (Google Font) | Already bundled in the app, so the design is 1:1 buildable |
| Icon set | **Material Symbols Rounded**, 1.5–2 px weight | Matches the Flutter app's icon set |
| Units / grid | **dp, 8-point grid**, 4 dp sub-grid | Android standard; easy to hand off |
| Interactivity | **Clickable prototype** — link tabs, buttons and sheets | You can tap through the whole journey |
| Images / AI imagery | **Off** for photos; illustrations only where a prompt asks | Fintech should look clean, not stocky |
| Export / hand-off (at the end) | **Design tokens (JSON)** + **specs / redlines** (+ Flutter code if offered) | So the redesign can be implemented in the Flutter app |
| Brand assets | Upload `mobile/assets/icons/app_icon.png` (the "A" logo) | The new icon is the brand anchor |

## 2. Order to run

1. `01 - Design System.md` — tokens, components, motion. **Review it and approve it before going on.**
2. `02 - Launch, Onboarding and Sign-in.md`
3. `03 - Home and Capture.md`
4. `04 - Activity and Transaction Detail.md`
5. `05 - Insights, Budgets, Goals and Assistant.md`
6. `06 - Money, Bills and People.md`
7. `07 - Me and Settings.md`
8. `08 - Aeris World and Town.md`
9. `09 - States, System UI and Tablet.md`

After each prompt: check light **and** dark, then say "keep" or ask for changes
before moving on. If a batch comes out shallow, ask it to "do the remaining
screens in this batch at the same depth".

## 3. Final hand-off prompt (after 09)

> Create a hand-off page for developers: export all design tokens (colour,
> type, spacing, radius, elevation, motion) as JSON with light and dark
> values; a component inventory with every variant and state; redlines for
> Home, Transaction detail, Add transaction and Settings; and a screen map
> showing how every screen links. Name tokens so they map to a Flutter
> ThemeData / ColorScheme.

## 4. Product facts the design must respect

- **AERIS** — a private, end-to-end-encrypted personal finance app for India
  (₹, Indian digit grouping: ₹1,20,000; lakh/crore in compact numbers).
- It **reads bank SMS and UPI-app notifications on the phone** to log
  transactions automatically, with a review queue for doubtful ones.
- Key features: budgets, goals, bills and card dues, shared bills with
  roommates (split rent ÷3, paybacks matched), lent & borrowed, accounts with
  live bank balances, net worth, monthly report card and Wrapped story, an
  on-device assistant "Ask Aeris", a light game layer (Aeris World / Town).
- Owner taste (important): **professional, calm, premium — never neon,
  never cartoonish, no harsh saturated colours, no glows.** Colour must carry
  meaning (green = money in / good, amber = needs attention, red = warning).
