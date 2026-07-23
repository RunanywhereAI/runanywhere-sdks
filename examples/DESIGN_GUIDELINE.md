# RunAnywhere Design Guideline

Canonical visual identity for the five RunAnywhere example apps in this folder
(iOS, Android, Flutter, React Native, Web). One brand, one palette, one type system.

> **Source of truth.** This document is the canonical brand reference for the
> example apps. Each app hand-maintains a small set of theme constants that
> **mirror the values here** (Swift/Kotlin/Dart/RN can't share a single stylesheet),
> and each theme file carries a header comment pointing back to this doc. When the
> brand values change, update this document and the per-app theme files together.

---

## 1. Brand color — the primary is the logo

The RunAnywhere mark is a two-path gradient. Its **start stop is the brand primary**:

| Role | Hex | HSL | Notes |
|------|-----|-----|-------|
| **Primary (brand orange)** | `#FF6900` | `hsl(24.7, 100%, 50%)` | The logo's gradient start. This is THE brand color. |
| Gradient end | `#FB2C36` | `hsl(357.3, 96%, 58%)` | The logo's gradient end (red). `#FB2D36` is the 1/255 HSL-rounded spelling used by the token CSS; `#FB2C36` is the raw-SVG spelling — either is acceptable. |
| Brand gradient | `linear-gradient(135°, #FF6900 → #FB2C36)` | — | Used for the mark, hero CTAs, brand moments. |

**Do not use the legacy `#FF5500` orange-red, `#FF9500` (Apple orange), or any blue as
the accent.** Every app previously drifted to one of those; the logos are already
`#FF6900` — the theme must match the logo.

Supporting brand neutrals:

| Role | Hex | HSL |
|------|-----|-----|
| Ink (foreground text) | `#10182B` | `hsl(220, 40%, 11%)` |
| Paper (light background) | `#FBFAF8` | `hsl(40, 20%, 98%)` |
| Surface inverse (dark background) | `#0C0E17` | `hsl(229, 31%, 7%)` |
| Surface inverse elevated | `#1B2231` | `hsl(224, 30%, 15%)` |

---

## 2. Full semantic palette (light / dark)

HSL triplets are authoritative; hex is the native mirror. Where one value is given, the
token is theme-invariant.

| Token | Light | Dark |
|-------|-------|------|
| `background` | `#FBFAF8` (`40 20% 98%`) | `#0C0E17` (`229 31% 7%`) |
| `foreground` | `#10182B` (`220 40% 11%`) | `#F7F4EE` (`40 25% 96%`) |
| `card` / surface | `#FBFAF8` | `#131620` (`228 26% 10%`) |
| `card-foreground` | `#10182B` | `#F7F4EE` |
| `muted` / secondary | `#F3F4F6` (`220 14% 96%`) | `#1C2230` (`228 22% 13%`) |
| `muted-foreground` | `#6B7280` (`220 9% 46%`) | `#9AA1B3` (`227 14% 66%`) |
| `border` / input | `#E5E7EB` (`220 13% 91%`) | `#242A38` (`228 18% 17%`) |
| **`primary`** | `#FF6900` | `#FF6900` |
| `primary-foreground` | `#FFFFFF` | `#FFFFFF` — but see §5 contrast |
| `ring` / focus | `#FF6900` | `#FF6900` |
| `destructive` / `error` | `#EF4444` (`0 84% 60%`) | `#DC2626` (`0 72% 51%`) |
| `success` | `#269B57` (`145 60% 38%`) | `#45C97F` (`145 50% 52%`) |
| `warning` | `#F59E0B` (`38 92% 50%`) | `#F7AE2A` (`38 92% 55%`) |
| `info` | `#3B82F6` (`217 91% 60%`) | `#60A5FA` (`213 94% 68%`) |
| `code-surface` (theme-invariant) | `#021A28` (`207 95% 8%`) | — |
| `code-foreground` | `#D3DCE8` (`217 34% 88%`) | — |

`radius`: **8px** (`0.5rem`). Focus ring: 2px `#FF6900` (offset by the background color).

---

## 3. Typography

| Role | Family | Fallback |
|------|--------|----------|
| Display / headings-as-brand-moment | **Instrument Serif** | Georgia, serif |
| Body / UI | **IBM Plex Sans** | system-ui, sans-serif |
| Code / metrics / mono | **JetBrains Mono** | ui-monospace, monospace |

Fonts are a **target**, not a hard requirement for every example app today. Apps that
already ship system fonts (iOS uses SF; several apps use Figtree) may keep them for now
and adopt the brand fonts as a follow-up — the **color palette is the priority**. When
adopting brand fonts, bundle the woff2/ttf from Google Fonts (all three are
OFL-licensed) and reserve Instrument Serif for display only.

---

## 4. Per-platform mapping

Every app defines these in its ONE theme file (cite this doc in that file's header).

### SwiftUI (iOS)
`Core/DesignSystem/AppColors.swift` + `Assets.xcassets/AccentColor.colorset`.
```swift
static let primary = Color(hex: 0xFF6900)   // brand orange — was 0xFF5500
static let gradientEnd = Color(hex: 0xFB2C36)
static let backgroundDark = Color(hex: 0x0C0E17)   // brand ink surface
static let backgroundLight = Color(hex: 0xFBFAF8)  // paper
// AccentColor.colorset components → R 0xFF, G 0x69, B 0x00
```
The brand gradient: `LinearGradient(colors: [primary, gradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing)`.

### Jetpack Compose (Android)
`ui/theme/Color.kt` + `Theme.kt` (Material 3 `lightColorScheme`/`darkColorScheme`).
```kotlin
val BrandOrange = Color(0xFFFF6900)   // was 0xFFFF5500
val BrandGradientEnd = Color(0xFFFB2C36)
// map BrandOrange → primary in both schemes; regenerate the Primary tonal ramp around this hue
```
`success`/`warning`/`info` have no Material 3 role — expose them via an extended-colors `CompositionLocal`. Brand gradient via `Brush.linearGradient(listOf(BrandOrange, BrandGradientEnd))`.

### Flutter
`lib/core/design_system/app_colors.dart` + the two `ThemeData` blocks in the app root.
```dart
static const Color primary = Color(0xFFFF6900);     // was Colors.blue
static const Color gradientEnd = Color(0xFFFB2C36);
// ColorScheme.fromSeed(seedColor: primary).copyWith(primary: primary)  — pin exact primary
```
Add success/warning/info via a `ThemeExtension<RaColors>`. Brand gradient via `LinearGradient(colors:[primary, gradientEnd], begin: Alignment.topLeft, end: Alignment.bottomRight)`.

### React Native
`src/theme/system/colors.ts` (the Material-3 scheme — the canonical one; the legacy `src/theme/colors.ts` blue system is being retired).
```ts
export const brand = { primary: '#FF6900', gradientEnd: '#FB2C36' } // primary was #E65500 / legacy #007AFF
// anchor lightScheme.primary and darkScheme.primary to '#FF6900'
```
Brand gradient via `expo-linear-gradient` `colors={['#FF6900', '#FB2C36']}`. Keep token keys 1:1 with the CSS var names so web + native share one vocabulary.

### Web / CSS
`src/styles/design-system.css` — CSS custom properties.
```css
--color-primary: #FF6900;   /* was #FF5500 */
--color-primary-strong: #E65E00;
--gradient-brand: linear-gradient(135deg, #FF6900 0%, #FB2C36 100%);
```

---

## 5. Contrast — the one honest caveat

**White text on solid `#FF6900` is ≈2.9:1 and FAILS WCAG AA.** Ink (`#10182B`) on
`#FF6900` is ≈6.1:1 and passes comfortably. The brand accepts white-on-orange for the
gradient CTA and large/bold brand moments (a documented, deliberate deviation), but:

- **Reserve solid-orange fills with white text for large or bold text only.**
- For small text on orange, or any body copy, use **ink text on orange**, or use orange
  as a border / accent / icon color instead of a text-bearing fill.
- **Never** put orange fill behind white body copy.
- Do **not** darken `#FF6900` to "fix" contrast — the hue is the locked brand identity.

---

## 6. Rules

1. **`#FF6900` is the primary everywhere.** No `#FF5500`, `#FF9500`, `#007AFF`, or `Colors.blue` as the accent.
2. **One theme file per app**, mirroring §2/§4, with a header comment citing this doc.
3. **Both light and dark** must be defined; dark backgrounds trend toward brand ink `#0C0E17`, light toward paper `#FBFAF8` (approximate is fine; exact is better).
4. **Logos are already on-brand** (`#FF6900 → #FB2C36`) — never repaint the mark; only the UI theme was lagging.
5. Third-party brand marks (Meta, Mistral, HuggingFace, macOS traffic lights, syntax highlighting) are intentionally off-palette — leave them.
6. When in doubt, use the exact values in this document — it is the reference.
