/**
 * MenuItemCard - DoorDash style menu item card
 */

import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { DoorDashColors, DoorDashTypography, DoorDashSpacing, DoorDashShadows } from '../../theme/doordash';
import type { MenuItem } from '../../data/foodData';

interface MenuItemCardProps {
  item: MenuItem;
  onPress: (item: MenuItem) => void;
  onAddToCart: (item: MenuItem) => void;
}

export const MenuItemCard: React.FC<MenuItemCardProps> = ({ item, onPress, onAddToCart }) => {
  return (
    <TouchableOpacity
      style={styles.container}
      onPress={() => onPress(item)}
      activeOpacity={0.95}
    >
      <View style={styles.content}>
        {/* Text Content */}
        <View style={styles.textContent}>
          <View style={styles.nameRow}>
            <Text style={styles.name} numberOfLines={2}>{item.name}</Text>
            {item.isPopular && (
              <View style={styles.popularBadge}>
                <Text style={styles.popularText}>Popular</Text>
              </View>
            )}
          </View>
          
          <Text style={styles.description} numberOfLines={2}>
            {item.description}
          </Text>
          
          <View style={styles.metaRow}>
            <Text style={styles.price}>${item.price.toFixed(2)}</Text>
            {item.calories && (
              <Text style={styles.calories}>{item.calories} cal</Text>
            )}
            {item.isSpicy && (
              <Text style={styles.spicyIcon}>🌶️</Text>
            )}
            {item.isVegetarian && (
              <Text style={styles.vegIcon}>🌱</Text>
            )}
          </View>
        </View>
        
        {/* Image & Add Button */}
        <View style={styles.rightSection}>
          <View style={styles.imagePlaceholder}>
            <Text style={styles.imageEmoji}>{item.image}</Text>
          </View>
          <TouchableOpacity
            style={styles.addButton}
            onPress={(e) => {
              e.stopPropagation();
              onAddToCart(item);
            }}
          >
            <Icon name="add" size={20} color={DoorDashColors.textWhite} />
          </TouchableOpacity>
        </View>
      </View>
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
  container: {
    backgroundColor: DoorDashColors.background,
    borderRadius: DoorDashSpacing.radiusMedium,
    marginBottom: DoorDashSpacing.md,
    ...DoorDashShadows.card,
  },
  content: {
    flexDirection: 'row',
    padding: DoorDashSpacing.md,
  },
  textContent: {
    flex: 1,
    marginRight: DoorDashSpacing.md,
  },
  nameRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    marginBottom: DoorDashSpacing.xs,
  },
  name: {
    ...DoorDashTypography.bodyLarge,
    fontWeight: '600',
    color: DoorDashColors.textPrimary,
    flex: 1,
  },
  popularBadge: {
    backgroundColor: DoorDashColors.warningLight,
    paddingHorizontal: DoorDashSpacing.sm,
    paddingVertical: 2,
    borderRadius: DoorDashSpacing.radiusSmall,
    marginLeft: DoorDashSpacing.sm,
  },
  popularText: {
    ...DoorDashTypography.caption,
    fontWeight: '600',
    color: DoorDashColors.warning,
  },
  description: {
    ...DoorDashTypography.bodySmall,
    color: DoorDashColors.textSecondary,
    marginBottom: DoorDashSpacing.sm,
    lineHeight: 18,
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: DoorDashSpacing.sm,
  },
  price: {
    ...DoorDashTypography.price,
    color: DoorDashColors.textPrimary,
  },
  calories: {
    ...DoorDashTypography.caption,
    color: DoorDashColors.textTertiary,
  },
  spicyIcon: {
    fontSize: 12,
  },
  vegIcon: {
    fontSize: 12,
  },
  rightSection: {
    alignItems: 'center',
    position: 'relative',
  },
  imagePlaceholder: {
    width: 80,
    height: 80,
    borderRadius: DoorDashSpacing.radiusMedium,
    backgroundColor: DoorDashColors.backgroundSecondary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  imageEmoji: {
    fontSize: 36,
  },
  addButton: {
    position: 'absolute',
    bottom: -8,
    right: -8,
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: DoorDashColors.primary,
    justifyContent: 'center',
    alignItems: 'center',
    ...DoorDashShadows.button,
  },
});

export default MenuItemCard;
