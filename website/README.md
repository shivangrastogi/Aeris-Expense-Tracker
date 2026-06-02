# AERIS Web

The browser version of the AERIS expense app. Logs into the **same Firebase
account** as the phone app and reads/writes the **same end-to-end encrypted
data**. SMS auto-import is mobile-only; everything else (dashboard, charts,
transactions, budgets, goals, AI assistant, add/edit/delete) is here.

## Security model
- Your financial data is encrypted by the phone app and only ever stored as
  ciphertext in Firestore. The server (and we) can never read it.
- On login, the key is derived from your password with **Argon2id**
  (m=19456 KiB, t=2, p=1) and the data key is unwrapped + used with
  **AES-256-GCM** — all in your browser tab.
- The data key lives **in memory only**. Refresh or close the tab and you must
  re-enter your password (by design — nothing sensitive is persisted on disk).

## Setup
1. Register a **Web app** in the Firebase console for project `jarvisv1-c40ed`
   (Project settings → Your apps → Add app → Web).
2. Paste the config into `src/firebaseConfig.js` (`apiKey` + `appId`; the rest
   are pre-filled). The web config is public by design — the Firestore rules +
   E2E encryption are what protect the data.

## Run
```bash
npm install
npm run dev      # http://localhost:5173
npm run build    # production build into dist/
```

## How it mirrors the app (do not drift)
- Crypto: `src/crypto/aerisCrypto.js` ↔ `lib/services/crypto_service.dart`
- Doc shapes / CRUD: `src/data/repo.js` ↔ `lib/services/firestore_service.dart`
- Categories: `src/data/categories.js` ↔ `lib/models/category.dart`
- Assistant: `src/services/assistant.js` ↔ `lib/services/assistant_service.dart`

Blob format everywhere: `base64(nonce).base64(cipher).base64(mac)`.
