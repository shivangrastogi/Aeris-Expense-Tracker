import {
  Utensils,
  ShoppingCart,
  Car,
  ShoppingBag,
  ReceiptText,
  Clapperboard,
  HeartPulse,
  Home,
  TrendingUp,
  ArrowLeftRight,
  Briefcase,
  Banknote,
  GraduationCap,
  Sparkles,
  MoreHorizontal,
} from 'lucide-react';
import { categoryById } from '../data/categories.js';

const MAP = {
  Utensils, ShoppingCart, Car, ShoppingBag, ReceiptText, Clapperboard,
  HeartPulse, Home, TrendingUp, ArrowLeftRight, Briefcase, Banknote,
  GraduationCap, Sparkles, MoreHorizontal,
};

export default function CategoryIcon({ id, size = 18, className = '' }) {
  const c = categoryById(id);
  const Icon = MAP[c.icon] || MoreHorizontal;
  return <Icon size={size} className={className} style={{ color: c.color }} />;
}
