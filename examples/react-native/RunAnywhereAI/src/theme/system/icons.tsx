/**
 * App icon set — Lucide icons, wrapped so screens reference semantic names
 * instead of importing glyphs directly. Defaults: 24px, stroke width 2; `color`
 * falls through to the caller (Lucide defaults to currentColor when unset).
 *
 * Grows as screens migrate off react-native-vector-icons; once nothing imports
 * Ionicons, that dependency is removed in one step. Backed by react-native-svg.
 */
import React from 'react';
import {
  MessageCircle,
  Mic,
  Ellipsis,
  ArrowUp,
  Eye,
  AudioLines,
  Volume2,
  Search,
  Activity,
  Folder,
  Layers,
  Gauge,
  Settings,
  ChevronRight,
  ChevronDown,
  Download,
  Check,
  Cpu,
  HardDrive,
  X,
  SlidersHorizontal,
  Info,
  History,
  Plus,
  Sparkles,
  Trash2,
  MessageSquarePlus,
  Cloud,
  Square,
  MicOff,
  Wrench,
  Clock,
  Battery,
  Calculator,
  Zap,
  Monitor,
} from 'lucide-react-native';

const ICONS = {
  chat: MessageCircle,
  voice: Mic,
  more: Ellipsis,
  vision: Eye,
  transcribe: AudioLines,
  speak: Volume2,
  rag: Search,
  search: Search,
  vad: Activity,
  storage: Folder,
  solutions: Layers,
  benchmarks: Gauge,
  settings: Settings,
  chevronRight: ChevronRight,
  chevronDown: ChevronDown,
  download: Download,
  check: Check,
  cpu: Cpu,
  storageDevice: HardDrive,
  close: X,
  sliders: SlidersHorizontal,
  info: Info,
  history: History,
  plus: Plus,
  sparkles: Sparkles,
  trash: Trash2,
  newChat: MessageSquarePlus,
  send: ArrowUp,
  cloud: Cloud,
  stop: Square,
  micOff: MicOff,
  tool: Wrench,
  clock: Clock,
  battery: Battery,
  calculator: Calculator,
  bolt: Zap,
  host: Monitor,
} as const;

export type IconName = keyof typeof ICONS;

export interface IconProps {
  name: IconName;
  size?: number;
  color?: string;
  strokeWidth?: number;
}

export const Icon: React.FC<IconProps> = ({
  name,
  size = 24,
  color,
  strokeWidth = 2,
}) => {
  const Glyph = ICONS[name];
  return <Glyph size={size} color={color} strokeWidth={strokeWidth} />;
};

export default Icon;
