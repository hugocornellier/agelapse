# AgeLapse Design System

This document defines the standard design tokens for the AgeLapse app. All UI components should reference these values to ensure visual consistency.

---

## Colors

### Backgrounds

| Token | Hex | RGB | Usage |
|-------|-----|-----|-------|
| `background` | `#0F0F0F` | `rgb(15, 15, 15)` | Standard scaffold backgrounds |
| `backgroundDark` | `#0A0A0A` | `rgb(10, 10, 10)` | Settings pages, sheets, modals |

### Surfaces

| Token | Hex | RGB | Usage |
|-------|-----|-----|-------|
| `surface` | `#1A1A1A` | `rgb(26, 26, 26)` | Cards, dialogs, bottom sheets, elevated containers |
| `surfaceElevated` | `#2A2A2A` | `rgb(42, 42, 42)` | Borders, dividers, input backgrounds, hover states |

### Semantic Colors

| Token | Hex | RGB | Usage |
|-------|-----|-----|-------|
| `danger` | `#EF4444` | `rgb(239, 68, 68)` | Delete buttons, destructive actions, errors |
| `success` | `#22C55E` | `rgb(34, 197, 94)` | Success states, confirmations, completed |
| `warning` | `#FF9500` | `rgb(255, 149, 0)` | Warnings, caution states, pending |
| `warningMuted` | `#C9A179` | `rgb(201, 161, 121)` | Soft warnings, guide highlights, caution overlays |
| `info` | `#2196F3` | `rgb(33, 150, 243)` | Information, drag/drop highlights, selection states |
| `accent` | `#4A9ECC` | `rgb(74, 158, 204)` | Primary interactive elements, links, settings buttons |

### Brand/Accent Color Ramp

For primary actions, navigation, and brand elements:

| Token | Hex | RGB | Usage |
|-------|-----|-----|-------|
| `accentLight` | `#66AACC` | `rgb(102, 170, 204)` | Active navigation, timer badges, progress indicators |
| `accent` | `#4A9ECC` | `rgb(74, 158, 204)` | Settings interactive elements, links |
| `accentDark` | `#3285AF` | `rgb(50, 133, 175)` | Primary CTA buttons, important actions |
| `accentDarker` | `#206588` | `rgb(32, 101, 136)` | In-progress states, secondary emphasis |

### Text Colors

| Token | Hex | RGB | Usage |
|-------|-----|-----|-------|
| `textPrimary` | `#FFFFFF` | `rgb(255, 255, 255)` | Main text, headings, important content |
| `textSecondary` | `#8E8E93` | `rgb(142, 142, 147)` | Descriptions, hints, supporting text |
| `textTertiary` | `#636366` | `rgb(99, 99, 102)` | Disabled text, placeholders, subtle labels |

### Utility Colors

| Token | Hex | RGB | Usage |
|-------|-----|-----|-------|
| `overlay` | `#000000` | `rgb(0, 0, 0)` | Modal scrims (use with `opacityHeavy` 0.7) |
| `disabled` | `#5A5A5A` | `rgb(90, 90, 90)` | Disabled elements, inactive states |
| `guideCorner` | `#924904` | `rgb(146, 73, 4)` | Camera grid corner guides, crop boundaries |

### SVG / Icon Colors

Icons should use these colors based on context:

