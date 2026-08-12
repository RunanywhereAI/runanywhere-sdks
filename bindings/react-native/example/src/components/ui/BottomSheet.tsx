/**
 * BottomSheet — the app's reusable bottom sheet, built on react-native-actions-sheet
 * (real snap points, drag, fling/momentum; works with reanimated 4, unlike
 * @gorhom/bottom-sheet). Styled from our design tokens: surface panel with rounded
 * top, themed grabber + scrim, snap points from the motion-consistent theme.
 *
 * Driven by a `visible`/`onClose` prop pair so it drops into the existing screen
 * state pattern. Scrollable content should use the re-exported BottomSheetScrollView
 * / BottomSheetFlatList (gesture-aware) so inner scrolling coordinates with the sheet.
 */
import React, { useEffect, useMemo, useRef } from 'react';
import { View } from 'react-native';
import ActionSheet, { type ActionSheetRef } from 'react-native-actions-sheet';
import { useTheme } from '../../theme/system';

/** Our snap points are strings like '60%' / numbers; the lib wants number[] (percent). */
function toSnapNumbers(
  snapPoints?: Array<string | number>
): number[] | undefined {
  if (!snapPoints || snapPoints.length === 0) return undefined;
  return snapPoints.map((p) => (typeof p === 'number' ? p : parseFloat(p)));
}

export interface BottomSheetProps {
  visible: boolean;
  onClose: () => void;
  /** Snap points (e.g. ['60%', '92%']); opens at the first. */
  snapPoints?: Array<string | number>;
  children: React.ReactNode;
}

export const BottomSheet: React.FC<BottomSheetProps> = ({
  visible,
  onClose,
  snapPoints,
  children,
}) => {
  const { colors, dimens } = useTheme();
  const ref = useRef<ActionSheetRef>(null);
  const points = useMemo(() => toSnapNumbers(snapPoints), [snapPoints]);

  useEffect(() => {
    if (visible) {
      ref.current?.show();
    } else {
      ref.current?.hide();
    }
  }, [visible]);

  return (
    <ActionSheet
      ref={ref}
      gestureEnabled
      snapPoints={points}
      initialSnapIndex={0}
      onClose={onClose}
      overlayColor={colors.scrim}
      defaultOverlayOpacity={0.45}
      indicatorStyle={{
        backgroundColor: colors.outlineVariant,
        width: 40,
        height: 4,
        borderRadius: 999,
        marginVertical: 8,
      }}
      containerStyle={{
        backgroundColor: colors.surface,
        borderTopLeftRadius: dimens.radius.lg,
        borderTopRightRadius: dimens.radius.lg,
      }}
    >
      {children}
    </ActionSheet>
  );
};

/** Content helpers — gesture-aware, drop-in for the migrated screens. */
export const BottomSheetView = View;
export {
  ScrollView as BottomSheetScrollView,
  FlatList as BottomSheetFlatList,
} from 'react-native-actions-sheet';

export default BottomSheet;
