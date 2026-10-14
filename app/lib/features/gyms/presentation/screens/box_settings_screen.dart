import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Box-level configuration — one home for the identity, scheduling, membership
/// and notification settings that today are scattered across the profile and
/// create-gym flows. A left-nav (section chips on mobile) drives a single
/// settings panel.
///
/// Scheduling and notification rules are held in local session state: the
/// backend enforcement lands with Memberships & Payments, so those sections are
/// flagged as such rather than silently pretending to persist.
class BoxSettingsScreen extends ConsumerStatefulWidget {
  const BoxSettingsScreen({super.key});

  @override
  ConsumerState<BoxSettingsScreen> createState() => _BoxSettingsScreenState();
}

enum _SettingsSection { identity, scheduling, memberships, notifications, danger }

class _ClassType {
  const _ClassType(this.name, this.capacity);
  final String name;
  final int capacity;
}

class _BoxSettingsScreenState extends ConsumerState<BoxSettingsScreen> {
  _SettingsSection _section = _SettingsSection.scheduling;

  // Scheduling rules (local session state — see class doc).
  int _bookingWindowDays = 14;
  int _cancelCutoffHours = 2;
  bool _waitlistAutoPromote = true;
  bool _blockWithoutMembership = false;

  // Notification rules (local session state).
  bool _notifyJoinRequests = true;
  bool _notifyWaitlistPromotion = true;
  bool _notifyLowFill = false;

  List<_ClassType> _classTypes = const [
    _ClassType('WOD', 20),
    _ClassType('Open Gym', 24),
    _ClassType('Skill', 14),
    _ClassType('PT', 2),
  ];

  void _save(String sectionLabel) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$sectionLabel saved for this session. Server-side enforcement '
          'arrives with Memberships & Payments.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final hasAccess =
        profile?.role == UserRole.admin && profile?.activeGym != null;

    return AppMobileScaffold(
      title: 'Box configuration',
      eyebrow: 'Box config',
      onBack: () => context.go('/profile'),
      body: !hasAccess
          ? Padding(
              padding: const EdgeInsets.all(appSpaceLg),
              child: AppEmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Owner access required',
                subtitle:
                    'Switch to an active box you own to configure it.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                appSpaceLg,
                appSpaceLg,
                appSpaceLg,
                appSpace3xl,
              ),
              children: [
                _SectionNav(
                  selected: _section,
                  onSelected: (section) => setState(() => _section = section),
                ),
                const SizedBox(height: appSpace2xl),
                _buildPanel(profile?.activeGym?.name ?? 'Your box',
                    profile?.activeGym?.timezone ?? 'GMT'),
              ],
            ),
    );
  }

  Widget _buildPanel(String gymName, String timezone) {
    switch (_section) {
      case _SettingsSection.identity:
        return _IdentityPanel(gymName: gymName, timezone: timezone);
      case _SettingsSection.scheduling:
        return _SchedulingPanel(
          bookingWindowDays: _bookingWindowDays,
          cancelCutoffHours: _cancelCutoffHours,
          waitlistAutoPromote: _waitlistAutoPromote,
          blockWithoutMembership: _blockWithoutMembership,
          classTypes: _classTypes,
          onBookingWindowChanged: (v) =>
              setState(() => _bookingWindowDays = v),
          onCancelCutoffChanged: (v) => setState(() => _cancelCutoffHours = v),
          onWaitlistAutoPromoteChanged: (v) =>
              setState(() => _waitlistAutoPromote = v),
          onBlockWithoutMembershipChanged: (v) =>
              setState(() => _blockWithoutMembership = v),
          onAddClassType: _addClassType,
          onRemoveClassType: (index) => setState(
            () => _classTypes = [
              for (var i = 0; i < _classTypes.length; i++)
                if (i != index) _classTypes[i],
            ],
          ),
          onSave: () => _save('Scheduling rules'),
        );
      case _SettingsSection.memberships:
        return const _RoadmapPanel(
          title: 'Membership plans',
          message:
              'Define plans, drop-ins and billing once Memberships & Payments '
              'ships. Booking rules above will hook into it automatically.',
        );
      case _SettingsSection.notifications:
        return _NotificationsPanel(
          notifyJoinRequests: _notifyJoinRequests,
          notifyWaitlistPromotion: _notifyWaitlistPromotion,
          notifyLowFill: _notifyLowFill,
          onJoinRequestsChanged: (v) => setState(() => _notifyJoinRequests = v),
          onWaitlistPromotionChanged: (v) =>
              setState(() => _notifyWaitlistPromotion = v),
          onLowFillChanged: (v) => setState(() => _notifyLowFill = v),
          onSave: () => _save('Notification rules'),
        );
      case _SettingsSection.danger:
        return const _DangerPanel();
    }
  }

  Future<void> _addClassType() async {
    final result = await showModalBottomSheet<_ClassType>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _AddClassTypeSheet(),
    );
    if (result != null) {
      setState(() => _classTypes = [..._classTypes, result]);
    }
  }
}

