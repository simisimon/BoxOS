# BoxOS UI Guidelines

BoxOS is a mobile-first Flutter app for iOS and Android. These guidelines capture the current interface conventions so new screens feel consistent across both platforms.

## Screen Width And Spacing
- Primary app screens use the shared `MobileContent` width constraint: content must not exceed `mobileContentMaxWidth` (`480`) on wide viewports.
- Shell screens already get this constraint from `AuthenticatedScaffold`; standalone routes must apply `MobileContent` or `MobileScrollableContent` themselves.
- Within that constrained content area, screens use full available mobile width with `ListView` or equivalent scrollable content.
- Use `EdgeInsets.all(16)` as the default page padding.
- Do not let standalone screens span the entire tablet/desktop viewport. Empty states, placeholders, forms, cards, and lists should align to the same constrained width and 16px page margin as Home.
- Cards inside primary screens should stretch to the available content width unless they are part of a deliberate compact control.

## Layout
- Prefer single-column stacked sections on phone-sized screens.
- Keep repeated content such as news, status rows, notifications, and quick actions below each other, not side by side.
- Use full-width tappable rows for navigation actions that are not already in the footer navigation.
- Avoid duplicating footer navigation destinations in screen quick actions.

## Components
- Use `AppBar` for screen titles and contextual actions.
- Use cards for individual pieces of content, not for wrapping whole page sections.
- Use a consistent 44x44 icon badge for row-style cards where an icon helps scanning.
- Use clear section titles with slightly stronger weight for top-level sections.

## Mobile Behavior
- Design first for iOS and Android phone widths.
- All important content must be reachable by vertical scrolling.
- Touch targets should be easy to hit; prefer full-row tap areas for list actions.
- Text must wrap cleanly inside cards and buttons without clipping on narrow phones.

## Placeholder And Empty States
- Empty states should use the same screen width and 16px page padding as populated states.
- Empty states should explain what will appear there and provide one relevant next action when available.
- Avoid large centered hero-style placeholders in operational screens unless the entire screen is a first-run setup flow.
