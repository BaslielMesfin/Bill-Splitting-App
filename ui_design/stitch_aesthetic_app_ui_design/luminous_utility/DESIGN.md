---
name: Luminous Utility
colors:
  surface: '#f9f9f9'
  surface-dim: '#dadada'
  surface-bright: '#f9f9f9'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f3f3f3'
  surface-container: '#eeeeee'
  surface-container-high: '#e8e8e8'
  surface-container-highest: '#e2e2e2'
  on-surface: '#1b1b1b'
  on-surface-variant: '#4c4546'
  inverse-surface: '#303030'
  inverse-on-surface: '#f1f1f1'
  outline: '#7e7576'
  outline-variant: '#cfc4c5'
  surface-tint: '#5e5e5e'
  primary: '#000000'
  on-primary: '#ffffff'
  primary-container: '#1b1b1b'
  on-primary-container: '#848484'
  inverse-primary: '#c6c6c6'
  secondary: '#326385'
  on-secondary: '#ffffff'
  secondary-container: '#a8d7ff'
  on-secondary-container: '#2d5e80'
  tertiary: '#000000'
  on-tertiary: '#ffffff'
  tertiary-container: '#181c1e'
  on-tertiary-container: '#818486'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#e2e2e2'
  primary-fixed-dim: '#c6c6c6'
  on-primary-fixed: '#1b1b1b'
  on-primary-fixed-variant: '#474747'
  secondary-fixed: '#cbe6ff'
  secondary-fixed-dim: '#9dccf3'
  on-secondary-fixed: '#001e30'
  on-secondary-fixed-variant: '#144b6c'
  tertiary-fixed: '#e0e3e5'
  tertiary-fixed-dim: '#c4c7c9'
  on-tertiary-fixed: '#181c1e'
  on-tertiary-fixed-variant: '#434749'
  background: '#f9f9f9'
  on-background: '#1b1b1b'
  surface-variant: '#e2e2e2'
  surface-blue: '#E1EEF9'
  surface-gray: '#F2F2F7'
  accent-pink: '#FFB1C1'
  success-green: '#28CD41'
  error-red: '#FF3B30'
typography:
  headline-xl:
    fontFamily: Inter
    fontSize: 40px
    fontWeight: '800'
    lineHeight: 48px
    letterSpacing: -0.03em
  headline-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 38px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 28px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 34px
    letterSpacing: -0.02em
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 26px
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.02em
  numeric-display:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '700'
    lineHeight: 24px
    letterSpacing: -0.01em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 8px
  container-padding: 24px
  stack-gap-sm: 12px
  stack-gap-md: 20px
  grid-gutter: 16px
---

## Brand & Style

The design system is built on a foundation of **Minimalist High-Contrast** aesthetics, blending the functional rigor of a utility app with the premium, airy feel of high-end consumer hardware. The brand personality is efficient, transparent, and sophisticated, aiming to transform the stressful task of manual math into a frictionless, almost serene experience.

The visual language draws inspiration from modern editorial design: expansive whitespace, bold "ink-on-paper" typography, and soft, pastel-tinted backgrounds that reduce cognitive load. Interaction design follows an "Apple-esque" philosophy—using subtle physical metaphors like squishy button states and organic card shapes to make the interface feel responsive and tangible.

## Colors

The palette is strictly divided between **functional containers** and **actionable elements**. 

- **Primary & Neutral:** Deep black is used exclusively for primary typography and high-priority action buttons, creating a "ink-on-paper" contrast against the light canvas.
- **Surface Tints:** Instead of pure white, the system uses `surface-blue` and `surface-gray` for background layers to define the "airy" mood and reduce glare.
- **Semantic Accents:** `accent-pink` is used sparingly for decorative highlights or secondary visual interest (e.g., specific item flags), while standard green and red are used for validation states during receipt review.

## Typography

The system utilizes **Inter** for its entire range, leveraging its neutral, geometric qualities to maintain clarity during data-heavy tasks. 

- **Display Logic:** Use `headline-xl` for large monetary totals on the summary screen. These should always be tight in letter-spacing to feel impactful.
- **Numbers:** Since the app focuses on financial data, use tabular lining figures where possible to ensure columns of prices align vertically.
- **Labels:** `label-md` is the workhorse for participant names and item tags, using a semi-bold weight to maintain legibility against colored backgrounds.

## Layout & Spacing

This design system uses a **Fluid Container** model with generous safe-area margins. 

- **Whitespace:** Elements are grouped in logical cards with a minimum internal padding of `container-padding` (24px). 
- **The 8px Grid:** All vertical spacing and element heights must be multiples of 8px. 
- **Mobile First:** On mobile devices, the layout relies on a single-column stack with persistent bottom action bars. Content should never touch the edge of the screen; a minimum 20px horizontal margin is required for all primary content blocks.

## Elevation & Depth

Depth is established through **Tonal Layering** and **Soft Ambient Shadows** rather than traditional heavy drop-shadows.

1.  **Level 0 (Base):** The main background using `surface-blue` or `surface-gray`.
2.  **Level 1 (Cards):** High-contrast white or off-white surfaces with a very soft, diffused shadow (15% opacity, 20px blur) to suggest they are floating slightly above the base.
3.  **Level 2 (Active Elements):** Primary buttons and selected chips use absolute black, appearing to "sit on top" of all other layers through pure contrast rather than shadow depth.
4.  **Glassmorphism:** Use backdrop blurs (20px) for fixed navigation bars and top headers to maintain context of the content scrolling beneath them.

## Shapes

The shape language is defined by **large, organic radii**. 

- **Cards & Primary Containers:** Use `rounded-xl` (1.5rem / 24px) to create a friendly, modern silhouette. 
- **Buttons & Chips:** Use `rounded-lg` (1rem / 16px) or full pill-shapes for smaller interactive elements. 
- **Image Previews:** Receipt captures should be framed within `rounded-xl` containers to soften the technical nature of the document.

## Components

### Buttons
- **Primary:** Solid black background, white `label-md` text. High-squish active state (scale 0.96 on tap).
- **Secondary:** Semi-transparent `secondary_color_hex` background with black text.
- **Ghost:** No background, black text with a subtle 1px border at 10% opacity.

### Chips (Participants & Items)
- **Participant Chip:** Rounded pill shape with `surface-gray` background. When selected, transitions to `secondary_color_hex` or a person-specific pastel.
- **Item Chip:** Used in the "Assign Items" flow. Large tap targets (min 48px height) with left-aligned text and right-aligned price.

### Cards
- White background, `rounded-xl` corners, and subtle ambient shadow.
- Used for grouping line items or displaying per-person totals on the Summary screen.

### Input Fields
- Underlined or soft-gray background containers. 
- Focus states should be indicated by a weight increase in the label or a subtle expansion of the container, avoiding harsh focus rings.

### Progress Indicators
- Use a thick, horizontal bar at the very top of the screen (4px height) in black to show completion of item assignments.