/**
 * Restaurant API Service - Foursquare Places API Integration
 * 
 * Uses Foursquare's free tier (10,000 calls/month) for real restaurant data.
 * 
 * Get your FREE API key at: https://foursquare.com/developers/signup
 */

import { Platform } from 'react-native';

// ==============================================================================
// CONFIGURATION - Set your API key here!
// ==============================================================================

// Option 1: Set directly (for quick testing)
// Get your FREE key at: https://foursquare.com/developers/signup
const FOURSQUARE_API_KEY = '';

// Option 2: Will also check for environment variable
const getApiKey = (): string => {
  // Check hardcoded key first
  if (FOURSQUARE_API_KEY) {
    return FOURSQUARE_API_KEY;
  }
  
  // Try environment variable (for CI/production)
  // @ts-ignore - process.env might not be typed
  const envKey = process?.env?.FOURSQUARE_API_KEY;
  if (envKey) {
    return envKey;
  }
  
  return '';
};

// ==============================================================================
// TYPES
// ==============================================================================

// New Foursquare Places API response format (2025+)
export interface FoursquareRestaurant {
  fsq_place_id: string;  // New field name
  fsq_id?: string;       // Legacy fallback
  name: string;
  distance?: number;
  latitude?: number;     // Now at top level
  longitude?: number;    // Now at top level
  categories?: Array<{
    fsq_category_id: string;
    name: string;
    short_name?: string;
    plural_name?: string;
    icon?: {
      prefix: string;
      suffix: string;
    };
  }>;
  geocodes?: {
    main?: {
      latitude: number;
      longitude: number;
    };
  };
  location?: {
    address?: string;
    address_extended?: string;
    census_block?: string;
    country?: string;
    cross_street?: string;
    dma?: string;
    formatted_address?: string;
    locality?: string;
    postcode?: string;
    region?: string;
  };
  rating?: number;
  price?: number; // 1-4 scale ($ to $$$$)
  hours?: {
    display?: string;
    is_local_holiday?: boolean;
    open_now?: boolean;
  };
  photos?: Array<{
    id: string;
    created_at: string;
    prefix: string;
    suffix: string;
    width: number;
    height: number;
  }>;
  website?: string;
  tel?: string;
  tastes?: string[];
  features?: {
    delivery?: {
      providers?: Array<{
        name: string;
        url: string;
      }>;
    };
  };
}

export interface RestaurantSearchResult {
  id: string;
  name: string;
  cuisine: string[];
  rating: number;
  distance: string;
  address: string;
  priceLevel: string;
  isOpen: boolean;
  imageUrl?: string;
  deliveryProviders?: string[];
}

export interface SearchOptions {
  query?: string;
  cuisine?: string;
  latitude?: number;
  longitude?: number;
  radius?: number; // meters
  limit?: number;
  openNow?: boolean;
  priceMax?: number; // 1-4
}

// ==============================================================================
// API SERVICE
// ==============================================================================

// NEW Foursquare Places API endpoint (2025+)
const FOURSQUARE_BASE_URL = 'https://places-api.foursquare.com';
const FOURSQUARE_API_VERSION = '2025-06-17';

// Category IDs for food (Foursquare's category taxonomy)
const FOOD_CATEGORY_ID = '13000'; // Food & Dining
const RESTAURANT_CATEGORY_IDS = [
  '13065', // Restaurant
  '13199', // Fast Food
  '13145', // Pizzeria
  '13303', // Thai Restaurant
  '13276', // Mexican Restaurant
  '13263', // Japanese Restaurant
  '13236', // Indian Restaurant
  '13072', // American Restaurant
  '13099', // Burger Joint
  '13145', // Pizza Place
  '13352', // Sushi Restaurant
];

/**
 * Check if API is configured
 */
export function isApiConfigured(): boolean {
  return !!getApiKey();
}

// ==============================================================================
// LOCATION CONFIG - Set your demo location here, or use device location
// ==============================================================================

// Popular demo locations with lots of restaurants
export const DEMO_LOCATIONS = {
  SAN_FRANCISCO: { latitude: 37.7749, longitude: -122.4194, name: 'San Francisco, CA' },
  NEW_YORK: { latitude: 40.7128, longitude: -74.0060, name: 'New York, NY' },
  LOS_ANGELES: { latitude: 34.0522, longitude: -118.2437, name: 'Los Angeles, CA' },
  CHICAGO: { latitude: 41.8781, longitude: -87.6298, name: 'Chicago, IL' },
  MIAMI: { latitude: 25.7617, longitude: -80.1918, name: 'Miami, FL' },
  AUSTIN: { latitude: 30.2672, longitude: -97.7431, name: 'Austin, TX' },
  SEATTLE: { latitude: 47.6062, longitude: -122.3321, name: 'Seattle, WA' },
  BOSTON: { latitude: 42.3601, longitude: -71.0589, name: 'Boston, MA' },
} as const;

// Default location for demo (change to your city!)
let currentDemoLocation = DEMO_LOCATIONS.SAN_FRANCISCO;

