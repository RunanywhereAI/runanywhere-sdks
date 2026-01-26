# 🍕 Real Restaurant API Setup

Make your demo go viral with **real restaurant data** near any location!

## Quick Setup (2 minutes)

### Step 1: Get FREE Foursquare API Key

1. Go to: https://foursquare.com/developers/signup
2. Create a free account (no credit card needed)
3. Create a new project
4. Copy your API key (starts with `fsq...`)

### Step 2: Add Your API Key

Open `src/services/restaurantApi.ts` and paste your key:

```typescript
// Line 15 - Replace empty string with your key
const FOURSQUARE_API_KEY = 'fsq3abc123...your-key-here';
```

### Step 3: Run the App

```bash
# Start Metro bundler
npm start

# In another terminal, run iOS
npx react-native run-ios
```

## That's it! 🎉

Now when you use the AI Food Agent:
- It searches **real restaurants** near your location
- Shows actual ratings, distances, and cuisines
- Works in any city worldwide!

## Free Tier Limits

- **10,000 API calls/month** - More than enough for demos
- No credit card required
- Reset monthly

## Location Options

The app supports 8 major US cities by default:
- San Francisco, New York, Los Angeles, Chicago
- Miami, Austin, Seattle, Boston

Tap "Deliver to" in the header to change location.

## Troubleshooting

### "Using mock data" message?
- Check your API key is set correctly
- Make sure there are no typos
- The key should start with `fsq3...`

### No restaurants found?
- Try a different search query (e.g., "pizza", "thai", "burger")
- Change to a different city location
- Some areas have less restaurant coverage

### Need help?
Check Foursquare docs: https://docs.foursquare.com/developer/reference/place-search

---

**Enjoy your viral demo!** 🚀
