---
description: UI styling rules and design guidelines for UsageBar
---

# UI Styling Rules

## NEVER USE:
1. **Purple/Blue gradients** - Do not use purple (#8b5cf6) or blue (#3b82f6) gradient backgrounds anywhere
2. **Linear gradients for buttons** - Use solid colors instead
3. **Flashy or attention-grabbing button styles** - Keep buttons subtle and consistent

## ALWAYS USE:
1. **shadCN-inspired dark theme** styling:
   - Background: `#18181b` (zinc-900)
   - Border: `#27272a` (zinc-800)
   - Hover background: `#27272a`
   - Text color: `#fafafa` (zinc-50)
   - Secondary text: `#a1a1aa` (zinc-400)

2. **Consistent button styling**:
   ```css
   .button {
       background: #18181b;
       color: #fafafa;
       border: 1px solid #27272a;
       border-radius: 6px;
       transition: all 0.15s ease;
   }
   .button:hover {
       background: #27272a;
       border-color: #3f3f46;
   }
   ```

3. **Color palette** (zinc-based):
   - Primary surface: `#09090b` (zinc-950)
   - Secondary surface: `#18181b` (zinc-900)
   - Border: `#27272a` (zinc-800)
   - Muted: `#3f3f46` (zinc-700)
   - Text primary: `#fafafa` (zinc-50)
   - Text secondary: `#a1a1aa` (zinc-400)
   - Success: `#22c55e` (green-500)
   - Error: `#ef4444` (red-500)
   - Warning: `#f59e0b` (amber-500)

## Accent Colors (for provider bars/icons only):
- Antigravity: `#5FBFA0` (teal)
- Use sparingly for usage meter fills

## Reference:
This project uses a dark, minimal aesthetic inspired by shadCN/UI design system.
Keep the interface clean, professional, and easy on the eyes.
