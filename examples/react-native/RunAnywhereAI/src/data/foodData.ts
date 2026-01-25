/**
 * Mock Food Data - Restaurants and Menu Items
 * 
 * Realistic data for the DoorDash clone demo
 */

export interface MenuItem {
  id: string;
  name: string;
  description: string;
  price: number;
  originalPrice?: number;
  image: string;
  category: string;
  isPopular?: boolean;
  isSpicy?: boolean;
  isVegetarian?: boolean;
  calories?: number;
  prepTime?: string;
}

export interface Restaurant {
  id: string;
  name: string;
  image: string;
  coverImage: string;
  cuisine: string[];
  rating: number;
  reviewCount: number;
  deliveryTime: string;
  deliveryFee: number;
  minOrder: number;
  distance: string;
  address: string;
  isOpen: boolean;
  isFeatured?: boolean;
  dashPassFree?: boolean;
  promo?: string;
  menu: MenuItem[];
}

export const RESTAURANTS: Restaurant[] = [
  {
    id: 'thai-palace',
    name: 'Thai Palace',
    image: '🍜',
    coverImage: 'https://images.unsplash.com/photo-1559314809-0d155014e29e?w=800',
    cuisine: ['Thai', 'Asian', 'Noodles'],
    rating: 4.8,
    reviewCount: 2847,
    deliveryTime: '25-35 min',
    deliveryFee: 0,
    minOrder: 15,
    distance: '1.2 mi',
    address: '123 Main St',
    isOpen: true,
    isFeatured: true,
    dashPassFree: true,
    promo: '$5 off orders $25+',
    menu: [
      {
        id: 'pad-thai',
        name: 'Pad Thai',
        description: 'Rice noodles stir-fried with eggs, tofu, bean sprouts, and peanuts in sweet tamarind sauce',
        price: 14.99,
        image: '🍜',
        category: 'Noodles',
        isPopular: true,
        calories: 680,
        prepTime: '15-20 min',
      },
      {
        id: 'pad-thai-spicy',
        name: 'Pad Thai Extra Spicy 🌶️🌶️',
        description: 'Classic Pad Thai with extra chili and jalapeños. Not for the faint of heart!',
        price: 15.99,
        image: '🍜🔥',
        category: 'Noodles',
        isPopular: true,
        isSpicy: true,
        calories: 690,
        prepTime: '15-20 min',
      },
      {
        id: 'green-curry',
        name: 'Green Curry',
        description: 'Creamy coconut curry with bamboo shoots, Thai basil, and your choice of protein',
        price: 16.99,
        image: '🍛',
        category: 'Curries',
        isSpicy: true,
        calories: 520,
        prepTime: '20-25 min',
      },
      {
        id: 'tom-yum',
        name: 'Tom Yum Soup',
        description: 'Hot and sour soup with shrimp, mushrooms, lemongrass, and lime',
        price: 12.99,
        image: '🍲',
        category: 'Soups',
        isSpicy: true,
        calories: 180,
        prepTime: '10-15 min',
      },
      {
        id: 'mango-sticky-rice',
        name: 'Mango Sticky Rice',
        description: 'Sweet sticky rice with fresh mango and coconut cream',
        price: 8.99,
        image: '🥭',
        category: 'Desserts',
        isVegetarian: true,
        calories: 420,
        prepTime: '5 min',
      },
    ],
  },
  {
    id: 'pizza-supreme',
    name: 'Pizza Supreme',
    image: '🍕',
    coverImage: 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=800',
    cuisine: ['Pizza', 'Italian', 'American'],
    rating: 4.6,
    reviewCount: 5234,
    deliveryTime: '30-40 min',
    deliveryFee: 2.99,
    minOrder: 12,
    distance: '0.8 mi',
    address: '456 Oak Ave',
    isOpen: true,
    promo: 'Buy 1 Get 1 50% off',
    menu: [
      {
        id: 'pepperoni-pizza',
        name: 'Classic Pepperoni',
        description: 'Hand-tossed crust with marinara, mozzarella, and premium pepperoni',
        price: 18.99,
        image: '🍕',
        category: 'Pizzas',
        isPopular: true,
        calories: 2200,
        prepTime: '20-25 min',
      },
      {
        id: 'margherita',
        name: 'Margherita',
        description: 'Fresh mozzarella, tomatoes, basil, and extra virgin olive oil',
        price: 16.99,
        image: '🍕',
        category: 'Pizzas',
        isVegetarian: true,
        calories: 1800,
        prepTime: '20-25 min',
      },
      {
        id: 'meat-lovers',
        name: 'Meat Lovers Supreme',
        description: 'Pepperoni, sausage, bacon, ham, and ground beef',
        price: 22.99,
        image: '🍖🍕',
        category: 'Pizzas',
        isPopular: true,
        calories: 2800,
        prepTime: '25-30 min',
      },
      {
        id: 'garlic-knots',
        name: 'Garlic Knots (6)',
        description: 'Fresh-baked knots brushed with garlic butter and herbs',
        price: 5.99,
        image: '🧄',
        category: 'Sides',
        isVegetarian: true,
        calories: 480,
        prepTime: '10 min',
      },
    ],
  },
  {
    id: 'burger-barn',
    name: 'Burger Barn',
    image: '🍔',
    coverImage: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=800',
    cuisine: ['Burgers', 'American', 'Fast Food'],
    rating: 4.5,
    reviewCount: 3891,
    deliveryTime: '20-30 min',
    deliveryFee: 1.99,
    minOrder: 10,
    distance: '1.5 mi',
    address: '789 Burger Blvd',
    isOpen: true,
    isFeatured: true,
    menu: [
      {
        id: 'classic-burger',
        name: 'Classic Cheeseburger',
        description: '1/3 lb Angus beef, American cheese, lettuce, tomato, pickles, special sauce',
        price: 12.99,
        image: '🍔',
        category: 'Burgers',
        isPopular: true,
        calories: 780,
        prepTime: '12-15 min',
      },
      {
        id: 'bacon-bbq',
        name: 'Bacon BBQ Burger',
        description: 'Angus beef, crispy bacon, cheddar, onion rings, BBQ sauce',
        price: 15.99,
        image: '🥓🍔',
        category: 'Burgers',
        isPopular: true,
        calories: 980,
        prepTime: '15-18 min',
      },
      {
        id: 'veggie-burger',
        name: 'Impossible Burger',
        description: 'Plant-based patty, vegan cheese, all the fixings',
        price: 14.99,
        image: '🌱🍔',
        category: 'Burgers',
        isVegetarian: true,
        calories: 630,
        prepTime: '12-15 min',
      },
      {
        id: 'loaded-fries',
        name: 'Loaded Cheese Fries',
        description: 'Crispy fries topped with cheese sauce, bacon, and green onions',
        price: 8.99,
        image: '🍟',
        category: 'Sides',
        calories: 720,
        prepTime: '8-10 min',
      },
      {
        id: 'milkshake',
        name: 'Chocolate Milkshake',
        description: 'Hand-spun with premium ice cream and whipped cream',
        price: 6.99,
        image: '🥤',
        category: 'Drinks',
        isVegetarian: true,
        calories: 580,
        prepTime: '5 min',
      },
    ],
  },
  {
    id: 'sushi-zen',
    name: 'Sushi Zen',
    image: '🍣',
    coverImage: 'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=800',
    cuisine: ['Sushi', 'Japanese', 'Asian'],
    rating: 4.9,
    reviewCount: 1892,
    deliveryTime: '35-45 min',
    deliveryFee: 3.99,
    minOrder: 20,
    distance: '2.1 mi',
    address: '321 Zen Way',
    isOpen: true,
    dashPassFree: true,
    menu: [
      {
        id: 'salmon-roll',
        name: 'Salmon Roll (8 pcs)',
        description: 'Fresh Atlantic salmon, cucumber, avocado, sesame seeds',
        price: 12.99,
        image: '🍣',
        category: 'Rolls',
        isPopular: true,
        calories: 320,
        prepTime: '15-20 min',
      },
      {
        id: 'dragon-roll',
        name: 'Dragon Roll (8 pcs)',
        description: 'Shrimp tempura, eel, avocado, unagi sauce, tobiko',
        price: 18.99,
        image: '🐉🍣',
        category: 'Specialty Rolls',
        isPopular: true,
        calories: 480,
        prepTime: '20-25 min',
      },
      {
        id: 'sashimi-platter',
        name: 'Sashimi Deluxe',
        description: '15 pieces of premium sashimi: salmon, tuna, yellowtail',
        price: 32.99,
        image: '🐟',
        category: 'Sashimi',
        calories: 280,
        prepTime: '15-20 min',
      },
      {
        id: 'miso-soup',
        name: 'Miso Soup',
        description: 'Traditional miso soup with tofu, seaweed, and green onions',
        price: 3.99,
        image: '🍜',
        category: 'Soups',
        isVegetarian: true,
        calories: 45,
        prepTime: '5 min',
      },
    ],
  },
  {
    id: 'taco-fiesta',
    name: 'Taco Fiesta',
    image: '🌮',
    coverImage: 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=800',
    cuisine: ['Mexican', 'Tacos', 'Burritos'],
    rating: 4.7,
    reviewCount: 4123,
    deliveryTime: '20-30 min',
    deliveryFee: 0,
    minOrder: 12,
    distance: '0.9 mi',
    address: '555 Fiesta Lane',
    isOpen: true,
    dashPassFree: true,
    promo: 'Free chips & salsa',
    menu: [
      {
        id: 'street-tacos',
        name: 'Street Tacos (3)',
        description: 'Corn tortillas, carne asada, onions, cilantro, lime',
        price: 10.99,
        image: '🌮',
        category: 'Tacos',
        isPopular: true,
        calories: 480,
        prepTime: '10-15 min',
      },
      {
        id: 'burrito-bowl',
        name: 'Burrito Bowl',
        description: 'Rice, beans, your choice of protein, guac, pico, sour cream',
        price: 13.99,
        image: '🥗',
        category: 'Bowls',
        isPopular: true,
        calories: 720,
        prepTime: '12-15 min',
      },
      {
        id: 'loaded-nachos',
        name: 'Loaded Nachos',
        description: 'Chips piled high with cheese, beans, jalapeños, guac, sour cream',
        price: 14.99,
        image: '🧀',
        category: 'Appetizers',
        isSpicy: true,
        calories: 1200,
        prepTime: '15-18 min',
      },
      {
        id: 'churros',
        name: 'Churros (4)',
        description: 'Crispy cinnamon sugar churros with chocolate dipping sauce',
        price: 6.99,
        image: '🍩',
        category: 'Desserts',
        isVegetarian: true,
        calories: 380,
        prepTime: '8-10 min',
      },
    ],
  },
];

