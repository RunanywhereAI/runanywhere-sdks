/**
 * FoodOrderScreen - DoorDash Clone with AI Voice Ordering
 * 
 * Demonstrates tool calling with a polished food ordering UI
 */

import React, { useState, useCallback, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  TextInput,
  SafeAreaView,
  StatusBar,
  Animated,
  Dimensions,
  Alert,
  Modal,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { useFocusEffect } from '@react-navigation/native';
import {
  DoorDashColors,
  DoorDashTypography,
  DoorDashSpacing,
  DoorDashShadows,
} from '../theme/doordash';
import {
  RESTAURANTS,
  FOOD_CATEGORIES,
  searchRestaurants,
  getRestaurantById,
  calculateCartTotals,
  type Restaurant,
  type MenuItem,
  type CartItem,
} from '../data/foodData';
import { RestaurantCard } from '../components/food/RestaurantCard';
import { MenuItemCard } from '../components/food/MenuItemCard';
import { AIAgentOverlay, type AgentStep } from '../components/food/AIAgentOverlay';
import { RunAnywhere } from '@runanywhere/core';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

// Tool definitions for food ordering
const FOOD_TOOLS = [
  {
    name: 'search_restaurants',
    description: 'Search for restaurants by cuisine type, name, or food item',
    parameters: [
      { name: 'query', type: 'string' as const, description: 'Search query (e.g., "thai", "pizza", "spicy")', required: true },
      { name: 'max_delivery_fee', type: 'number' as const, description: 'Maximum delivery fee in dollars', required: false },
    ],
  },
  {
    name: 'get_menu',
    description: 'Get the menu items from a specific restaurant',
    parameters: [
      { name: 'restaurant_id', type: 'string' as const, description: 'The restaurant ID', required: true },
      { name: 'category', type: 'string' as const, description: 'Filter by category (e.g., "Noodles", "Pizzas")', required: false },
      { name: 'max_price', type: 'number' as const, description: 'Maximum price filter', required: false },
      { name: 'spicy_only', type: 'boolean' as const, description: 'Only show spicy items', required: false },
    ],
  },
  {
    name: 'add_to_cart',
    description: 'Add a menu item to the cart',
    parameters: [
      { name: 'restaurant_id', type: 'string' as const, description: 'The restaurant ID', required: true },
      { name: 'item_id', type: 'string' as const, description: 'The menu item ID', required: true },
      { name: 'quantity', type: 'number' as const, description: 'Quantity to add (default: 1)', required: false },
    ],
  },
  {
    name: 'view_cart',
    description: 'View the current cart contents and total',
    parameters: [],
  },
  {
    name: 'place_order',
    description: 'Place the order for delivery',
    parameters: [
      { name: 'delivery_instructions', type: 'string' as const, description: 'Special delivery instructions', required: false },
    ],
  },
];

export const FoodOrderScreen: React.FC = () => {
  // UI State
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedRestaurant, setSelectedRestaurant] = useState<Restaurant | null>(null);
  const [showMenu, setShowMenu] = useState(false);
  
  // Cart State
  const [cartItems, setCartItems] = useState<CartItem[]>([]);
  const [cartVisible, setCartVisible] = useState(false);
  
  // AI Agent State
  const [showAgent, setShowAgent] = useState(false);
  const [agentSteps, setAgentSteps] = useState<AgentStep[]>([]);
  const [isProcessing, setIsProcessing] = useState(false);
  const [userQuery, setUserQuery] = useState('');
  const [isModelLoaded, setIsModelLoaded] = useState(false);
  
  // Input modal state
  const [showInputModal, setShowInputModal] = useState(false);
  const [inputText, setInputText] = useState('');
  
  // Animations
  const fabScale = React.useRef(new Animated.Value(1)).current;
  
  // Check if LLM model is loaded AND register tools when screen is focused
  useFocusEffect(
    useCallback(() => {
      console.log('[FoodOrder] Screen focused - checking model and registering tools');
      checkModelStatus();
      registerFoodTools(); // Re-register tools every time screen is focused
    }, [])
  );
  
  const checkModelStatus = async () => {
    try {
      const loaded = await RunAnywhere.isModelLoaded();
      setIsModelLoaded(loaded);
      console.log('[FoodOrder] Model loaded:', loaded);
    } catch (error) {
      console.log('[FoodOrder] Error checking model status:', error);
      setIsModelLoaded(false);
    }
  };
  
  const registerFoodTools = () => {
    console.log('[FoodOrder] 🔧 Registering food ordering tools...');
    
    // Search restaurants tool
    RunAnywhere.registerTool(
      {
        name: 'search_restaurants',
        description: 'Search for restaurants by cuisine type, name, or food item',
        parameters: FOOD_TOOLS[0].parameters,
      },
      async (args) => {
        const results = searchRestaurants(
          args.query as string,
          { maxDeliveryFee: args.max_delivery_fee as number }
        );
        return {
          found: results.length,
          restaurants: results.map(r => ({
            id: r.id,
            name: r.name,
            cuisine: r.cuisine.join(', '),
            rating: r.rating,
            deliveryTime: r.deliveryTime,
            deliveryFee: r.deliveryFee,
          })),
        };
      }
    );
    
    // Get menu tool
    RunAnywhere.registerTool(
      {
        name: 'get_menu',
        description: 'Get the menu items from a specific restaurant',
        parameters: FOOD_TOOLS[1].parameters,
      },
      async (args) => {
        const restaurant = getRestaurantById(args.restaurant_id as string);
        if (!restaurant) {
          return { error: 'Restaurant not found' };
        }
        
        let items = restaurant.menu;
        if (args.category) {
          items = items.filter(i => i.category === args.category);
        }
        if (args.max_price) {
          items = items.filter(i => i.price <= (args.max_price as number));
        }
        if (args.spicy_only) {
          items = items.filter(i => i.isSpicy);
        }
        
        return {
          restaurant: restaurant.name,
          items: items.map(i => ({
            id: i.id,
            name: i.name,
            price: i.price,
            description: i.description.slice(0, 50) + '...',
            isSpicy: i.isSpicy,
            isPopular: i.isPopular,
          })),
        };
      }
    );
    
    // Add to cart tool
    RunAnywhere.registerTool(
      {
        name: 'add_to_cart',
        description: 'Add a menu item to the cart',
        parameters: FOOD_TOOLS[2].parameters,
      },
      async (args) => {
        const restaurant = getRestaurantById(args.restaurant_id as string);
        if (!restaurant) {
          return { error: 'Restaurant not found' };
        }
        
        const menuItem = restaurant.menu.find(i => i.id === args.item_id);
        if (!menuItem) {
          return { error: 'Menu item not found' };
        }
        
        const quantity = (args.quantity as number) || 1;
        
        setCartItems(prev => {
          const existing = prev.find(
            ci => ci.menuItem.id === menuItem.id && ci.restaurantId === restaurant.id
          );
          if (existing) {
            return prev.map(ci =>
              ci === existing ? { ...ci, quantity: ci.quantity + quantity } : ci
            );
          }
          return [...prev, {
            menuItem,
            quantity,
            restaurantId: restaurant.id,
            restaurantName: restaurant.name,
          }];
        });
        
        return {
          success: true,
          item: menuItem.name,
          quantity,
          price: menuItem.price,
          total: menuItem.price * quantity,
        };
      }
    );
    
    // View cart tool
    RunAnywhere.registerTool(
      {
        name: 'view_cart',
        description: 'View the current cart contents and total',
        parameters: [],
      },
      async () => {
        if (cartItems.length === 0) {
          return { empty: true, message: 'Cart is empty' };
        }
        
        const restaurant = cartItems[0] ? getRestaurantById(cartItems[0].restaurantId) : null;
        const cart = calculateCartTotals(cartItems, restaurant?.deliveryFee || 0);
        
        return {
          restaurant: cart.restaurantName,
          items: cart.items.map(i => ({
            name: i.menuItem.name,
            quantity: i.quantity,
            price: i.menuItem.price * i.quantity,
          })),
          subtotal: cart.subtotal,
          deliveryFee: cart.deliveryFee,
          tax: cart.tax,
          total: cart.total,
        };
      }
    );
    
    // Place order tool
    RunAnywhere.registerTool(
      {
        name: 'place_order',
        description: 'Place the order for delivery',
        parameters: FOOD_TOOLS[4].parameters,
      },
      async (args) => {
        if (cartItems.length === 0) {
          return { error: 'Cart is empty' };
        }
        
        const restaurant = cartItems[0] ? getRestaurantById(cartItems[0].restaurantId) : null;
        const cart = calculateCartTotals(cartItems, restaurant?.deliveryFee || 0);
        
        return {
          success: true,
          orderId: `ORD-${Date.now()}`,
          restaurant: cart.restaurantName,
          total: cart.total,
          estimatedDelivery: restaurant?.deliveryTime || '30-40 min',
          deliveryInstructions: args.delivery_instructions || 'None',
        };
      }
    );
    
    console.log('[FoodOrder] ✅ All 5 food tools registered: search_restaurants, get_menu, add_to_cart, view_cart, place_order');
  };
  
  // Handle AI voice input
  const handleVoiceInput = async (query: string) => {
    if (!query.trim()) return;
    
    console.log('[FoodOrder] 🚀 Starting AI order with query:', query);
    
    setUserQuery(query);
    setShowAgent(true);
    setAgentSteps([]);
    setIsProcessing(true);
    
    // Add initial thinking step
    addAgentStep('thinking', 'Understanding your request...', 'Analyzing what you want to order');
    
    try {
      console.log('[FoodOrder] 📤 Calling RunAnywhere.generateWithTools...');
      
      // Use generateWithTools to process the request
      const result = await RunAnywhere.generateWithTools(query, {
        maxToolCalls: 5,
        systemPrompt: `You are a helpful food ordering assistant for a DoorDash-like app. 
Help the user find restaurants and order food.
When the user asks for food, use the search_restaurants tool first, then get_menu, then add_to_cart.
Be helpful and suggest good options based on what they want.
After adding items to cart, use view_cart to show the summary.`,
      });
      
      console.log('[FoodOrder] 📥 Got result:', JSON.stringify(result, null, 2));
      
      // Process the result and update steps
      if (result.toolCalls && result.toolCalls.length > 0) {
        console.log('[FoodOrder] 🔧 Processing', result.toolCalls.length, 'tool calls');
        for (const toolCall of result.toolCalls) {
          console.log('[FoodOrder] Tool call:', toolCall.toolName);
          await processToolCall(toolCall);
        }
      } else {
        console.log('[FoodOrder] ⚠️ No tool calls in result');
      }
      
      // Add final response
      if (result.finalResponse) {
        console.log('[FoodOrder] ✅ Final response:', result.finalResponse.substring(0, 100) + '...');
        addAgentStep('success', 'Here\'s what I found!', result.finalResponse, true);
      } else {
        console.log('[FoodOrder] ⚠️ No final response');
        addAgentStep('success', 'Done!', 'Order processing complete', true);
      }
      
    } catch (error) {
      console.error('[FoodOrder] ❌ AI processing error:', error);
      addAgentStep('error', 'Something went wrong', String(error), true);
    } finally {
      setIsProcessing(false);
      console.log('[FoodOrder] 🏁 Processing complete');
    }
  };
  
  const processToolCall = async (toolCall: { toolName: string; result?: unknown; success?: boolean; error?: string }) => {
    console.log('[FoodOrder] Processing tool call:', toolCall.toolName, 'success:', toolCall.success);
    
    // Handle failed tool calls
    if (toolCall.success === false || toolCall.error) {
      console.log('[FoodOrder] Tool call failed:', toolCall.error);
      addAgentStep(
        'error',
        `Tool ${toolCall.toolName} failed`,
        toolCall.error || 'Unknown error',
        true
      );
      return;
    }
    
    const result = toolCall.result as Record<string, unknown> | undefined;
    
    // Handle case where result is undefined
    if (!result) {
      console.log('[FoodOrder] No result for tool call:', toolCall.toolName);
      return;
    }
    
    switch (toolCall.toolName) {
      case 'search_restaurants':
        addAgentStep(
          'searching',
          'Searching restaurants...',
          `Found ${result.found || 0} restaurants matching your criteria`,
          true
        );
        break;
      case 'get_menu':
        addAgentStep(
          'found',
          `Checking menu at ${result.restaurant || 'restaurant'}`,
          `Found ${(result.items as unknown[])?.length || 0} items`,
          true
        );
        break;
      case 'add_to_cart':
        if (result.success) {
          addAgentStep(
            'adding',
            'Adding to cart',
            `Added ${result.quantity}x ${result.item} - $${(result.total as number)?.toFixed(2)}`,
            true
          );
        }
        break;
      case 'view_cart':
        if (!result.empty) {
          addAgentStep(
            'cart',
            'Cart ready!',
            `${(result.items as unknown[])?.length} items - Total: $${(result.total as number)?.toFixed(2)}`,
            true
          );
        }
        break;
      case 'place_order':
        if (result.success) {
          addAgentStep(
            'success',
            'Order placed! 🎉',
            `Order #${result.orderId} - Arriving in ${result.estimatedDelivery}`,
            true
          );
        }
        break;
    }
  };
  
  const addAgentStep = (
    type: AgentStep['type'],
    title: string,
    content: string,
    isComplete: boolean = false
  ) => {
    const step: AgentStep = {
      id: `step-${Date.now()}-${Math.random()}`,
      type,
      title,
      content,
      timestamp: new Date(),
      isComplete,
    };
    setAgentSteps(prev => [...prev, step]);
    
    // Mark previous steps as complete
    if (isComplete) {
      setTimeout(() => {
        setAgentSteps(prev =>
          prev.map(s => ({ ...s, isComplete: true }))
        );
      }, 500);
    }
  };
  
  // Show input modal for AI ordering
  const runDemoOrder = () => {
    if (!isModelLoaded) {
      Alert.alert(
        'Model Required',
        'Please load an LLM model first (3B+ recommended for tool calling).\n\nGo to Chat tab → Select a model → Download if needed.',
        [{ text: 'OK' }]
      );
      return;
    }
    
    // Show input modal
    setInputText('');
    setShowInputModal(true);
  };
  
  // Handle submit from input modal
  const handleSubmitQuery = () => {
    const query = inputText.trim();
    if (!query) {
      Alert.alert('Enter a query', 'Please type what you want to order');
      return;
    }
    setShowInputModal(false);
    handleVoiceInput(query);
  };
  
  // Quick demo presets
  const DEMO_QUERIES = [
    "Order me spicy Thai food under $20",
    "I want a pepperoni pizza",
    "Get me a burger with fries",
    "Order sushi - something with salmon",
    "I want tacos and churros",
  ];
  
  // Handle restaurant selection
  const handleRestaurantPress = (restaurant: Restaurant) => {
    setSelectedRestaurant(restaurant);
    setShowMenu(true);
  };
  
  // Handle add to cart
  const handleAddToCart = (item: MenuItem) => {
    if (!selectedRestaurant) return;
    
    setCartItems(prev => {
      const existing = prev.find(
        ci => ci.menuItem.id === item.id && ci.restaurantId === selectedRestaurant.id
      );
      if (existing) {
        return prev.map(ci =>
          ci === existing ? { ...ci, quantity: ci.quantity + 1 } : ci
        );
      }
      return [...prev, {
        menuItem: item,
        quantity: 1,
        restaurantId: selectedRestaurant.id,
        restaurantName: selectedRestaurant.name,
      }];
    });
  };
  
  // Calculate cart total
  const getCartTotal = () => {
    if (cartItems.length === 0) return 0;
    const restaurant = getRestaurantById(cartItems[0].restaurantId);
    const cart = calculateCartTotals(cartItems, restaurant?.deliveryFee || 0);
    return cart.total;
  };
  
  // Filter restaurants
  const filteredRestaurants = RESTAURANTS.filter(r => {
    if (selectedCategory !== 'all') {
      const category = FOOD_CATEGORIES.find(c => c.id === selectedCategory);
      if (category && !r.cuisine.some(c => c.toLowerCase().includes(category.name.toLowerCase()))) {
        return false;
      }
    }
    if (searchQuery) {
      const q = searchQuery.toLowerCase();
      return r.name.toLowerCase().includes(q) ||
        r.cuisine.some(c => c.toLowerCase().includes(q));
    }
    return true;
  });
  
  // Animate FAB
  const animateFab = () => {
    Animated.sequence([
      Animated.timing(fabScale, { toValue: 0.9, duration: 100, useNativeDriver: true }),
      Animated.spring(fabScale, { toValue: 1, useNativeDriver: true }),
    ]).start();
  };
  
  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="dark-content" backgroundColor={DoorDashColors.background} />
      
      {/* Header */}
      <View style={styles.header}>
        <View style={styles.locationRow}>
          <Icon name="location" size={20} color={DoorDashColors.primary} />
          <View style={styles.locationText}>
            <Text style={styles.deliverTo}>Deliver to</Text>
            <Text style={styles.address}>123 Main Street ▾</Text>
          </View>
        </View>
        <TouchableOpacity style={styles.profileButton}>
          <Icon name="person-circle-outline" size={32} color={DoorDashColors.textPrimary} />
        </TouchableOpacity>
      </View>
      
      {/* Search Bar */}
      <View style={styles.searchContainer}>
        <Icon name="search" size={20} color={DoorDashColors.textTertiary} />
        <TextInput
          style={styles.searchInput}
          placeholder="Search restaurants, food..."
          placeholderTextColor={DoorDashColors.textTertiary}
          value={searchQuery}
          onChangeText={setSearchQuery}
        />
        {searchQuery.length > 0 && (
          <TouchableOpacity onPress={() => setSearchQuery('')}>
            <Icon name="close-circle" size={20} color={DoorDashColors.textTertiary} />
          </TouchableOpacity>
        )}
      </View>
      
      {/* Categories */}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        style={styles.categoriesContainer}
        contentContainerStyle={styles.categoriesContent}
      >
        {FOOD_CATEGORIES.map(category => (
          <TouchableOpacity
            key={category.id}
            style={[
              styles.categoryPill,
              selectedCategory === category.id && styles.categoryPillActive,
            ]}
            onPress={() => setSelectedCategory(category.id)}
          >
            <Text style={styles.categoryEmoji}>{category.icon}</Text>
            <Text
              style={[
                styles.categoryText,
                selectedCategory === category.id && styles.categoryTextActive,
              ]}
            >
              {category.name}
            </Text>
          </TouchableOpacity>
        ))}
      </ScrollView>
      
      {/* Main Content */}
      {showMenu && selectedRestaurant ? (
        // Restaurant Menu View
        <View style={styles.menuContainer}>
          <View style={styles.menuHeader}>
            <TouchableOpacity
              style={styles.backButton}
              onPress={() => {
                setShowMenu(false);
                setSelectedRestaurant(null);
              }}
            >
              <Icon name="arrow-back" size={24} color={DoorDashColors.textPrimary} />
            </TouchableOpacity>
            <View style={styles.menuHeaderText}>
              <Text style={styles.menuTitle}>{selectedRestaurant.name}</Text>
              <Text style={styles.menuSubtitle}>
                {selectedRestaurant.deliveryTime} • {selectedRestaurant.distance}
              </Text>
            </View>
          </View>
          
          <ScrollView style={styles.menuList} showsVerticalScrollIndicator={false}>
            {selectedRestaurant.menu.map(item => (
              <MenuItemCard
                key={item.id}
                item={item}
                onPress={() => {}}
                onAddToCart={handleAddToCart}
              />
            ))}
            <View style={{ height: 100 }} />
          </ScrollView>
        </View>
      ) : (
        // Restaurant List View
        <ScrollView
          style={styles.restaurantList}
          showsVerticalScrollIndicator={false}
          contentContainerStyle={styles.restaurantListContent}
        >
          {/* Featured Section */}
          <Text style={styles.sectionTitle}>Featured on DoorDash</Text>
          
          {filteredRestaurants.map(restaurant => (
            <RestaurantCard
              key={restaurant.id}
              restaurant={restaurant}
              onPress={handleRestaurantPress}
            />
          ))}
          
          <View style={{ height: 100 }} />
        </ScrollView>
      )}
      
      {/* Cart Badge */}
      {cartItems.length > 0 && (
        <TouchableOpacity
          style={styles.cartBadge}
          onPress={() => setCartVisible(true)}
        >
          <View style={styles.cartBadgeContent}>
            <View style={styles.cartCount}>
              <Text style={styles.cartCountText}>{cartItems.length}</Text>
            </View>
            <Text style={styles.cartText}>View Cart</Text>
            <Text style={styles.cartTotal}>${getCartTotal().toFixed(2)}</Text>
          </View>
        </TouchableOpacity>
      )}
      
      {/* AI Voice FAB */}
      <Animated.View style={[styles.fabContainer, { transform: [{ scale: fabScale }] }]}>
        <TouchableOpacity
          style={styles.fab}
          onPress={() => {
            animateFab();
            runDemoOrder();
          }}
          activeOpacity={0.9}
        >
          <View style={styles.fabInner}>
            <Icon name="mic" size={28} color={DoorDashColors.textWhite} />
            <Text style={styles.fabLabel}>AI Order</Text>
          </View>
          <View style={styles.fabBadge}>
            <Text style={styles.fabBadgeText}>✨ Try it!</Text>
          </View>
        </TouchableOpacity>
      </Animated.View>
      
      {/* AI Agent Overlay */}
      <AIAgentOverlay
        visible={showAgent}
        onClose={() => setShowAgent(false)}
        steps={agentSteps}
        isProcessing={isProcessing}
        userQuery={userQuery}
        cartItems={cartItems}
        cartTotal={getCartTotal()}
        onConfirmOrder={() => {
          Alert.alert('Order Placed! 🎉', 'Your food is on the way!');
          setShowAgent(false);
          setCartItems([]);
        }}
        onCancelOrder={() => {
          setShowAgent(false);
        }}
      />
      
      {/* Input Modal */}
      <Modal
        visible={showInputModal}
        transparent
        animationType="slide"
        onRequestClose={() => setShowInputModal(false)}
      >
        <KeyboardAvoidingView 
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
          style={styles.inputModalOverlay}
        >
          <View style={styles.inputModalContainer}>
            {/* Header */}
            <View style={styles.inputModalHeader}>
              <Text style={styles.inputModalTitle}>🤖 AI Food Agent</Text>
              <TouchableOpacity onPress={() => setShowInputModal(false)}>
                <Icon name="close" size={24} color={DoorDashColors.textSecondary} />
              </TouchableOpacity>
            </View>
            
            {/* Instructions */}
            <Text style={styles.inputModalSubtitle}>
              Tell me what you want to eat!
            </Text>
            
            {/* Text Input */}
            <TextInput
              style={styles.inputModalInput}
              placeholder="e.g., Order me spicy Thai food under $20"
              placeholderTextColor={DoorDashColors.textTertiary}
              value={inputText}
              onChangeText={setInputText}
              multiline
              autoFocus
            />
            
            {/* Quick Presets */}
            <Text style={styles.quickPresetsLabel}>Quick examples:</Text>
            <ScrollView 
              horizontal 
              showsHorizontalScrollIndicator={false}
              style={styles.quickPresetsScroll}
            >
              {DEMO_QUERIES.map((query, index) => (
                <TouchableOpacity
                  key={index}
                  style={styles.quickPresetPill}
                  onPress={() => setInputText(query)}
                >
                  <Text style={styles.quickPresetText}>{query}</Text>
                </TouchableOpacity>
              ))}
            </ScrollView>
            
            {/* Submit Button */}
            <TouchableOpacity 
              style={styles.inputModalSubmit}
              onPress={handleSubmitQuery}
            >
              <Icon name="send" size={20} color={DoorDashColors.textWhite} />
              <Text style={styles.inputModalSubmitText}>Send to AI</Text>
            </TouchableOpacity>
            
            {/* Privacy Badge */}
            <View style={styles.inputModalPrivacy}>
              <Icon name="shield-checkmark" size={14} color={DoorDashColors.success} />
              <Text style={styles.inputModalPrivacyText}>
                100% On-Device • Your data stays private
              </Text>
            </View>
          </View>
        </KeyboardAvoidingView>
      </Modal>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: DoorDashColors.background,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: DoorDashSpacing.lg,
    paddingVertical: DoorDashSpacing.md,
  },
  locationRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: DoorDashSpacing.sm,
  },
  locationText: {
    marginLeft: DoorDashSpacing.xs,
  },
  deliverTo: {
    ...DoorDashTypography.caption,
    color: DoorDashColors.textSecondary,
  },
  address: {
    ...DoorDashTypography.bodyMedium,
    fontWeight: '600',
    color: DoorDashColors.textPrimary,
  },
  profileButton: {
    padding: DoorDashSpacing.xs,
  },
  searchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: DoorDashColors.backgroundSecondary,
    marginHorizontal: DoorDashSpacing.lg,
    paddingHorizontal: DoorDashSpacing.md,
    paddingVertical: DoorDashSpacing.sm,
    borderRadius: DoorDashSpacing.radiusFull,
    gap: DoorDashSpacing.sm,
  },
  searchInput: {
    flex: 1,
    ...DoorDashTypography.bodyMedium,
    color: DoorDashColors.textPrimary,
    paddingVertical: DoorDashSpacing.xs,
  },
  categoriesContainer: {
    marginTop: DoorDashSpacing.lg,
    maxHeight: 50,
  },
  categoriesContent: {
    paddingHorizontal: DoorDashSpacing.lg,
    gap: DoorDashSpacing.sm,
  },
  categoryPill: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: DoorDashSpacing.md,
    paddingVertical: DoorDashSpacing.sm,
    backgroundColor: DoorDashColors.backgroundSecondary,
    borderRadius: DoorDashSpacing.radiusFull,
    marginRight: DoorDashSpacing.sm,
    gap: DoorDashSpacing.xs,
  },
  categoryPillActive: {
    backgroundColor: DoorDashColors.textPrimary,
  },
  categoryEmoji: {
    fontSize: 16,
  },
  categoryText: {
    ...DoorDashTypography.bodySmall,
    fontWeight: '500',
    color: DoorDashColors.textPrimary,
  },
  categoryTextActive: {
    color: DoorDashColors.textWhite,
  },
  sectionTitle: {
    ...DoorDashTypography.headerMedium,
    color: DoorDashColors.textPrimary,
    marginBottom: DoorDashSpacing.lg,
  },
  restaurantList: {
    flex: 1,
  },
  restaurantListContent: {
    padding: DoorDashSpacing.lg,
  },
  menuContainer: {
    flex: 1,
  },
  menuHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: DoorDashSpacing.lg,
    borderBottomWidth: 1,
    borderBottomColor: DoorDashColors.divider,
  },
  backButton: {
    padding: DoorDashSpacing.sm,
    marginRight: DoorDashSpacing.sm,
  },
  menuHeaderText: {
    flex: 1,
  },
  menuTitle: {
    ...DoorDashTypography.headerSmall,
    color: DoorDashColors.textPrimary,
  },
  menuSubtitle: {
    ...DoorDashTypography.bodySmall,
    color: DoorDashColors.textSecondary,
  },
  menuList: {
    flex: 1,
    padding: DoorDashSpacing.lg,
  },
  cartBadge: {
    position: 'absolute',
    bottom: 100,
    left: DoorDashSpacing.lg,
    right: DoorDashSpacing.lg,
    backgroundColor: DoorDashColors.primary,
    borderRadius: DoorDashSpacing.radiusFull,
    ...DoorDashShadows.floating,
  },
  cartBadgeContent: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: DoorDashSpacing.md,
    paddingHorizontal: DoorDashSpacing.lg,
  },
  cartCount: {
    backgroundColor: DoorDashColors.background,
    width: 24,
    height: 24,
    borderRadius: 12,
    justifyContent: 'center',
    alignItems: 'center',
  },
  cartCountText: {
    ...DoorDashTypography.bodySmall,
    fontWeight: '700',
    color: DoorDashColors.primary,
  },
  cartText: {
    ...DoorDashTypography.button,
    color: DoorDashColors.textWhite,
    flex: 1,
    marginLeft: DoorDashSpacing.md,
  },
  cartTotal: {
    ...DoorDashTypography.button,
    color: DoorDashColors.textWhite,
  },
  fabContainer: {
    position: 'absolute',
    bottom: 30,
    right: DoorDashSpacing.lg,
  },
  fab: {
    backgroundColor: DoorDashColors.primary,
    borderRadius: 30,
    paddingVertical: DoorDashSpacing.md,
    paddingHorizontal: DoorDashSpacing.xl,
    ...DoorDashShadows.floating,
    position: 'relative',
  },
  fabInner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: DoorDashSpacing.sm,
  },
  fabLabel: {
    ...DoorDashTypography.button,
    color: DoorDashColors.textWhite,
  },
  fabBadge: {
    position: 'absolute',
    top: -8,
    right: -8,
    backgroundColor: DoorDashColors.warning,
    paddingHorizontal: DoorDashSpacing.sm,
    paddingVertical: 2,
    borderRadius: DoorDashSpacing.radiusFull,
  },
  fabBadgeText: {
    ...DoorDashTypography.caption,
    fontWeight: '600',
    color: DoorDashColors.textWhite,
  },
  // Input Modal Styles
  inputModalOverlay: {
    flex: 1,
    backgroundColor: DoorDashColors.overlay,
    justifyContent: 'flex-end',
  },
  inputModalContainer: {
    backgroundColor: DoorDashColors.background,
    borderTopLeftRadius: DoorDashSpacing.radiusXLarge,
    borderTopRightRadius: DoorDashSpacing.radiusXLarge,
    padding: DoorDashSpacing.xl,
    paddingBottom: DoorDashSpacing.xxxl,
  },
  inputModalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: DoorDashSpacing.sm,
  },
  inputModalTitle: {
    ...DoorDashTypography.headerMedium,
    color: DoorDashColors.textPrimary,
  },
  inputModalSubtitle: {
    ...DoorDashTypography.bodyMedium,
    color: DoorDashColors.textSecondary,
    marginBottom: DoorDashSpacing.lg,
  },
  inputModalInput: {
    backgroundColor: DoorDashColors.backgroundSecondary,
    borderRadius: DoorDashSpacing.radiusMedium,
    padding: DoorDashSpacing.md,
    minHeight: 80,
    ...DoorDashTypography.bodyLarge,
    color: DoorDashColors.textPrimary,
    textAlignVertical: 'top',
    marginBottom: DoorDashSpacing.lg,
  },
  quickPresetsLabel: {
    ...DoorDashTypography.bodySmall,
    color: DoorDashColors.textSecondary,
    marginBottom: DoorDashSpacing.sm,
  },
  quickPresetsScroll: {
    marginBottom: DoorDashSpacing.lg,
  },
  quickPresetPill: {
    backgroundColor: DoorDashColors.backgroundSecondary,
    paddingHorizontal: DoorDashSpacing.md,
    paddingVertical: DoorDashSpacing.sm,
    borderRadius: DoorDashSpacing.radiusFull,
    marginRight: DoorDashSpacing.sm,
  },
  quickPresetText: {
    ...DoorDashTypography.bodySmall,
    color: DoorDashColors.textPrimary,
  },
  inputModalSubmit: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: DoorDashSpacing.sm,
    backgroundColor: DoorDashColors.primary,
    paddingVertical: DoorDashSpacing.md,
    borderRadius: DoorDashSpacing.radiusFull,
    ...DoorDashShadows.button,
  },
  inputModalSubmitText: {
    ...DoorDashTypography.button,
    color: DoorDashColors.textWhite,
  },
  inputModalPrivacy: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: DoorDashSpacing.xs,
    marginTop: DoorDashSpacing.lg,
  },
  inputModalPrivacyText: {
    ...DoorDashTypography.caption,
    color: DoorDashColors.success,
  },
});

export default FoodOrderScreen;
