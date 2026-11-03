Using the **AERIS design system already created in this project** (Graphite dark + Porcelain light, steel-blue accent, Plus Jakarta Sans, rising-line-and-dot motif, muted category palette, no neon, no emoji), design these screens on a Pixel 8 frame (412 × 915 dp), in **both Dark and Light**, as a clickable prototype.

## 1. Accounts
Intro line "Balances come from your bank SMS". Account cards: bank tile, nickname "HDFC salary" with "A/C ••4521 · 22 txns · last Saturday" beneath, big balance ₹85,610.82 with "per bank SMS, today 11:59 AM", three metrics (Spent ₹6K · Received ₹2.5L · Net +₹2.5L), ⋮ menu (Name this account / Rename, Opening balance, Hide account). Credit card variant: "Available limit ₹45,000 · Outstanding ₹12,345 due 5 Nov". "Unassigned" bucket (manual entries) without balance. Low-balance variant (red balance + "Below your ₹1,000 alert").

## 2. Rename account sheet
Text field "e.g. HDFC salary", helper "Leave empty to remove the name", Save.

## 3. Bills & subscriptions
Title with a labelled action "Subscriptions". Month calendar (dots on due days, today ringed, tap a day → its bills). "Upcoming" list: "Due tomorrow · Rent ₹12,000 (split)", "HDFC card ••1234 — ₹12,345 · min ₹620 · due 5 Nov" (amber), "Netflix ₹649 on the 5th", "Airtel ₹399 (usual amount) · spotted from history". Paid state ("Paid ✓ 3 Nov"). Month total. Empty state.

## 4. People hub
Title "People", summary line "Owed to you ₹7,500 · You owe ₹0", tabs **Shared bills · Lent & borrowed**.
- **Shared bills tab**: "Owed to you" card with total and per-person rows (avatar, name, amount, "Remind" button); "Groups" cards ("Flat — You, Rahul, Amit · Auto-splits: payments to Mr Sharma"); "+ New group"; "Shared bills" list (Rent · Mr Sharma, 3 Oct, your share ₹4,000, "1 of 2 paid back", amber outstanding / green tick when settled).
- **Lent & borrowed tab**: summary card, pending/settled lists, "Add" FAB; Add sheet (person, amount, I gave / I took, note, date).

## 5. Group editor sheet
Group name with rename, intro "Shares for automatic splits", rows (You, Rahul, Amit) each with a share selector (Equal, 1.5x, 2x, 0.5x) and remove; "Add a person"; "Splits automatically when you pay" chips with × (Mr Sharma / sharma@okicici); "Delete group" (destructive, with confirm).

## 6. Remind flow
Bottom sheet preview of the friendly message ("Hi Amit, a quick reminder of your share: • Rent (3 Oct): ₹4,000. Thanks!") with share targets WhatsApp, Messages, Copy; option "Include my UPI ID".

## 7. Net-worth links
From People "Owed to you" and Accounts balances, show how a tap leads to the relevant detail (link arrows in the prototype).