// Helper functions for AI agent
export function searchRestaurants(query: string, filters?: {
  cuisine?: string;
  maxDeliveryFee?: number;
  maxDeliveryTime?: number;
}): Restaurant[] {
  const q = query.toLowerCase();
  
  return RESTAURANTS.filter(r => {
    // Search by name or cuisine
    const matchesQuery = 
      r.name.toLowerCase().includes(q) ||
      r.cuisine.some(c => c.toLowerCase().includes(q)) ||
      r.menu.some(m => m.name.toLowerCase().includes(q));
    
    if (!matchesQuery) return false;
    
    // Apply filters
    if (filters?.cuisine && !r.cuisine.some(c => 
      c.toLowerCase().includes(filters.cuisine!.toLowerCase())
    )) return false;
    
    if (filters?.maxDeliveryFee !== undefined && 
        r.deliveryFee > filters.maxDeliveryFee) return false;
    
    return true;
  });
}

export function getRestaurantById(id: string): Restaurant | undefined {
  return RESTAURANTS.find(r => r.id === id);
}

export function getMenuItems(restaurantId: string, filters?: {
  category?: string;
  maxPrice?: number;
  isSpicy?: boolean;
  isVegetarian?: boolean;
}): MenuItem[] {
  const restaurant = getRestaurantById(restaurantId);
  if (!restaurant) return [];
  
  return restaurant.menu.filter(item => {
    if (filters?.category && item.category !== filters.category) return false;
    if (filters?.maxPrice !== undefined && item.price > filters.maxPrice) return false;
    if (filters?.isSpicy !== undefined && item.isSpicy !== filters.isSpicy) return false;
    if (filters?.isVegetarian !== undefined && item.isVegetarian !== filters.isVegetarian) return false;
    return true;
  });
}