/**
 * Set the demo location
 */
export function setDemoLocation(location: { latitude: number; longitude: number; name?: string }) {
  currentDemoLocation = { ...location, name: location.name || 'Custom Location' };
  console.log('[RestaurantAPI] Demo location set to:', currentDemoLocation.name);
}

/**
 * Get current demo location
 */
export function getDemoLocation() {
  return currentDemoLocation;
}

/**
 * Get user's current location
 * Uses device geolocation if available, falls back to demo location
 */
export async function getCurrentLocation(): Promise<{ latitude: number; longitude: number }> {
  // Try to get real device location using navigator.geolocation (works in React Native)
  return new Promise((resolve) => {
    // Check if geolocation is available
    if (typeof navigator !== 'undefined' && navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          console.log('[RestaurantAPI] 📍 Got real device location!');
          resolve({
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
          });
        },
        (error) => {
          console.log('[RestaurantAPI] Location error, using demo location:', error.message);
          resolve(currentDemoLocation);
        },
        {
          enableHighAccuracy: false,
          timeout: 5000,
          maximumAge: 60000, // 1 minute cache
        }
      );
    } else {
      console.log('[RestaurantAPI] Geolocation not available, using demo location');
      resolve(currentDemoLocation);
    }
  });
}

/**
 * Search for restaurants using Foursquare Places API
 */
export async function searchRestaurantsApi(options: SearchOptions = {}): Promise<RestaurantSearchResult[]> {
  const apiKey = getApiKey();
  
  if (!apiKey) {
    console.warn('[RestaurantAPI] No API key configured. Get one free at https://foursquare.com/developers/signup');
    return [];
  }
  
  try {
    // Get location
    let { latitude, longitude } = options;
    if (!latitude || !longitude) {
      const location = await getCurrentLocation();
      if (location) {
        latitude = location.latitude;
        longitude = location.longitude;
      } else {
        // Default to San Francisco
        latitude = 37.7749;
        longitude = -122.4194;
      }
    }
    
    // Build query params
    const params = new URLSearchParams({
      ll: `${latitude},${longitude}`,
      radius: String(options.radius || 5000), // 5km default
      limit: String(options.limit || 10),
      categories: FOOD_CATEGORY_ID, // Food category
      sort: 'RELEVANCE',
    });
    
    // Add query if provided
    if (options.query) {
      params.set('query', options.query);
    }
    
    // Add open now filter
    if (options.openNow) {
      params.set('open_now', 'true');
    }
    
    // Add price filter (1-4)
    if (options.priceMax) {
      params.set('max_price', String(options.priceMax));
    }
    
    console.log('[RestaurantAPI] Searching with params:', params.toString());
    
    // Make API request
    const response = await fetch(
      `${FOURSQUARE_BASE_URL}/places/search?${params.toString()}`,
      {
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Accept': 'application/json',
          'X-Places-Api-Version': FOURSQUARE_API_VERSION,
        },
      }
    );
    
    if (!response.ok) {
      const errorText = await response.text();
      console.error('[RestaurantAPI] API error:', response.status, errorText);
      throw new Error(`API error: ${response.status}`);
    }
    
    const data = await response.json();
    console.log('[RestaurantAPI] Got', data.results?.length || 0, 'results');
    
    // Transform to our format
    return (data.results || []).map((place: FoursquareRestaurant) => transformToResult(place));
    
  } catch (error) {
    console.error('[RestaurantAPI] Search failed:', error);
    return [];
  }
}

/**
 * Get restaurant details
 */
export async function getRestaurantDetails(fsqId: string): Promise<FoursquareRestaurant | null> {
  const apiKey = getApiKey();
  
  if (!apiKey) {
    console.warn('[RestaurantAPI] No API key configured');
    return null;
  }
  
  try {
    const response = await fetch(
      `${FOURSQUARE_BASE_URL}/places/${fsqId}`,
      {
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Accept': 'application/json',
          'X-Places-Api-Version': FOURSQUARE_API_VERSION,
        },
      }
    );
    
    if (!response.ok) {
      throw new Error(`API error: ${response.status}`);
    }
    
    return await response.json();
    
  } catch (error) {
    console.error('[RestaurantAPI] Get details failed:', error);
    return null;
  }
}

/**
 * Get restaurant photos
 */
export async function getRestaurantPhotos(fsqId: string, limit: number = 5): Promise<string[]> {
  const apiKey = getApiKey();
  
  if (!apiKey) {
    return [];
  }
  
  try {
    const response = await fetch(
      `${FOURSQUARE_BASE_URL}/places/${fsqId}/photos?limit=${limit}`,
      {
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Accept': 'application/json',
          'X-Places-Api-Version': FOURSQUARE_API_VERSION,
        },
      }
    );
    
    if (!response.ok) {
      return [];
    }
    
    const photos = await response.json();
    return photos.map((photo: any) => `${photo.prefix}300x300${photo.suffix}`);
    
  } catch (error) {
    return [];
  }
}

// ==============================================================================
// HELPERS
// ==============================================================================

