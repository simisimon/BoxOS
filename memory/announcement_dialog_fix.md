---
name: announcement-dialog-fix
description: ConsumerStatefulWidget inside showDialog caused blank modal (dark filter visible, no dialog content) in GoRouter 17.x + StatefulShellRoute setup
metadata:
  type: project
---

User repeatedly couldn't create announcements: clicking "Create Announcement" showed only a dark modal barrier with no dialog content.

**Root cause hypothesis:** `ConsumerStatefulWidget` inside `showDialog` with GoRouter 17.x `StatefulShellRoute.indexedStack` caused a widget build failure — Riverpod's `ref` initialization or ProviderScope lookup may silently fail in the nested navigator context, producing an empty dialog.

**Fix applied:** Converted `_AnnouncementComposerDialog` from `ConsumerStatefulWidget` to `StatefulWidget`. Repository is now read via `ref.read(announcementRepositoryProvider)` in `_HomeScreenState` (before calling `showDialog`) and passed as a constructor parameter `required AnnouncementRepository repository`. Also changed `barrierDismissible: false` (better UX for form dialogs) and replaced `Row` + unconstrained `FilledButton.icon` with `Wrap` + explicit `minimumSize: Size(0, 44)` to avoid infinite-width layout issues from the global `minimumSize: Size.fromHeight(52)` theme.

**How to apply:** When showing complex dialogs from ConsumerState in GoRouter StatefulShellRoute apps, prefer passing providers/repositories as constructor parameters rather than using ConsumerStatefulWidget in the dialog itself.
