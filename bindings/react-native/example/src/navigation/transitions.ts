/**
 * Shared navigation transitions. Every screen change fades (duration from the
 * motion system) so the whole app has one consistent transition. Modals fade in
 * as a modal presentation. Built on `motion` so timings match component animations.
 */
import type { NativeStackNavigationOptions } from '@react-navigation/native-stack';
import { motion } from '../theme/system/motion';

/** Root-stack default: fade push/pop. */
export const screenFade: NativeStackNavigationOptions = {
  animation: 'fade',
  animationDuration: motion.duration.medium,
};

/** Modal presentation with the same fade. */
export const modalFade: NativeStackNavigationOptions = {
  presentation: 'modal',
  animation: 'fade',
  animationDuration: motion.duration.medium,
};
