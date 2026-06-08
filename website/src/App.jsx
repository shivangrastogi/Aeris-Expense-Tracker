import { Routes, Route, Navigate } from 'react-router-dom';
import { useVault } from './state/Vault.jsx';
import { DataProvider } from './state/Data.jsx';
import AppShell from './components/AppShell.jsx';
import Login from './pages/Login.jsx';
import Unlock from './pages/Unlock.jsx';
import Dashboard from './pages/Dashboard.jsx';
import Transactions from './pages/Transactions.jsx';
import Charts from './pages/Charts.jsx';
import Budgets from './pages/Budgets.jsx';
import Goals from './pages/Goals.jsx';
import Assistant from './pages/Assistant.jsx';
import Wrapped from './pages/Wrapped.jsx';
import { Loader2 } from 'lucide-react';

function Splash() {
  return (
    <div className="min-h-screen grid place-items-center">
      <Loader2 className="animate-spin text-mint" size={32} />
    </div>
  );
}

export default function App() {
  const { status } = useVault();

  return (
    <>
      <div className="bg-aurora" />
      <div className="grain" />
      {status === 'loading' && <Splash />}
      {status === 'signedOut' && <Login />}
      {status === 'locked' && <Unlock />}
      {status === 'unlocked' && (
        <DataProvider>
          <AppShell>
            <Routes>
              <Route path="/" element={<Dashboard />} />
              <Route path="/transactions" element={<Transactions />} />
              <Route path="/charts" element={<Charts />} />
              <Route path="/budgets" element={<Budgets />} />
              <Route path="/goals" element={<Goals />} />
              <Route path="/wrapped" element={<Wrapped />} />
              <Route path="/assistant" element={<Assistant />} />
              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
          </AppShell>
        </DataProvider>
      )}
    </>
  );
}
