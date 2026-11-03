Using the **AERIS design system already created in this project** (Graphite dark + Porcelain light, steel-blue accent, Plus Jakarta Sans, rising-line-and-dot motif, no neon, no emoji), design these screens on a Pixel 8 frame (412 × 915 dp), in **both Dark and Light**, as a clickable prototype with the floating bottom navigation (Activity tab active where relevant).

Sample data (₹): Swiggy −₹486 (Food, PhonePe, needs review), Uber −₹1,200 (Travel, Google Pay), Zomato −₹544, Ola −₹203, Myntra −₹2,199 (Shopping), Starbucks −₹336 (card ••4521), Salary +₹85,000 (Acme Tech, NEFT), Rent −₹12,000 to Mr Sharma (split 3 ways), "Rahul paid back" +₹4,000, Flipkart refund +₹450.

## 1. Activity tab
- Large title "Activity" with an export icon button (labelled).
- Segmented tabs: Transactions · Lent · Subscriptions.
- Smart search field: placeholder "Try 'swiggy september' or 'above 1000'".
- Filter chips: Filter (opens sheet), All, Spent, Received, plus account and category chips; active filters show as removable chips with a "Clear" link.
- List grouped by day with sticky day headers and day totals ("Today −₹1,686"). Rows: category tile, merchant, sub-line "Food · 2:07 PM · PhonePe", amount right (−₹486), small "Review" pill when unconfirmed, small split icon on shared bills ("your share ₹4,000"), small "own transfer" icon on transfers.
- Swipe actions on a row: left = delete (with undo toast), right = mark reviewed / change category.
- Multi-select mode (long-press): count in header, bulk actions Categorise · Mark reviewed · Delete.
- Filter sheet: date range presets + custom, amount range slider, categories grid, accounts, source (SMS / UPI app / manual / import), type.
- Empty states: no results for a search ("No matches for 'netflix october'" + clear button); first-time empty.

## 2. Transaction detail — design ALL these variants
Header: back, "Edit all details" and delete actions. Top: large category tile, merchant name, amount (tappable to edit), type pill (Expense / Income).
Field rows (tap to edit in a small sheet): Category, Type, Merchant/Payer, When, Account "HDFC salary · ••4521", Paid via "Google Pay", UPI ID, Reference, Balance after "₹85,610.82", Source "Bank SMS", Note.

Variants:
- **a. Plain SMS expense** with the **Original SMS** card at the bottom: the message text with every money figure shown as a tappable chip (the chosen amount highlighted in accent, others outlined); hint "Wrong amount? Tap the right number — AERIS remembers it for this bank."; "From: JX-BOBSMS-T".
- **b. Split bill (rent)**: card "Shared bill · your share ₹4,000" with edit; rows Rahul ₹4,000 "Paid back" (green tick), Amit ₹4,000 "Pending" (amber) with a ⋮ menu (Mark received (cash), Remind); "Remove split" text button. Before splitting, the variant shows an outline button "Split this bill" + helper line.
- **c. Payback (credit)**: card "Rahul paid back — his share of Rent (₹12,000 · 1 Oct), not counted as income" with "Not a payback".
- **d. Own-account transfer**: card "Transfer between your accounts — not counted as spending or income · Arrived in SBI ••5174" with "Not a transfer".
- **e. Refund**: "Refund for: Flipkart ₹1,450 · 1 Oct" linked card; and on the purchase: "Refunded ₹450".
- **f. Received from UPI app notification**: "Original notification · From: Google Pay app".

## 3. Split bill sheet
Title "Split ₹12,000 · Rent", helper "Only your share counts as your spending". Group chips (Flat ✓, Goa trip, + New people). People rows: avatar initial, name, editable amount field, remove ×. "Add a person" field. "Split equally" button and live "Your share ₹4,000" (red "More than the bill" error state). Switches: "Save these people as a group" + group name; "Always split payments to Mr Sharma". Primary "Save split".

## 4. Edit sheets
- Category picker sheet: search, recent categories, grid of all categories (built-in + user's custom, e.g. "Pets"), "+ New category".
- Amount editor sheet with keypad. Date-time editor sheet. Text editor sheet (merchant / note) with Save enabled only when changed.

## 5. Lent and Subscriptions tabs
- Lent: summary "Owed to you ₹1,500 · You owe ₹0", pending and settled lists (person, note, amount, "Mark settled"), FAB "Add".
- Subscriptions: monthly total ₹19,167 / yearly; list (Netflix ₹649 on the 5th, Rent ₹12,000 on the 3rd, Airtel ₹399, Spotify ₹119) with next-due dates; "Detected from your payments" suggestions with "Add".
