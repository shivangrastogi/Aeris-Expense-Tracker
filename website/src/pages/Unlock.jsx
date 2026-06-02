import { useState } from 'react';
import { motion } from 'framer-motion';
import { Lock, KeyRound, Loader2, LogOut, LifeBuoy } from 'lucide-react';
import { useVault } from '../state/Vault.jsx';

export default function Unlock() {
  const { user, unlock, restore, logout } = useVault();
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [recoverMode, setRecoverMode] = useState(false);
  const [recoveryKey, setRecoveryKey] = useState('');
  const [newPw, setNewPw] = useState('');

  async function doUnlock(e) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await unlock(password);
    } catch (err) {
      setError(err?.message || 'Could not unlock.');
      setBusy(false);
    }
  }

  async function doRestore(e) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await restore(recoveryKey, newPw);
    } catch (err) {
      setError(err?.message || 'Recovery failed.');
      setBusy(false);
    }
  }

  return (
    <div className="min-h-screen grid place-items-center p-6">
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.45, ease: [0.16, 1, 0.3, 1] }}
        className="w-full max-w-sm card"
      >
        <div className="h-12 w-12 rounded-2xl bg-mint/15 border border-mint/20 grid place-items-center mb-4">
          <Lock className="text-mint" size={22} />
        </div>
        <h2 className="font-display text-2xl font-semibold">Vault locked</h2>
        <p className="text-muted text-sm mt-1 mb-6">
          {user?.email} · re-enter your password to decrypt your data.
        </p>

        {!recoverMode ? (
          <form onSubmit={doUnlock} className="space-y-3">
            <div className="relative">
              <KeyRound size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted" />
              <input
                type="password"
                required
                autoFocus
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="field pl-10"
                placeholder="Password"
              />
            </div>
            {error && (
              <div className="text-debit text-sm rounded-xl bg-debit/10 border border-debit/20 px-3 py-2">{error}</div>
            )}
            <button type="submit" disabled={busy} className="btn-primary w-full">
              {busy ? <Loader2 className="animate-spin" size={18} /> : <><Lock size={16} /> Unlock</>}
            </button>
          </form>
        ) : (
          <form onSubmit={doRestore} className="space-y-3">
            <input
              type="text"
              required
              value={recoveryKey}
              onChange={(e) => setRecoveryKey(e.target.value)}
              className="field font-mono tracking-wider"
              placeholder="XXXX-XXXX-XXXX-…"
            />
            <input
              type="password"
              required
              value={newPw}
              onChange={(e) => setNewPw(e.target.value)}
              className="field"
              placeholder="New password"
            />
            {error && (
              <div className="text-debit text-sm rounded-xl bg-debit/10 border border-debit/20 px-3 py-2">{error}</div>
            )}
            <button type="submit" disabled={busy} className="btn-primary w-full">
              {busy ? <Loader2 className="animate-spin" size={18} /> : 'Recover & set new password'}
            </button>
          </form>
        )}

        <div className="flex items-center justify-between mt-5 text-xs">
          <button
            onClick={() => { setRecoverMode((v) => !v); setError(null); }}
            className="inline-flex items-center gap-1.5 text-muted hover:text-ink"
          >
            <LifeBuoy size={13} /> {recoverMode ? 'Use password' : 'Use recovery key'}
          </button>
          <button onClick={logout} className="inline-flex items-center gap-1.5 text-muted hover:text-ink">
            <LogOut size={13} /> Sign out
          </button>
        </div>
      </motion.div>
    </div>
  );
}