| Context | Color Token |
|---------|-------------|
| Default icons | `textSecondary` (#8E8E93) |
| Active/selected icons | `accent` (#4A9ECC) |
| Destructive icons | `danger` (#EF4444) |
| Success icons | `success` (#22C55E) |
| Warning icons | `warning` (#FF9500) |
| Disabled icons | `textTertiary` (#636366) |
| Icons on colored backgrounds | `textPrimary` (#FFFFFF) |

### Illustration Palette (SVG Assets Only)

These colors are used exclusively in illustration SVGs (`person-grey.svg`, `user-avatar.svg`) and should NOT be used in UI components:

| Color | Hex | Usage |
|-------|-----|-------|
| Shirt Blue | `#3285AF` | Avatar clothing (maps to `accentDark`) |
| Shirt Blue Dark | `#206588` | Avatar clothing shadow (maps to `accentDarker`) |
| Skin | `#FFB044` | Avatar skin tone |
| Skin Light | `#FFD28C` | Avatar skin highlight |
| Hair Brown | `#5D4037` | Avatar hair |
| Eye Brown | `#6B3E1C` | Avatar eyes |

---

## Opacity Scale

Standard opacity values for overlays and transparency effects:

| Token | Value | Usage |
|-------|-------|-------|
| `opacityFaint` | `0.05` | Very subtle backgrounds, input fields |
| `opacitySubtle` | `0.08` | Subtle borders, hover backgrounds, card borders |
| `opacityLight` | `0.15` | Light tints, soft backgrounds, selection highlights |
| `opacityMild` | `0.24` | Drag handles, subtle indicators |
| `opacityMedium` | `0.3` | Medium emphasis, shadows, warning overlays |
| `opacityHalf` | `0.5` | Half-visible overlays, overlay buttons |
| `opacityHeavy` | `0.7` | Modal scrims, overlays |
| `opacityStrong` | `0.85` | Near-opaque states |
| `opacityNearFull` | `0.9` | Active highlights, strong emphasis |

---

## Typography

### Font Families

| Token | Value | Usage |
|-------|-------|-------|
| `fontDefault` | `Inter` | Primary UI font |
| `fontMono` | `JetBrainsMono` | Code, debug info, monospace content, format fields |

**Note:** Always use `JetBrainsMono` instead of generic `monospace` for consistency.

Available bundled fonts for date stamps: `Inter`, `Roboto`, `SourceSans3`, `Nunito`, `JetBrainsMono`

### Type Scale

| Token | Size | Weight | Line Height | Usage |
|-------|------|--------|-------------|-------|
| `displayLarge` | 28px | Bold (700) | 1.2 | Large titles, splash screens |
| `displayMedium` | 24px | Bold (700) | 1.2 | Page titles |
| `headlineLarge` | 20px | SemiBold (600) | 1.3 | Section headers |
| `headlineMedium` | 18px | SemiBold (600) | 1.3 | Card titles, dialog titles |
| `titleLarge` | 16px | SemiBold (600) | 1.4 | Subsection titles |
| `titleMedium` | 15px | Medium (500) | 1.4 | List item titles |
| `bodyLarge` | 16px | Regular (400) | 1.5 | Primary body text |
| `bodyMedium` | 14px | Regular (400) | 1.5 | Standard body text (most common) |
| `bodySmall` | 13px | Regular (400) | 1.5 | Secondary body text |
| `labelLarge` | 14px | SemiBold (600) | 1.4 | Button text, emphasized labels |
| `labelMedium` | 13px | Medium (500) | 1.4 | Form labels, navigation |
| `labelSmall` | 12px | Medium (500) | 1.4 | Badges, tags, captions |
| `caption` | 11px | Regular (400) | 1.4 | Fine print, timestamps |

**Note:** Minimum font size is 11px. Sizes 9px and 10px found in legacy code should be normalized to 11px (`caption`).

### Font Weights

| Token | Value | CSS |
|-------|-------|-----|
| `weightRegular` | 400 | `FontWeight.w400` |
| `weightMedium` | 500 | `FontWeight.w500` |
| `weightSemiBold` | 600 | `FontWeight.w600` |
| `weightBold` | 700 | `FontWeight.bold` |

---

## Spacing

Use a 4px base grid. Standard spacing values:

| Token | Value | Usage |
|-------|-------|-------|
| `space2` | 2px | Tight spacing, icon gaps |
| `space4` | 4px | Minimal spacing |
| `space6` | 6px | Small gaps |
| `space8` | 8px | Compact spacing |
| `space10` | 10px | Common legacy spacing (button/icon gaps) |
| `space12` | 12px | Default small spacing |
| `space14` | 14px | Common legacy spacing (card padding) |
| `space16` | 16px | Standard spacing (most common) |
| `space20` | 20px | Medium spacing |
| `space24` | 24px | Large spacing |
| `space32` | 32px | Section spacing |
| `space40` | 40px | Large section gaps |
| `space48` | 48px | Major section breaks |

**Note:** `space10` and `space14` are included for legacy compatibility. For new code, prefer values on the 4px grid (8, 12, 16).

---

## Border Radius

| Token | Value | Usage |
|-------|-------|-------|
| `radiusXSmall` | 4px | Progress bars, small badges, inline elements |
| `radiusSmall` | 8px | Small buttons, chips, tags |
| `radiusMediumSmall` | 10px | Dialog buttons, compact cards |
| `radiusMedium` | 12px | Cards, inputs, standard containers |
| `radiusMediumLarge` | 14px | Tip bars, settings cards, yellow alerts |
| `radiusLarge` | 16px | Dialogs, sheets, large cards |
| `radiusXLarge` | 20px | Bottom sheets (top corners only) |
| `radiusFull` | 9999px | Circular buttons, avatars |

**Migration note:** Normalize `6px` to `radiusXSmall` (4px) or `radiusSmall` (8px). Normalize `7px` and `11px` to nearest standard value.

---

## Border Width

| Token | Value | Usage |
|-------|-------|-------|
| `borderThin` | 0.5px | Subtle dividers, navigation borders |
| `borderDefault` | 1px | Standard borders |
| `borderThick` | 2px | Emphasized borders, focus states |

---

## Shadows

| Token | Value | Usage |
|-------|-------|-------|
| `shadowSmall` | `0 2px 4px rgba(0,0,0,0.3)` | Subtle elevation |
| `shadowMedium` | `0 4px 12px rgba(0,0,0,0.4)` | Cards, dialogs |
| `shadowLarge` | `0 8px 24px rgba(0,0,0,0.5)` | Modals, popovers |
| `shadowOverlay` | `0 4px 20px rgba(0,0,0,0.4)` | Saving indicators, floating UI |

---

## Animation Durations

| Token | Value | Usage |
|-------|-------|-------|
| `durationFast` | 100ms | Micro-interactions, hover |
| `durationNormal` | 200ms | Standard transitions |
| `durationSlow` | 300ms | Page transitions, modals |
| `durationSlowest` | 500ms | Complex animations |

---

## Component-Specific Guidelines

### Buttons

| Type | Background | Text | Border |
|------|------------|------|--------|
| Primary | `accentDark` | `textPrimary` | none |
| Secondary | `surface` | `textPrimary` | `surfaceElevated` |
| Danger | `danger` | `textPrimary` | none |
| Ghost | transparent | `textSecondary` | none |
| Disabled | `disabled` @ 0.5 | `textTertiary` | none |

### Cards

- Background: `surface`
- Border: `surfaceElevated` @ 1px
- Border radius: `radiusMedium` (12px)
- Padding: `space16`

### Dialogs

- Background: `surface`
- Border: `textPrimary` @ `opacitySubtle` (0.08), 1px
- Border radius: `radiusLarge` (16px)
- Padding: `space20`

### Bottom Sheets

- Background: `surface`
- Border radius: `radiusXLarge` (20px) top corners only
- Drag handle: 36x4px, `textPrimary` @ `opacityMild` (0.24)

### Inputs

- Background: `textPrimary` @ `opacityFaint` (0.05)
- Border: `textPrimary` @ 0.1 opacity, 1px
- Border (focused): `accent`, 1px
- Border (error): `danger`, 1px
- Border radius: `radiusMedium` (12px)
- Text: `textPrimary`
- Placeholder: `textTertiary`
- Monospace inputs: Use `fontMono` (JetBrainsMono)

### Dividers

- Color: `surfaceElevated`
- Thickness: `borderDefault` (1px)

### SnackBars

- Background: `surface`
- Text: `textPrimary`
- Border radius: `radiusSmall` (8px)
- Action text: `accent`

### Progress Indicators

- Track: `surfaceElevated`
- Active: `accentLight` (stabilization), `accent` (compilation)
- Border radius: `radiusXSmall` (4px) for linear indicators

### Time Picker

- Background: `surface`
- Primary color: `accent`
- Text: `textPrimary`

---

## Flutter Implementation

### AppColors Class

```dart
class AppColors {
  // Backgrounds
  static const Color background = Color(0xFF0F0F0F);
  static const Color backgroundDark = Color(0xFF0A0A0A);

  // Surfaces
  static const Color surface = Color(0xFF1A1A1A);
  static const Color surfaceElevated = Color(0xFF2A2A2A);

  // Semantic
  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFFF9500);
  static const Color warningMuted = Color(0xFFC9A179);
  static const Color info = Color(0xFF2196F3);

  // Brand/Accent Ramp
  static const Color accentLight = Color(0xFF66AACC);
  static const Color accent = Color(0xFF4A9ECC);
  static const Color accentDark = Color(0xFF3285AF);
  static const Color accentDarker = Color(0xFF206588);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textTertiary = Color(0xFF636366);

  // Utility
  static const Color overlay = Color(0xFF000000);
  static const Color disabled = Color(0xFF5A5A5A);
  static const Color guideCorner = Color(0xFF924904);

  // Settings aliases (for backwards compatibility)
  static const Color settingsBackground = backgroundDark;
  static const Color settingsCardBackground = surface;
  static const Color settingsCardBorder = surfaceElevated;
  static const Color settingsDivider = surfaceElevated;
  static const Color settingsAccent = accent;
  static const Color settingsTextPrimary = textPrimary;
  static const Color settingsTextSecondary = textSecondary;
  static const Color settingsTextTertiary = textTertiary;
  static const Color settingsInputBackground = surface;

  // DEPRECATED - Use tokens above instead
  // static const Color darkOverlay = ... → Use overlay @ 0.5
  // static const Color lightGrey = ... → Use textSecondary
  // static const Color darkGrey = ... → Use background
  // static const Color lessDarkGrey = ... → Use surfaceElevated
  // static const Color lightBlue = ... → Use accentLight
  // static const Color darkerLightBlue = ... → Use accentDark
  // static const Color evenDarkerLightBlue = ... → Use accentDarker
  // static const Color orange = ... → Use warningMuted
}
```

### Usage Example

```dart
// Instead of:
color: Color(0xff1a1a1a)
color: Colors.white
color: Color(0xFFDC2626)
color: Colors.blue.withValues(alpha: 0.5)
fontFamily: 'monospace'

// Use:
color: AppColors.surface
color: AppColors.textPrimary
color: AppColors.danger
color: AppColors.info.withValues(alpha: 0.5)
fontFamily: 'JetBrainsMono'
```

---

## Migration Notes

### Colors to Replace

| Old Value | New Token |
|-----------|-----------|
| `0xff0A0A0A` | `backgroundDark` |
| `0xff0F0F0F` | `background` |
| `0xff121212` | `background` |
| `0xff151517` | `background` |
| `0xff1A1A1A` | `surface` |
| `0xff1C1C1E` | `surface` |
| `0xff1a1a1a` | `surface` |
| `0xff1e1e1e` | `surface` |
| `0xff212121` | `surfaceElevated` |
| `0xff2A2A2A` | `surfaceElevated` |
| `0xFFDC2626` | `danger` |
| `0xffFF453A` | `danger` |
| `0xff4CD964` | `success` |
| `0xFF22C55E` | `success` |
| `0xffFF9500` | `warning` |
| `0xffc9a179` | `warningMuted` |
| `0xff66aacc` | `accentLight` |
| `0xff3285af` | `accentDark` |
| `0xff206588` | `accentDarker` |
| `0xff924904` | `guideCorner` |
| `Colors.white` | `textPrimary` |
| `Colors.white70` | `textPrimary` @ 0.7 |
| `Colors.white24` | `textPrimary` @ `opacityMild` |
| `Colors.grey` | `textSecondary` |
| `Colors.blue` | `info` |
| `Colors.blue.withValues(...)` | `info.withValues(...)` |

### AppColors to Migrate

| Old Token | New Token |
|-----------|-----------|
| `AppColors.darkOverlay` | `AppColors.overlay` @ 0.5 or `AppColors.surface` |
| `AppColors.lightGrey` | `AppColors.textSecondary` (UNUSED - remove) |
| `AppColors.darkGrey` | `AppColors.background` |
| `AppColors.lessDarkGrey` | `AppColors.surfaceElevated` |
| `AppColors.lightBlue` | `AppColors.accentLight` |
| `AppColors.darkerLightBlue` | `AppColors.accentDark` |
| `AppColors.evenDarkerLightBlue` | `AppColors.accentDarker` |
| `AppColors.orange` | `AppColors.warningMuted` |

### Font Sizes to Normalize

| Old Size | New Size | Token |
|----------|----------|-------|
| 9px | 11px | `caption` |
| 10px | 11px | `caption` |
| 11px | 11px | `caption` |
| 11.5px | 12px | `labelSmall` |
| 12px | 12px | `labelSmall` |
| 13px | 13px | `bodySmall` / `labelMedium` |
| 13.5px | 14px | `bodyMedium` |
| 13.7px | 14px | `bodyMedium` |
| 14px | 14px | `bodyMedium` / `labelLarge` |
| 14.5px | 15px | `titleMedium` |
| 15px | 15px | `titleMedium` |
| 16px | 16px | `bodyLarge` / `titleLarge` |
| 18px | 18px | `headlineMedium` |
| 19px | 20px | `headlineLarge` |
| 20px | 20px | `headlineLarge` |
| 22px | 24px | `displayMedium` |
| 24px | 24px | `displayMedium` |
| 26-28px | 28px | `displayLarge` |

### Border Radius to Normalize

| Old Value | New Token |
|-----------|-----------|
| 2px | `radiusXSmall` (4px) - for drag handles only |
| 4px | `radiusXSmall` |
| 6px | `radiusSmall` (8px) |
| 7px | `radiusSmall` (8px) |
| 10px | `radiusMediumSmall` |
| 11px | `radiusMedium` (12px) |
| 14px | `radiusMediumLarge` |

### Spacing to Normalize (Future)

For strict 4px grid adherence, consider:

| Legacy Value | Preferred Value |
|--------------|-----------------|
| 3px | 4px (`space4`) |
| 10px | 8px or 12px |
| 14px | 12px or 16px |
| 18px | 16px or 20px |