class _SectionNav extends StatelessWidget {
  const _SectionNav({required this.selected, required this.onSelected});

  final _SettingsSection selected;
  final ValueChanged<_SettingsSection> onSelected;

  static const _items = <(_SettingsSection, String, bool)>[
    (_SettingsSection.identity, 'Box Identity', false),
    (_SettingsSection.scheduling, 'Scheduling', false),
    (_SettingsSection.memberships, 'Memberships', true),
    (_SettingsSection.notifications, 'Notifications', false),
    (_SettingsSection.danger, 'Danger Zone', false),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (section, label, soon) in _items) ...[
            _NavChip(
              label: label,
              soon: soon,
              selected: section == selected,
              onTap: () => onSelected(section),
            ),
            const SizedBox(width: appSpaceSm),
          ],
        ],
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  const _NavChip({
    required this.label,
    required this.selected,
    required this.soon,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool soon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(appRadiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? appPrimarySoft : appSurface,
            borderRadius: BorderRadius.circular(appRadiusSm),
            border: Border.all(
              color: selected ? appPrimaryHairline : appBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? appPrimary : appMutedText,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              if (soon) ...[
                const SizedBox(width: 6),
                Text('SOON', style: appMono(fontSize: 8, letterSpacing: 1.2)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared card header: mono eyebrow + display title + optional Save action.
class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.eyebrow, required this.title, this.onSave});

  final String eyebrow;
  final String title;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow.toUpperCase(),
                  style: appMono(fontSize: 10, letterSpacing: 1.5,
                      color: appPrimary)),
              const SizedBox(height: 5),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
              ),
            ],
          ),
        ),
        if (onSave != null)
          AppPrimaryButton(
            label: 'Save changes',
            onPressed: onSave,
            size: AppButtonSize.md,
          ),
      ],
    );
  }
}

class _IdentityPanel extends StatelessWidget {
  const _IdentityPanel({required this.gymName, required this.timezone});

