import { createContext, useContext, useEffect, useState } from 'react';
import { useVault } from './Vault.jsx';
import {
  watchTransactions,
  watchBudgets,
  watchGoals,
  fetchProfile,
} from '../data/repo.js';

const DataCtx = createContext(null);
export const useData = () => useContext(DataCtx);

// Subscribes once (while unlocked) and shares decrypted data with every page.
export function DataProvider({ children }) {
  const { user, dek, status } = useVault();
  const [txns, setTxns] = useState([]);
  const [budgets, setBudgets] = useState([]);
  const [goals, setGoals] = useState([]);
  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (status !== 'unlocked' || !user || !dek) return;
    const uid = user.uid;
    setLoading(true);
    const onErr = (e) => setError(e?.message || String(e));

    const unsubTx = watchTransactions(uid, dek, (t) => {
      setTxns(t);
      setLoading(false);
    }, onErr);
    const unsubB = watchBudgets(uid, dek, setBudgets, onErr);
    const unsubG = watchGoals(uid, dek, setGoals, onErr);
    fetchProfile(uid, dek).then(setProfile).catch(onErr);

    return () => {
      unsubTx?.();
      unsubB?.();
      unsubG?.();
    };
  }, [status, user, dek]);

  const refreshProfile = () => {
    if (user && dek) fetchProfile(user.uid, dek).then(setProfile);
  };

  return (
    <DataCtx.Provider
      value={{ txns, budgets, goals, profile, loading, error, refreshProfile }}
    >
      {children}
    </DataCtx.Provider>
  );
}