function transformToResult(place: FoursquareRestaurant): RestaurantSearchResult {
  // Get cuisines from categories
  const cuisines = place.categories?.map(c => c.short_name || c.name) || ['Restaurant'];
  
  // Format distance
  const distanceStr = place.distance 
    ? place.distance < 1000 
      ? `${place.distance}m`
      : `${(place.distance / 1000).toFixed(1)}km`
    : 'Unknown';
  
  // Format price level
  const priceLevel = place.price 
    ? '$'.repeat(place.price)
    : '$$';
  
  // Get first photo if available
  const imageUrl = place.photos?.[0]
    ? `${place.photos[0].prefix}300x200${place.photos[0].suffix}`
    : undefined;
  
  // Get delivery providers
  const deliveryProviders = place.features?.delivery?.providers?.map(p => p.name) || [];
  
  return {
    id: place.fsq_place_id || place.fsq_id || 'unknown',  // Use new field name with fallback
    name: place.name,
    cuisine: cuisines,
    rating: place.rating ? place.rating / 2 : 4.0, // Foursquare uses 10 scale, we use 5
    distance: distanceStr,
    address: place.location?.formatted_address || place.location?.address || 'Address unavailable',
    priceLevel,
    isOpen: place.hours?.open_now ?? true,
    imageUrl,
    deliveryProviders,
  };
}

/**
 * Map cuisine queries to Foursquare search terms
 */
export function mapCuisineQuery(query: string): string {
  const cuisineMap: Record<string, string> = {
    // Standard cuisines
    'thai': 'thai restaurant',
    'pizza': 'pizza',
    'burger': 'burger',
    'burgers': 'burger',
    'sushi': 'sushi',
    'japanese': 'japanese restaurant',
    'mexican': 'mexican restaurant',
    'tacos': 'tacos',
    'chinese': 'chinese restaurant',
    'indian': 'indian restaurant',
    'italian': 'italian restaurant',
    'korean': 'korean restaurant',
    'vietnamese': 'vietnamese restaurant',
    'mediterranean': 'mediterranean restaurant',
    'fast food': 'fast food',
    'healthy': 'healthy food',
    'vegan': 'vegan restaurant',
    'vegetarian': 'vegetarian restaurant',
    'breakfast': 'breakfast restaurant',
    'brunch': 'brunch',
    'coffee': 'coffee shop',
    'dessert': 'dessert',
    'churros': 'churros',
    
    // Fun/situational queries 🔥
    'bar': 'bar',
    'drinks': 'bar',
    'strong drinks': 'bar',
    'beer': 'bar',
    'cocktails': 'cocktail bar',
    'wine': 'wine bar',
    'ice cream': 'ice cream',
    'dumped': 'ice cream',
    'comfort': 'comfort food',
    'ramen': 'ramen',
    'noodles': 'noodle shop',
    'steak': 'steakhouse',
    'fancy': 'fine dining',
    'expensive': 'fine dining',
    'classy': 'fine dining',
    'greasy': 'diner',
    'hungover': 'breakfast restaurant',
    'late night': 'late night food',
    '2am': 'late night food',
    '3am': 'late night food',
    'pasta': 'italian restaurant',
    'romantic': 'fine dining',
    'date': 'fine dining',
    'first date': 'cocktail bar',
    'in-laws': 'fine dining',
    
    // Startup/founder culture 🚀
    'startup': 'coffee shop',
    'coffee': 'coffee shop',
    'caffeine': 'coffee shop',
    'sadness': 'comfort food',
    'pivoted': 'ramen',
    'demo day': 'pizza',
    'investor': 'sushi',
    'ghosted': 'sushi',
    'cope': 'comfort food',
    'reward': 'fine dining',
    'founder': 'coffee shop',
    'yc': 'pizza',
    'hackathon': 'pizza',
    'nuggets': 'fast food',
    'bougie': 'fine dining',
    'series a': 'fine dining',
    'bootstrapping': 'ramen',
    'impostor': 'comfort food',
    'stress': 'pizza',
    'cholesterol': 'burger',
    'metric': 'burger',
    'cheeseburger': 'burger',
    'double': 'burger',
  };
  
  const lowerQuery = query.toLowerCase();
  
  // Check for exact matches first
  if (cuisineMap[lowerQuery]) {
    return cuisineMap[lowerQuery];
  }
  
  // Check for partial matches
  for (const [key, value] of Object.entries(cuisineMap)) {
    if (lowerQuery.includes(key)) {
      return value;
    }
  }
  
  // Return original query if no mapping found
  return query;
}

// ==============================================================================
// DEMO HELPER - For showing API setup instructions
// ==============================================================================

export function getApiSetupInstructions(): string {
  return `
🔑 FREE Restaurant API Setup (2 minutes):

1. Go to: https://foursquare.com/developers/signup
2. Create a free account
3. Create a new project
4. Copy your API key
5. Paste it in: src/services/restaurantApi.ts (line 15)

✅ Free tier includes 10,000 API calls/month!
  `.trim();
}