  final String gymName;
  final String timezone;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeader(eyebrow: 'Identity', title: 'Box identity'),
          const SizedBox(height: appSpaceLg),
          Row(
            children: [
              AppAvatar(displayName: gymName, size: 56),
              const SizedBox(width: appSpaceLg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gymName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text('Timezone · $timezone',
                        style: appMono(fontSize: 11, letterSpacing: 0)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: appSpaceLg),
          Text(
            'Box name, logo and timezone are set during box creation. Inline '
            'editing here lands alongside logo upload on the roadmap.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: appMutedText, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _SchedulingPanel extends StatelessWidget {
  const _SchedulingPanel({
    required this.bookingWindowDays,
    required this.cancelCutoffHours,
    required this.waitlistAutoPromote,
    required this.blockWithoutMembership,
    required this.classTypes,
    required this.onBookingWindowChanged,
    required this.onCancelCutoffChanged,
    required this.onWaitlistAutoPromoteChanged,
    required this.onBlockWithoutMembershipChanged,
    required this.onAddClassType,
    required this.onRemoveClassType,
    required this.onSave,
  });

  final int bookingWindowDays;
  final int cancelCutoffHours;
  final bool waitlistAutoPromote;
  final bool blockWithoutMembership;
  final List<_ClassType> classTypes;
  final ValueChanged<int> onBookingWindowChanged;
  final ValueChanged<int> onCancelCutoffChanged;
  final ValueChanged<bool> onWaitlistAutoPromoteChanged;
  final ValueChanged<bool> onBlockWithoutMembershipChanged;
  final VoidCallback onAddClassType;
  final ValueChanged<int> onRemoveClassType;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PanelHeader(
                eyebrow: 'Scheduling',
                title: 'Booking & waitlist rules',
                onSave: onSave,
              ),
              const SizedBox(height: appSpaceLg),
              _StepperField(
                label: 'Booking window',
                help: 'How far ahead members can reserve.',
                value: bookingWindowDays,
                suffix: 'days',
                min: 1,
                max: 60,
                onChanged: onBookingWindowChanged,
              ),
              const Divider(height: appSpace2xl),
              _StepperField(
                label: 'Cancellation cutoff',
                help: 'Latest a member can cancel without penalty.',
                value: cancelCutoffHours,
                suffix: 'hours',
                min: 0,
                max: 48,
                onChanged: onCancelCutoffChanged,
              ),
              const Divider(height: appSpace2xl),
              _ToggleRow(
                label: 'Waitlist auto-promote',
                help: 'Move the next athlete up when a spot frees.',
                value: waitlistAutoPromote,
                onChanged: onWaitlistAutoPromoteChanged,
              ),
              const Divider(height: appSpace2xl),
              _ToggleRow(
                label: 'Block booking without active membership',
                help: 'Requires Memberships & Payments.',
                value: blockWithoutMembership,
                roadmap: true,
                onChanged: onBlockWithoutMembershipChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: appSpaceLg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CLASS TYPES & DEFAULT CAPACITY',
                  style: appMono(fontSize: 10, letterSpacing: 1.4)),
              const SizedBox(height: appSpaceLg),
              Wrap(
                spacing: appSpaceSm,
                runSpacing: appSpaceSm,
                children: [
                  for (var i = 0; i < classTypes.length; i++)
                    _ClassTypeChip(
                      type: classTypes[i],
                      onRemove: () => onRemoveClassType(i),
                    ),
                  _AddTypeChip(onTap: onAddClassType),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepperField extends StatelessWidget {
  const _StepperField({
    required this.label,
    required this.help,
    required this.value,
    required this.suffix,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String help;
  final int value;
  final String suffix;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: appText,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              const SizedBox(height: 3),
              Text(help,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: appSubtleText)),
            ],
          ),
        ),
        const SizedBox(width: appSpaceMd),
        _StepButton(
          icon: Icons.remove_rounded,
          onTap: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 74,
          child: Text(
            '$value $suffix',
            textAlign: TextAlign.center,
            style: appMono(fontSize: 12, letterSpacing: 0, color: appText),
          ),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          onTap: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(appRadiusSm),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: appSurfaceAlt,
            borderRadius: BorderRadius.circular(appRadiusSm),
            border: Border.all(color: appBorderStrong),
          ),
          child: Icon(icon,
              size: 18, color: enabled ? appText : appSubtleText),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.help,
    required this.value,
    required this.onChanged,
    this.roadmap = false,
  });

  final String label;
  final String help;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool roadmap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(label,
                        style: const TextStyle(
                            color: appText,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                  ),
                  if (roadmap) ...[
                    const SizedBox(width: 8),
                    Text('ROADMAP',
                        style: appMono(fontSize: 8, letterSpacing: 1.2)),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(help,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: appSubtleText)),
            ],
          ),
        ),
        const SizedBox(width: appSpaceMd),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _ClassTypeChip extends StatelessWidget {
  const _ClassTypeChip({required this.type, required this.onRemove});

  final _ClassType type;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: appSurfaceAlt,
        borderRadius: BorderRadius.circular(appRadiusSm),
        border: Border.all(color: appBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(type.name,
              style: const TextStyle(
                  color: appText, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(width: 8),
          Text('·${type.capacity}',
              style: appMono(fontSize: 11, letterSpacing: 0, color: appPrimary)),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(appRadiusPill),
            child: const Icon(Icons.close_rounded,
                size: 15, color: appSubtleText),
          ),
        ],
      ),
    );
  }
}

