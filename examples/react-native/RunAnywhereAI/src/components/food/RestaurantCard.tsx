/**
 * RestaurantCard - DoorDash style restaurant card
 */

import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Image,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { DoorDashColors, DoorDashTypography, DoorDashSpacing, DoorDashShadows } from '../../theme/doordash';
import type { Restaurant } from '../../data/foodData';

interface RestaurantCardProps {
  restaurant: Restaurant;
  onPress: (restaurant: Restaurant) => void;
}

export const RestaurantCard: React.FC<RestaurantCardProps> = ({ restaurant, onPress }) => {
  return (
    <TouchableOpacity
      style={styles.container}
      onPress={() => onPress(restaurant)}
      activeOpacity={0.95}
    >
      {/* Image Section */}
      <View style={styles.imageContainer}>
        <View style={styles.imagePlaceholder}>
          <Text style={styles.imageEmoji}>{restaurant.image}</Text>
        </View>
        
        {/* Badges */}
        <View style={styles.badgeContainer}>
          {restaurant.dashPassFree && (
            <View style={[styles.badge, styles.dashPassBadge]}>
              <Text style={styles.dashPassText}>DashPass</Text>
            </View>
          )}
          {restaurant.promo && (
            <View style={[styles.badge, styles.promoBadge]}>
              <Text style={styles.promoText}>{restaurant.promo}</Text>
            </View>
          )}
        </View>
        
        {/* Delivery Time Pill */}
        <View style={styles.deliveryTimePill}>
          <Text style={styles.deliveryTimeText}>{restaurant.deliveryTime}</Text>
        </View>
      </View>
      
      {/* Content Section */}
      <View style={styles.content}>
        {/* Restaurant Name & Rating */}
        <View style={styles.headerRow}>
          <Text style={styles.name} numberOfLines={1}>{restaurant.name}</Text>
          <View style={styles.ratingContainer}>
            <Text style={styles.rating}>{restaurant.rating.toFixed(1)}</Text>
            <Icon name="star" size={12} color={DoorDashColors.ratingGold} />
          </View>
        </View>
        
        {/* Cuisine & Distance */}
        <Text style={styles.subtitle} numberOfLines={1}>
          {restaurant.cuisine.join(' • ')} • {restaurant.distance}
        </Text>
        
        {/* Delivery Fee */}
        <View style={styles.deliveryRow}>
          {restaurant.deliveryFee === 0 ? (
            <Text style={styles.freeDelivery}>$0 delivery fee</Text>
          ) : (
            <Text style={styles.deliveryFee}>${restaurant.deliveryFee.toFixed(2)} delivery</Text>
          )}
          <Text style={styles.reviewCount}>({restaurant.reviewCount.toLocaleString()}+ ratings)</Text>
        </View>
      </View>
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
  container: {
    backgroundColor: DoorDashColors.background,
    borderRadius: DoorDashSpacing.radiusLarge,
    marginBottom: DoorDashSpacing.lg,
    ...DoorDashShadows.card,
  },
  imageContainer: {
    height: 160,
    borderTopLeftRadius: DoorDashSpacing.radiusLarge,
    borderTopRightRadius: DoorDashSpacing.radiusLarge,
    overflow: 'hidden',
    position: 'relative',
  },
  imagePlaceholder: {
    flex: 1,
    backgroundColor: DoorDashColors.backgroundSecondary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  imageEmoji: {
    fontSize: 64,
  },
  badgeContainer: {
    position: 'absolute',
    top: DoorDashSpacing.sm,
    left: DoorDashSpacing.sm,
    flexDirection: 'row',
    gap: DoorDashSpacing.xs,
  },
  badge: {
    paddingHorizontal: DoorDashSpacing.sm,
    paddingVertical: DoorDashSpacing.xs,
    borderRadius: DoorDashSpacing.radiusSmall,
  },
  dashPassBadge: {
    backgroundColor: DoorDashColors.dashPassPurple,
  },
  dashPassText: {
    ...DoorDashTypography.badge,
    color: DoorDashColors.textWhite,
  },
  promoBadge: {
    backgroundColor: DoorDashColors.promoGreen,
  },
  promoText: {
    ...DoorDashTypography.badge,
    color: DoorDashColors.textWhite,
  },
  deliveryTimePill: {
    position: 'absolute',
    bottom: DoorDashSpacing.sm,
    right: DoorDashSpacing.sm,
    backgroundColor: DoorDashColors.background,
    paddingHorizontal: DoorDashSpacing.sm,
    paddingVertical: DoorDashSpacing.xs,
    borderRadius: DoorDashSpacing.radiusFull,
    ...DoorDashShadows.button,
  },
  deliveryTimeText: {
    ...DoorDashTypography.bodySmall,
    fontWeight: '600',
    color: DoorDashColors.textPrimary,
  },
  content: {
    padding: DoorDashSpacing.md,
  },
  headerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: DoorDashSpacing.xs,
  },
  name: {
    ...DoorDashTypography.headerSmall,
    color: DoorDashColors.textPrimary,
    flex: 1,
    marginRight: DoorDashSpacing.sm,
  },
  ratingContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 2,
    backgroundColor: DoorDashColors.backgroundSecondary,
    paddingHorizontal: DoorDashSpacing.sm,
    paddingVertical: DoorDashSpacing.xs,
    borderRadius: DoorDashSpacing.radiusFull,
  },
  rating: {
    ...DoorDashTypography.bodySmall,
    fontWeight: '600',
    color: DoorDashColors.textPrimary,
  },
  subtitle: {
    ...DoorDashTypography.bodySmall,
    color: DoorDashColors.textSecondary,
    marginBottom: DoorDashSpacing.xs,
  },
  deliveryRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: DoorDashSpacing.sm,
  },
  freeDelivery: {
    ...DoorDashTypography.bodySmall,
    fontWeight: '600',
    color: DoorDashColors.success,
  },
  deliveryFee: {
    ...DoorDashTypography.bodySmall,
    color: DoorDashColors.textSecondary,
  },
  reviewCount: {
    ...DoorDashTypography.bodySmall,
    color: DoorDashColors.textTertiary,
  },
});

export default RestaurantCard;
