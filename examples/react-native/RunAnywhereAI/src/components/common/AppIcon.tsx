import React from 'react';
import {
  Activity,
  AlertCircle,
  AlertTriangle,
  ArrowUp,
  ArrowUpCircle,
  Send,
  Box,
  CheckCircle2,
  ChevronRight,
  Clock,
  CloudDownload,
  Copy,
  Cpu,
  Eye,
  FileText,
  FlaskConical,
  Gauge,
  Hammer,
  History,
  Hourglass,
  Image as ImageIcon,
  Info,
  Camera,
  LayoutGrid,
  Lightbulb,
  List,
  Mic,
  MessageCircle,
  MessagesSquare,
  Minus,
  Music,
  Plus,
  PlusCircle,
  Radio,
  RefreshCw,
  ScanLine,
  Search,
  Server,
  Settings,
  Smartphone,
  Sparkles,
  Square,
  Trash2,
  Volume2,
  Waves,
  Wrench,
  X,
  XCircle,
  Zap,
} from 'lucide-react-native';
import type { LucideIcon } from 'lucide-react-native';

export type AppIconName =
  | 'add'
  | 'add-circle'
  | 'add-circle-outline'
  | 'alert-circle'
  | 'alert-circle-outline'
  | 'alert-triangle'
  | 'analytics-outline'
  | 'arrow-up'
  | 'arrow-up-circle'
  | 'send'
  | 'build-outline'
  | 'bulb-outline'
  | 'camera'
  | 'camera-outline'
  | 'chat'
  | 'chat-filled'
  | 'chatbubble'
  | 'chatbubble-ellipses-outline'
  | 'chatbubble-outline'
  | 'chatbubbles-outline'
  | 'checkmark-circle'
  | 'checkmark-circle-outline'
  | 'chevron-forward'
  | 'close'
  | 'close-circle'
  | 'cloud-download-outline'
  | 'construct-outline'
  | 'copy-outline'
  | 'cube-outline'
  | 'document-text-outline'
  | 'eye'
  | 'eye-filled'
  | 'eye-outline'
  | 'flash-outline'
  | 'flask-outline'
  | 'grid'
  | 'grid-filled'
  | 'hardware-chip-outline'
  | 'history'
  | 'hourglass'
  | 'hourglass-outline'
  | 'images-outline'
  | 'information-circle-outline'
  | 'list'
  | 'mic'
  | 'mic-filled'
  | 'mic-circle-outline'
  | 'mic-outline'
  | 'musical-notes'
  | 'phone-portrait-outline'
  | 'pulse'
  | 'pulse-outline'
  | 'radio-outline'
  | 'refresh'
  | 'remove'
  | 'scan-outline'
  | 'search'
  | 'search-outline'
  | 'server-outline'
  | 'settings'
  | 'settings-filled'
  | 'settings-outline'
  | 'sparkles-outline'
  | 'speedometer-outline'
  | 'stats-chart'
  | 'stop'
  | 'time-outline'
  | 'trash-outline'
  | 'volume-high'
  | 'volume-high-outline'
  | 'warning-outline';

const iconMap: Record<AppIconName, LucideIcon> = {
  'add': Plus,
  'add-circle': PlusCircle,
  'add-circle-outline': PlusCircle,
  'alert-circle': AlertCircle,
  'alert-circle-outline': AlertCircle,
  'alert-triangle': AlertTriangle,
  'analytics-outline': Activity,
  'arrow-up': ArrowUp,
  'arrow-up-circle': ArrowUpCircle,
  'send': Send,
  'build-outline': Wrench,
  'bulb-outline': Lightbulb,
  'camera': Camera,
  'camera-outline': Camera,
  'chat': MessageCircle,
  'chat-filled': MessageCircle,
  'chatbubble': MessageCircle,
  'chatbubble-ellipses-outline': MessageCircle,
  'chatbubble-outline': MessageCircle,
  'chatbubbles-outline': MessagesSquare,
  'checkmark-circle': CheckCircle2,
  'checkmark-circle-outline': CheckCircle2,
  'chevron-forward': ChevronRight,
  'close': X,
  'close-circle': XCircle,
  'cloud-download-outline': CloudDownload,
  'construct-outline': Hammer,
  'copy-outline': Copy,
  'cube-outline': Box,
  'document-text-outline': FileText,
  'eye': Eye,
  'eye-filled': Eye,
  'eye-outline': Eye,
  'flash-outline': Zap,
  'flask-outline': FlaskConical,
  'grid': LayoutGrid,
  'grid-filled': LayoutGrid,
  'hardware-chip-outline': Cpu,
  'history': History,
  'hourglass': Hourglass,
  'hourglass-outline': Hourglass,
  'images-outline': ImageIcon,
  'information-circle-outline': Info,
  'list': List,
  'mic': Mic,
  'mic-filled': Mic,
  'mic-circle-outline': Mic,
  'mic-outline': Mic,
  'musical-notes': Music,
  'phone-portrait-outline': Smartphone,
  'pulse': Activity,
  'pulse-outline': Waves,
  'radio-outline': Radio,
  'refresh': RefreshCw,
  'remove': Minus,
  'scan-outline': ScanLine,
  'search': Search,
  'search-outline': Search,
  'server-outline': Server,
  'settings': Settings,
  'settings-filled': Settings,
  'settings-outline': Settings,
  'sparkles-outline': Sparkles,
  'speedometer-outline': Gauge,
  'stats-chart': Activity,
  'stop': Square,
  'time-outline': Clock,
  'trash-outline': Trash2,
  'volume-high': Volume2,
  'volume-high-outline': Volume2,
  'warning-outline': AlertTriangle,
};

type AppIconProps = {
  name: AppIconName | (string & {});
  size?: number;
  color?: string;
  strokeWidth?: number;
  style?: import('react-native').StyleProp<import('react-native').ViewStyle>;
};

export const AppIcon: React.FC<AppIconProps> = ({
  name,
  size = 20,
  color,
  strokeWidth = 1.75,
}) => {
  const Component = iconMap[name as AppIconName] ?? AlertCircle;
  return <Component size={size} color={color} strokeWidth={strokeWidth} />;
};

export default AppIcon;
