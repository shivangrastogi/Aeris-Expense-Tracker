Using the **AERIS design system already created in this project** (Graphite dark + Porcelain light, steel-blue accent, Plus Jakarta Sans, grouped-list settings style, no neon, no emoji), design these screens on a Pixel 8 frame (412 × 915 dp), in **both Dark and Light**, as a clickable prototype (Me tab active in the floating bottom navigation).

Settings behaviour to show: switches and choices apply instantly and confirm with a small "Saved" toast; text forms have an explicit Save button enabled only when something changed, plus a "Discard changes?" guard; destructive actions need a confirm; deletes offer Undo.

## 1. Me tab
Large title "Me" with a settings icon button. Profile card: avatar "SR" (or photo), Shivang Rastogi, email, chips "Level 3 · 420 Aura" and "₹85K/mo". Attention card "2 imports to review — Review". Grouped sections:
- **Money**: Net worth · Accounts · Budgets · Goals · Bills & subscriptions · People.
- **Tools**: Import bank statement · Review imports (badge 2) · Home-screen widgets.
- **You**: Report card · Monthly Wrapped · Aeris World.
- **Settings** row. Footer: "Sign out" (outline, red text) and "🔒 Your data is end-to-end encrypted" (use a lock icon, not an emoji).

## 2. Edit profile
Photo picker (camera / gallery / remove), name, email (read-only with "Change in Account & security"), monthly income, payday (day of month), Save with discard guard.

## 3. Settings (one scrollable grouped list)
- **Account**: Account & security →.
- **Appearance**: Theme segmented (Light · Dark · System); Currency (₹ Indian Rupee) →; Customize Home →; Categories & learning →.
- **SMS auto-import**: Read bank SMS automatically (switch); Auto-confirm confident imports (switch, "Only doubtful ones wait in Review"); Backfill range (value "90 days" with dropdown: 7 days, 30 days, 90 days, 6 months, 1 year, Custom…); Backfill last 90 days ("Re-scan inbox → import", progress state); Read UPI app notifications (status "On — catches Google Pay / PhonePe / Paytm"); Low-balance alert (dropdown Off / ₹500 / ₹1,000 / ₹2,000 / ₹5,000 / ₹10,000); Allow background activity.
- **Notifications**: Smart reminders (master switch) → when on, sub-switches: Daily spend alert (9 PM), Weekly recap (Sunday), Bills & card dues (day before), Money owed to you, Monthly report card (1st).
- **Security & data**: App lock (switch), Hide in recent apps (switch), Encrypted backup →, Restore from backup →, Blocked senders (list with Unblock).
- **Export**: Export to Excel (share icon, progress state).
- **About**: About AERIS (version 1.0.0) →, Privacy policy →.

## 4. Custom range dialog
"Custom range" with a number field "Number of days, e.g. 45", helper "1–1825", Cancel / Save, error state.

## 5. Account & security
Profile card (name, email). **Security** group: Change password ("Also re-locks your encrypted data with it"), Make a new recovery key ("Lost the old one? Replace it"). Explainer "Two locks protect you…" (password vs app lock). **Session** group: Sign out; **Delete account** (red).
- Change password dialog: current, new (live rules), confirm; error states.
- New recovery key: password prompt → the recovery key screen (from the sign-up design) with "Your old key no longer works".
- Delete account dialog: warning icon, what is erased, "Export to Excel first" link, password field, checkbox "I understand this is permanent", buttons "Keep my account" / "Delete forever" (red, disabled until ready). Then a final "Account deleted" screen.

## 6. Categories & learning
**Your categories**: list (Pets, Gym — icon tile in its colour) + "Add a category". **Learned from you**: rules "Swiggy → Food", "sharma@okicici → Rent" with × to forget; "Reset learned SMS formats". **Built in**: read-only list.
- Category editor sheet: name (with duplicate error), icon grid (20 icons), colour row (12 muted swatches), Save.

## 7. Customize Home
"Show on Home" switches with a live mini preview of Home on the right/top: Balances & card bills, Momentum, Top categories, Forecast, Daily check-in. Drag handles to reorder. Accent colour swatches (Steel default, Teal, Indigo, Sage, Plum, Slate, Terracotta) applied live to the preview.

## 8. Home-screen widgets gallery
Previews of each Android widget in light and dark: 2×2 Month spend, 4×2 Overview (spent, left, streak), 4×1 Quick add (Add · Voice · Scan), 1×1 Today, 2×1 Streak, 2×2 Budget ring, Town. "How to add" steps.

## 9. About & Privacy policy
About: logo, "AERIS Expense", version, tagline "Private, automatic money tracking", rows Privacy policy, Send feedback, Licences. Privacy policy: readable long-form page with section headings (In short, What the app reads, What is stored, Your keys, Permissions, Your choices, Crash reports).
