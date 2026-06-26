/**
 * Typed param lists for the mono navigation graph. `RootStackParamList` is the
 * flat root stack (tabs container + every feature screen + modals); `TabParamList`
 * is the 3-tab bar. Params are `undefined` until a screen's rebuild defines its
 * real contract. The global augmentation makes `useNavigation()` typed app-wide
 * with no per-call generics.
 */
import type {
  NavigatorScreenParams,
  CompositeScreenProps,
} from '@react-navigation/native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { BottomTabScreenProps } from '@react-navigation/bottom-tabs';

export type TabParamList = {
  Chat: undefined;
  Voice: undefined;
  More: undefined;
};

export type RootStackParamList = {
  Tabs: NavigatorScreenParams<TabParamList> | undefined;

  // Feature screens (flat, directly navigable).
  Vision: undefined;
  Vlm: undefined;
  Transcribe: undefined;
  Speak: undefined;
  Vad: undefined;
  Rag: undefined;
  Storage: undefined;
  Solutions: undefined;
  Benchmarks: undefined;
  Settings: undefined;

  // Modals.
  ModelSelection: undefined;
  Lora: undefined;
  ConversationList: undefined;
  ChatAnalytics: undefined;
};

/** Props for a screen on the root stack. */
export type RootStackScreenProps<T extends keyof RootStackParamList> =
  NativeStackScreenProps<RootStackParamList, T>;

/** Props for a tab screen — composed so tab screens can also reach root routes. */
export type TabScreenProps<T extends keyof TabParamList> = CompositeScreenProps<
  BottomTabScreenProps<TabParamList, T>,
  NativeStackScreenProps<RootStackParamList>
>;

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace ReactNavigation {
    interface RootParamList extends RootStackParamList {}
  }
}