// Cart types
export interface CartItem {
  menuItem: MenuItem;
  quantity: number;
  restaurantId: string;
  restaurantName: string;
  specialInstructions?: string;
}

export interface Cart {
  items: CartItem[];
  restaurantId: string | null;
  restaurantName: string | null;
  subtotal: number;
  deliveryFee: number;
  tax: number;
  total: number;
}

export function calculateCartTotals(items: CartItem[], deliveryFee: number): Cart {
  const subtotal = items.reduce((sum, item) => sum + (item.menuItem.price * item.quantity), 0);
  const tax = subtotal * 0.0875; // 8.75% tax
  const total = subtotal + deliveryFee + tax;
  
  return {
    items,
    restaurantId: items.length > 0 ? items[0].restaurantId : null,
    restaurantName: items.length > 0 ? items[0].restaurantName : null,
    subtotal,
    deliveryFee,
    tax,
    total,
  };
}

// Featured categories for home screen
export const FOOD_CATEGORIES = [
  { id: 'all', name: 'All', icon: '🍽️' },
  { id: 'thai', name: 'Thai', icon: '🍜' },
  { id: 'pizza', name: 'Pizza', icon: '🍕' },
  { id: 'burgers', name: 'Burgers', icon: '🍔' },
  { id: 'sushi', name: 'Sushi', icon: '🍣' },
  { id: 'mexican', name: 'Mexican', icon: '🌮' },
  { id: 'healthy', name: 'Healthy', icon: '🥗' },
  { id: 'dessert', name: 'Dessert', icon: '🍰' },
];
