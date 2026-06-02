import { NavLink, useLocation } from 'react-router-dom';
import { motion } from 'framer-motion';
import {
  LayoutDashboard,
  ReceiptText,
  PieChart,
  Wallet,
  Target,
  Sparkles,
  Lock,
  LogOut,
  ShieldCheck,
} from 'lucide-react';
import { useVault } from '../state/Vault.jsx';

const NAV = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard, end: true },
  { to: '/transactions', label: 'Transactions', icon: ReceiptText },
  { to: '/charts', label: 'Charts', icon: PieChart },
  { to: '/budgets', label: 'Budgets', icon: Wallet },
  { to: '/goals', label: 'Goals', icon: Target },
  { to: '/assistant', label: 'Aeris AI', icon: Sparkles },
];

export default function AppShell({ children }) {
  const { user, lock, logout } = useVault();
  const location = useLocation();
  const title = NAV.find((n) => (n.end ? n.to === location.pathname : location.pathname.startsWith(n.to)))?.label || 'AERIS';

  return (
    <div className="min-h-screen flex">
      {/* Sidebar */}
      <aside className="hidden md:flex w-64 shrink-0 flex-col gap-2 p-4 border-r border-white/[0.06] sticky top-0 h-screen">
        <div className="flex items-center gap-2 px-3 py-4">
          <div className="h-9 w-9 rounded-2xl bg-gradient-to-br from-mint to-teal grid place-items-center text-[#042521] font-display font-bold">
            A
          </div>
          <div>
            <div className="font-display font-semibold leading-none">AERIS</div>
            <div className="text-[10px] text-muted tracking-widest uppercase">Web Vault</div>
          </div>
        </div>

        <nav className="flex flex-col gap-1 mt-2">
          {NAV.map((n) => (
            <NavLink
              key={n.to}
              to={n.to}
              end={n.end}
              className={({ isActive }) =>
                `nav-link ${isActive ? 'nav-link-active' : ''}`
              }
            >
              <n.icon size={18} />
              {n.label}
            </NavLink>
          ))}
        </nav>

        <div className="mt-auto flex flex-col gap-2">
          <div className="glass rounded-2xl px-3 py-2.5 flex items-center gap-2 text-xs text-muted">
            <ShieldCheck size={14} className="text-mint shrink-0" />
            End-to-end encrypted. Key in memory only.
          </div>
          <div className="px-3 text-xs text-muted truncate">{user?.email}</div>
          <div className="flex gap-2">
            <button onClick={lock} className="nav-link flex-1 justify-center text-xs">
              <Lock size={14} /> Lock
            </button>
            <button onClick={logout} className="nav-link flex-1 justify-center text-xs">
              <LogOut size={14} /> Sign out
            </button>
          </div>
        </div>
      </aside>

      {/* Main */}
      <div className="flex-1 min-w-0">
        {/* Mobile top bar */}
        <header className="md:hidden sticky top-0 z-20 flex items-center justify-between px-4 py-3 glass">
          <div className="font-display font-semibold">AERIS · {title}</div>
          <button onClick={lock} className="text-muted"><Lock size={18} /></button>
        </header>

        <motion.main
          key={location.pathname}
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.35, ease: [0.16, 1, 0.3, 1] }}
          className="max-w-6xl mx-auto px-4 sm:px-6 py-6 pb-28 md:pb-10"
        >
          {children}
        </motion.main>

        {/* Mobile bottom nav */}
        <nav className="md:hidden fixed bottom-0 inset-x-0 z-20 glass border-t border-white/10 flex justify-around py-2">
          {NAV.map((n) => (
            <NavLink
              key={n.to}
              to={n.to}
              end={n.end}
              className={({ isActive }) =>
                `flex flex-col items-center gap-0.5 px-2 py-1 text-[10px] ${isActive ? 'text-mint' : 'text-muted'}`
              }
            >
              <n.icon size={20} />
              {n.label.split(' ')[0]}
            </NavLink>
          ))}
        </nav>
      </div>
    </div>
  );
}
