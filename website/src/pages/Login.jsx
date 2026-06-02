import { useState } from 'react';
import { motion } from 'framer-motion';
import { Lock, Mail, KeyRound, Loader2, ShieldCheck, ArrowRight } from 'lucide-react';
import { useVault } from '../state/Vault.jsx';

export default function Login() {
  const { login } = useVault();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  async function submit(e) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await login(email, password);
    } catch (err) {
      setError(humanize(err));
      setBusy(false);
    }
  }

  return (
    <div className="min-h-screen grid lg:grid-cols-2">
      {/* Brand panel */}
      <div className="hidden lg:flex flex-col justify-between p-12 relative overflow-hidden">
        <div className="flex items-center gap-2">
          <div className="h-10 w-10 rounded-2xl bg-gradient-to-br from-mint to-teal grid place-items-center text-[#042521] font-display font-bold text-lg">
            A
          </div>
          <span className="font-display text-xl font-semibold">AERIS</span>
        </div>
        <div>
          <h1 className="font-display text-5xl font-semibold leading-[1.05]">
            Your money,<br />
            <span className="text-gradient">end-to-end private.</span>
          </h1>
          <p className="mt-5 max-w-md text-muted leading-relaxed">
            The same encrypted vault as the app — now in your browser. Your
            transactions are decrypted locally with a key derived from your
            password. We can never read them.
          </p>
          <div className="mt-8 flex items-center gap-3 text-sm text-muted">
            <ShieldCheck className="text-mint" size={18} />
            Argon2id + AES-256-GCM · key never leaves this tab
          </div>
        </div>
        <div className="text-xs text-muted">Same account as the AERIS phone app.</div>
      </div>

      {/* Form */}
      <div className="flex items-center justify-center p-6">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
          className="w-full max-w-sm card"
        >
          <div className="flex items-center gap-2 mb-1 lg:hidden">
            <div className="h-9 w-9 rounded-2xl bg-gradient-to-br from-mint to-teal grid place-items-center text-[#042521] font-display font-bold">A</div>
            <span className="font-display text-lg font-semibold">AERIS</span>
          </div>
          <h2 className="font-display text-2xl font-semibold">Welcome back</h2>
          <p className="text-muted text-sm mt-1 mb-6">Sign in to unlock your vault.</p>

          <form onSubmit={submit} className="space-y-3">
            <label className="block">
              <span className="text-xs text-muted ml-1">Email</span>
              <div className="relative mt-1">
                <Mail size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted" />
                <input
                  type="email"
                  required
                  autoComplete="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="field pl-10"
                  placeholder="you@email.com"
                />
              </div>
            </label>
            <label className="block">
              <span className="text-xs text-muted ml-1">Password</span>
              <div className="relative mt-1">
                <KeyRound size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted" />
                <input
                  type="password"
                  required
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="field pl-10"
                  placeholder="••••••••"
                />
              </div>
            </label>

            {error && (
              <div className="text-debit text-sm rounded-xl bg-debit/10 border border-debit/20 px-3 py-2">
                {error}
              </div>
            )}

            <button type="submit" disabled={busy} className="btn-primary w-full mt-2">
              {busy ? <Loader2 className="animate-spin" size={18} /> : <><Lock size={16} /> Unlock vault <ArrowRight size={16} /></>}
            </button>
          </form>

          <p className="text-[11px] text-muted text-center mt-5 leading-relaxed">
            Deriving your key runs Argon2id in your browser — unlocking can take a
            second. Nothing is sent anywhere.
          </p>
        </motion.div>
      </div>
    </div>
  );
}

function humanize(err) {
  const code = err?.code || '';
  if (code.includes('invalid-credential') || code.includes('wrong-password') || code.includes('user-not-found'))
    return 'Incorrect email or password.';
  if (code.includes('too-many-requests')) return 'Too many attempts — try again shortly.';
  if (code.includes('network')) return 'Network error — check your connection.';
  return err?.message || 'Could not sign in.';
}
