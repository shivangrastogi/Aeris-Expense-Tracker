import { useRef, useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { Send, Sparkles, ShieldCheck } from 'lucide-react';
import { useData } from '../state/Data.jsx';
import { answer, SUGGESTIONS } from '../services/assistant.js';

export default function Assistant() {
  const { txns, budgets, profile } = useData();
  const [messages, setMessages] = useState([
    { role: 'aeris', text: "Hi, I'm Aeris ✨ I read your transactions right here in your browser — nothing leaves this tab. Ask me anything about your money." },
  ]);
  const [input, setInput] = useState('');
  const endRef = useRef(null);

  useEffect(() => { endRef.current?.scrollIntoView({ behavior: 'smooth' }); }, [messages]);

  function ask(text) {
    const q = (text ?? input).trim();
    if (!q) return;
    const reply = answer(q, { txns, budgets, monthlyIncome: profile?.monthlyIncome ?? null });
    setMessages((m) => [...m, { role: 'me', text: q }, { role: 'aeris', text: reply }]);
    setInput('');
  }

  return (
    <div className="flex flex-col h-[calc(100vh-7rem)] md:h-[calc(100vh-3rem)] max-w-3xl mx-auto">
      <div className="flex items-center gap-3 pb-4">
        <div className="h-11 w-11 rounded-2xl bg-gradient-to-br from-mint to-teal grid place-items-center text-[#042521]"><Sparkles size={20} /></div>
        <div>
          <h1 className="font-display text-xl font-semibold leading-none">Aeris</h1>
          <div className="text-xs text-muted flex items-center gap-1 mt-1"><ShieldCheck size={12} className="text-mint" /> On-device · private</div>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto space-y-3 pr-1">
        {messages.map((m, i) => (
          <motion.div key={i} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.25 }}
            className={`flex ${m.role === 'me' ? 'justify-end' : 'justify-start'}`}>
            <div className={`max-w-[80%] rounded-2xl px-4 py-2.5 whitespace-pre-line text-sm leading-relaxed ${
              m.role === 'me' ? 'bg-mint text-[#042521] rounded-br-md' : 'glass rounded-bl-md'
            }`}>
              {m.text}
            </div>
          </motion.div>
        ))}
        <div ref={endRef} />
      </div>

      {/* Suggestions */}
      <div className="flex gap-2 overflow-x-auto py-3 -mx-1 px-1">
        {SUGGESTIONS.map((s) => (
          <button key={s} onClick={() => ask(s)}
            className="shrink-0 glass rounded-full px-3.5 py-2 text-xs text-muted hover:text-ink hover:border-mint/40 transition-colors">
            {s}
          </button>
        ))}
      </div>

      <form onSubmit={(e) => { e.preventDefault(); ask(); }} className="flex gap-2">
        <input value={input} onChange={(e) => setInput(e.target.value)} className="field" placeholder="Ask about your spending…" />
        <button type="submit" className="btn-primary !px-4"><Send size={18} /></button>
      </form>
    </div>
  );
}