class _AddTypeChip extends StatelessWidget {
  const _AddTypeChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(appRadiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(appRadiusSm),
            border: Border.all(color: appPrimaryHairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 16, color: appPrimary),
              const SizedBox(width: 4),
              Text('Add type',
                  style: const TextStyle(
                      color: appPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationsPanel extends StatelessWidget {
  const _NotificationsPanel({
    required this.notifyJoinRequests,
    required this.notifyWaitlistPromotion,
    required this.notifyLowFill,
    required this.onJoinRequestsChanged,
    required this.onWaitlistPromotionChanged,
    required this.onLowFillChanged,
    required this.onSave,
  });

  final bool notifyJoinRequests;
  final bool notifyWaitlistPromotion;
  final bool notifyLowFill;
  final ValueChanged<bool> onJoinRequestsChanged;
  final ValueChanged<bool> onWaitlistPromotionChanged;
  final ValueChanged<bool> onLowFillChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            eyebrow: 'Notifications',
            title: 'What the box tells you',
            onSave: onSave,
          ),
          const SizedBox(height: appSpaceLg),
          _ToggleRow(
            label: 'New join requests',
            help: 'Ping when an athlete asks to join.',
            value: notifyJoinRequests,
            onChanged: onJoinRequestsChanged,
          ),
          const Divider(height: appSpace2xl),
          _ToggleRow(
            label: 'Waitlist promotions',
            help: 'Alert when a waitlisted athlete gets a spot.',
            value: notifyWaitlistPromotion,
            onChanged: onWaitlistPromotionChanged,
          ),
          const Divider(height: appSpace2xl),
          _ToggleRow(
            label: 'Low-fill warnings',
            help: 'Flag classes trending under capacity.',
            value: notifyLowFill,
            onChanged: onLowFillChanged,
          ),
        ],
      ),
    );
  }
}

class _RoadmapPanel extends StatelessWidget {
  const _RoadmapPanel({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppAccentBadge(
                icon: Icons.workspace_premium_outlined,
                color: appWarning,
              ),
              const SizedBox(width: appSpaceMd),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              AppPill(label: 'Soon', intent: AppPillIntent.warning, dense: true),
            ],
          ),
          const SizedBox(height: appSpaceMd),
          Text(message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: appMutedText, height: 1.5)),
        ],
      ),
    );
  }
}

class _DangerPanel extends StatelessWidget {
  const _DangerPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(appSpaceLg),
      decoration: BoxDecoration(
        color: appDangerSoft,
        borderRadius: BorderRadius.circular(appRadiusLg),
        border: Border.all(color: appDanger.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DANGER ZONE',
              style: appMono(fontSize: 10, letterSpacing: 1.5, color: appDanger)),
          const SizedBox(height: appSpaceMd),
          Text(
            'Archiving hides the box from members while keeping its data. '
            'Deleting is permanent and removes classes, bookings and logs.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: appMutedText, height: 1.5),
          ),
          const SizedBox(height: appSpaceLg),
          Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  label: 'Archive box',
                  size: AppButtonSize.md,
                  onPressed: () => _notImplemented(context, 'Archiving'),
                ),
              ),
              const SizedBox(width: appSpaceSm),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: () => _notImplemented(context, 'Deletion'),
                    style: FilledButton.styleFrom(
                      backgroundColor: appDanger,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(appRadiusSm),
                      ),
                    ),
                    child: const Text('Delete box'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _notImplemented(BuildContext context, String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action lands with box lifecycle management.')),
    );
  }
}

class _AddClassTypeSheet extends StatefulWidget {
  const _AddClassTypeSheet();

  @override
  State<_AddClassTypeSheet> createState() => _AddClassTypeSheetState();
}

class _AddClassTypeSheetState extends State<_AddClassTypeSheet> {
  final _nameController = TextEditingController();
  int _capacity = 20;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: appSpaceLg,
        right: appSpaceLg,
        top: appSpaceLg,
        bottom: MediaQuery.of(context).viewInsets.bottom + appSpaceLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NEW CLASS TYPE',
              style: appMono(fontSize: 10, letterSpacing: 1.4)),
          const SizedBox(height: appSpaceMd),
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'e.g. Endurance'),
          ),
          const SizedBox(height: appSpaceLg),
          _StepperField(
            label: 'Default capacity',
            help: 'Seats per class of this type.',
            value: _capacity,
            suffix: 'seats',
            min: 1,
            max: 100,
            onChanged: (v) => setState(() => _capacity = v),
          ),
          const SizedBox(height: appSpaceLg),
          AppPrimaryButton(
            label: 'Add type',
            onPressed: () {
              final name = _nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(_ClassType(name, _capacity));
            },
          ),
        ],
      ),
    );
  }
}
