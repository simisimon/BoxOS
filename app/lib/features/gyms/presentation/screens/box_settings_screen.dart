import 'dart:typed_data';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/calendar/data/repositories/class_types_repository.dart';
import 'package:app/features/calendar/domain/models/class_type.dart';
import 'package:app/features/calendar/presentation/widgets/class_type_badge.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/memberships/presentation/membership_settings_panel.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

/// Box-level configuration — one home for the identity, scheduling, membership
/// and notification settings that today are scattered across the profile and
/// create-gym flows. The sidebar's Settings ▸ submenu and the section
/// chips both select the page via `?section=`.
///
/// Scheduling and notification rules are held in local session state: the
/// backend enforcement lands with Memberships & Payments, so those sections are
/// flagged as such rather than silently pretending to persist.
class BoxSettingsScreen extends ConsumerStatefulWidget {
  const BoxSettingsScreen({super.key, this.section = SettingsSection.profile});

  /// The page shown; wide screens pick it in the sidebar submenu, phones in
  /// the chips at the top.
  final SettingsSection section;

  @override
  ConsumerState<BoxSettingsScreen> createState() => _BoxSettingsScreenState();
}

/// The Settings ▸ submenu (docs/admin-ui-reference.md §12), in sidebar order.
/// [slug] is the `?section=` value in the route.
enum SettingsSection {
  profile('profile', 'Gym profile'),
  bookingRules('booking-rules', 'Booking rules'),
  classTypes('class-types', 'Class types'),
  payments('payments', 'Payments'),
  notifications('notifications', 'Notifications');

  const SettingsSection(this.slug, this.label);

  final String slug;
  final String label;

  static SettingsSection fromSlug(String? slug) => values.firstWhere(
    (section) => section.slug == slug,
    orElse: () => SettingsSection.profile,
  );
}

class _BoxSettingsScreenState extends ConsumerState<BoxSettingsScreen> {
  late SettingsSection _section = widget.section;

  @override
  void didUpdateWidget(BoxSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) _section = widget.section;
  }

  // Scheduling rules (local session state — see class doc).
  int _bookingWindowDays = 14;
  int _cancelCutoffHours = 2;
  bool _waitlistAutoPromote = true;

  // Notification rules (local session state).
  bool _notifyJoinRequests = true;
  bool _notifyWaitlistPromotion = true;
  bool _notifyLowFill = false;

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

    // Rendered as a tab body inside the authenticated shell, which supplies
    // the header, navigation, background and content column.
    if (!hasAccess) {
      return const Padding(
        padding: EdgeInsets.all(appSpaceLg),
        child: AppEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Owner access required',
          subtitle: 'Switch to an active box you own to configure it.',
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        appSpaceLg,
        appSpaceLg,
        appSpaceLg,
        appSpace3xl,
      ),
      children: [
        // Always shown: a collapsed sidebar hides its Settings submenu.
        _SectionNav(
          selected: _section,
          onSelected: (section) {
            // Through the URL so the sidebar highlight, reload and Back
            // agree; tests without a router just switch locally.
            if (GoRouter.maybeOf(context) != null) {
              context.go('/box-settings?section=${section.slug}');
            } else {
              setState(() => _section = section);
            }
          },
        ),
        const SizedBox(height: appSpace2xl),
        _buildPanel(profile!.activeGym!),
      ],
    );
  }

  Widget _buildPanel(GymSummary gym) {
    switch (_section) {
      case SettingsSection.profile:
        // Archiving the box sits at the end of its profile.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _IdentityPanel(
              // Rebuild the form from the server values after each save.
              key: ValueKey(
                '${gym.id}|${gym.name}|${gym.logoUrl}|${gym.timezone}',
              ),
              gym: gym,
            ),
            const SizedBox(height: appSpace2xl),
            const _DangerPanel(),
          ],
        );
      case SettingsSection.bookingRules:
        return _SchedulingPanel(
          bookingWindowDays: _bookingWindowDays,
          cancelCutoffHours: _cancelCutoffHours,
          waitlistAutoPromote: _waitlistAutoPromote,
          onBookingWindowChanged: (v) => setState(() => _bookingWindowDays = v),
          onCancelCutoffChanged: (v) => setState(() => _cancelCutoffHours = v),
          onWaitlistAutoPromoteChanged: (v) =>
              setState(() => _waitlistAutoPromote = v),
          onSave: () => _save('Booking rules'),
        );
      case SettingsSection.classTypes:
        return const _ClassTypesTable();
      case SettingsSection.payments:
        return const MembershipSettingsPanel();
      case SettingsSection.notifications:
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
    }
  }
}

class _SectionNav extends StatelessWidget {
  const _SectionNav({required this.selected, required this.onSelected});

  final SettingsSection selected;
  final ValueChanged<SettingsSection> onSelected;

  static final _items = [
    for (final section in SettingsSection.values)
      (section, section.label, false),
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
  const _PanelHeader({
    required this.eyebrow,
    required this.title,
    this.onSave,
    this.busy = false,
  });

  final String eyebrow;
  final String title;
  final VoidCallback? onSave;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: appMono(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: appPrimary,
                ),
              ),
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
        AppPrimaryButton(
          label: 'Save changes',
          onPressed: onSave,
          busy: busy,
          size: AppButtonSize.md,
          expand: false,
        ),
      ],
    );
  }
}

/// Common IANA zones offered as suggestions. Any other valid IANA name can be
/// typed; the backend rejects unknown zones.
const _timezoneSuggestions = <String>[
  'UTC',
  'Europe/London',
  'Europe/Dublin',
  'Europe/Lisbon',
  'Europe/Berlin',
  'Europe/Vienna',
  'Europe/Zurich',
  'Europe/Amsterdam',
  'Europe/Brussels',
  'Europe/Paris',
  'Europe/Madrid',
  'Europe/Rome',
  'Europe/Copenhagen',
  'Europe/Stockholm',
  'Europe/Oslo',
  'Europe/Helsinki',
  'Europe/Warsaw',
  'Europe/Prague',
  'Europe/Athens',
  'Europe/Istanbul',
  'America/New_York',
  'America/Toronto',
  'America/Chicago',
  'America/Denver',
  'America/Phoenix',
  'America/Los_Angeles',
  'America/Vancouver',
  'America/Mexico_City',
  'America/Sao_Paulo',
  'America/Buenos_Aires',
  'Africa/Johannesburg',
  'Asia/Dubai',
  'Asia/Kolkata',
  'Asia/Singapore',
  'Asia/Hong_Kong',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Australia/Perth',
  'Australia/Sydney',
  'Australia/Melbourne',
  'Pacific/Auckland',
];

/// Edits the box name, logo and timezone of the active box (owner only).
class _IdentityPanel extends ConsumerStatefulWidget {
  const _IdentityPanel({super.key, required this.gym});

  final GymSummary gym;

  @override
  ConsumerState<_IdentityPanel> createState() => _IdentityPanelState();
}

class _IdentityPanelState extends ConsumerState<_IdentityPanel> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _timezoneController;
  late String _logoUrl;
  Uint8List? _logoPreview;
  bool _uploadingLogo = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.gym.name)
      ..addListener(_onChanged);
    _timezoneController = TextEditingController(text: widget.gym.timezone)
      ..addListener(_onChanged);
    _logoUrl = widget.gym.logoUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  String get _name => _nameController.text.trim();
  String get _timezone => _timezoneController.text.trim();

  bool get _nameChanged => _name != widget.gym.name;
  bool get _logoChanged => _logoUrl != widget.gym.logoUrl;
  bool get _timezoneChanged => _timezone != widget.gym.timezone;
  bool get _dirty => _nameChanged || _logoChanged || _timezoneChanged;

  Future<void> _pickLogo() async {
    if (_uploadingLogo || _saving) return;
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1200,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final contentType = switch (picked.mimeType) {
        final type? when type.trim().isNotEmpty => type,
        _ when picked.name.toLowerCase().endsWith('.png') => 'image/png',
        _ when picked.name.toLowerCase().endsWith('.webp') => 'image/webp',
        _ => 'image/jpeg',
      };
      setState(() {
        _uploadingLogo = true;
        _error = null;
      });
      final logoUrl = await ref
          .read(gymRepositoryProvider)
          .uploadGymLogo(
            bytes: bytes,
            filename: picked.name,
            contentType: contentType,
          );
      if (!mounted) return;
      setState(() {
        _logoUrl = logoUrl;
        _logoPreview = bytes;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = errorMessageFrom(error, fallback: 'Logo upload failed.'),
      );
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  void _removeLogo() => setState(() {
    _logoUrl = '';
    _logoPreview = null;
  });

  void _reset() => setState(() {
    _nameController.text = widget.gym.name;
    _timezoneController.text = widget.gym.timezone;
    _logoUrl = widget.gym.logoUrl;
    _logoPreview = null;
    _error = null;
  });

  Future<void> _save() async {
    if (!_dirty || _saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_timezoneChanged) {
      final confirmed = await showAppConfirmDialog(
        context,
        title: 'Change timezone?',
        message:
            'Recurring classes move to the same local time in $_timezone. '
            'Classes that already have bookings keep their current time and '
            'become one-off classes.',
        confirmLabel: 'Change timezone',
      );
      if (!confirmed || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(gymRepositoryProvider)
          .updateCurrentGym(
            name: _nameChanged ? _name : null,
            logoUrl: _logoChanged ? _logoUrl : null,
            timezone: _timezoneChanged ? _timezone : null,
          );
      ref.invalidate(currentProfileProvider);
      if (!mounted) return;
      final detached = result.detachedSessions;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            detached == 0
                ? 'Box identity saved.'
                : 'Box identity saved. $detached booked '
                      '${detached == 1 ? 'class keeps' : 'classes keep'} '
                      'the old time as one-off.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = errorMessageFrom(
          error,
          fallback: 'Could not save the box identity.',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _uploadingLogo;
    final displayName = _name.isEmpty ? widget.gym.name : _name;
    return AppCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelHeader(
              eyebrow: 'Identity',
              title: 'Box identity',
              onSave: _dirty && !busy ? _save : null,
              busy: _saving,
            ),
            const SizedBox(height: appSpaceLg),
            Row(
              children: [
                _logoPreview != null
                    ? ClipOval(
                        child: Image.memory(
                          _logoPreview!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      )
                    : AppAvatar(
                        displayName: displayName,
                        imageUrl: _logoUrl,
                        size: 56,
                      ),
                const SizedBox(width: appSpaceLg),
                Expanded(
                  child: OverflowBar(
                    spacing: appSpaceSm,
                    overflowSpacing: appSpaceSm,
                    children: [
                      AppSecondaryButton(
                        label: _uploadingLogo
                            ? 'Uploading…'
                            : (_logoUrl.isEmpty
                                  ? 'Upload logo'
                                  : 'Change logo'),
                        icon: Icons.add_photo_alternate_outlined,
                        size: AppButtonSize.md,
                        expand: false,
                        busy: _uploadingLogo,
                        onPressed: busy ? null : _pickLogo,
                      ),
                      if (_logoUrl.isNotEmpty)
                        TextButton(
                          onPressed: busy ? null : _removeLogo,
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: appSpaceLg),
            TextFormField(
              controller: _nameController,
              enabled: !_saving,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Box name',
                counterText: '',
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Box name is required' : null,
            ),
            const SizedBox(height: appSpaceMd),
            _TimezoneField(controller: _timezoneController, enabled: !_saving),
            const SizedBox(height: appSpaceSm),
            Text(
              'Class times follow the box timezone. The box link '
              '(${widget.gym.slug}) stays the same when you rename it.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: appMutedText, height: 1.5),
            ),
            if (_error != null) ...[
              const SizedBox(height: appSpaceMd),
              Text(
                _error!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: appDanger),
              ),
            ],
            if (_dirty && !_saving) ...[
              const SizedBox(height: appSpaceSm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _uploadingLogo ? null : _reset,
                  child: const Text('Discard changes'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Free-text timezone input with IANA suggestions.
class _TimezoneField extends StatefulWidget {
  const _TimezoneField({required this.controller, required this.enabled});

  final TextEditingController controller;
  final bool enabled;

  @override
  State<_TimezoneField> createState() => _TimezoneFieldState();
}

class _TimezoneFieldState extends State<_TimezoneField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return _timezoneSuggestions;
        return _timezoneSuggestions.where(
          (zone) => zone.toLowerCase().contains(query),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled,
          decoration: const InputDecoration(
            labelText: 'Timezone',
            hintText: 'e.g. Europe/Berlin',
            suffixIcon: Icon(Icons.public_rounded),
          ),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'Timezone is required' : null,
          onFieldSubmitted: (_) => onSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            color: appSurface,
            borderRadius: BorderRadius.circular(appRadiusSm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final zone in options)
                    ListTile(
                      dense: true,
                      title: Text(
                        zone,
                        style: appMono(
                          fontSize: 12,
                          letterSpacing: 0,
                          color: appText,
                        ),
                      ),
                      onTap: () => onSelected(zone),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SchedulingPanel extends StatelessWidget {
  const _SchedulingPanel({
    required this.bookingWindowDays,
    required this.cancelCutoffHours,
    required this.waitlistAutoPromote,
    required this.onBookingWindowChanged,
    required this.onCancelCutoffChanged,
    required this.onWaitlistAutoPromoteChanged,
    required this.onSave,
  });

  final int bookingWindowDays;
  final int cancelCutoffHours;
  final bool waitlistAutoPromote;
  final ValueChanged<int> onBookingWindowChanged;
  final ValueChanged<int> onCancelCutoffChanged;
  final ValueChanged<bool> onWaitlistAutoPromoteChanged;
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
              Text(
                label,
                style: const TextStyle(
                  color: appText,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                help,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: appSubtleText),
              ),
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
          child: Icon(icon, size: 18, color: enabled ? appText : appSubtleText),
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
  });

  final String label;
  final String help;
  final bool value;
  final ValueChanged<bool> onChanged;

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
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: appText,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                help,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: appSubtleText),
              ),
            ],
          ),
        ),
        const SizedBox(width: appSpaceMd),
        Switch(value: value, onChanged: onChanged),
      ],
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
          Text(
            'DANGER ZONE',
            style: appMono(fontSize: 10, letterSpacing: 1.5, color: appDanger),
          ),
          const SizedBox(height: appSpaceMd),
          Text(
            'Archiving hides the box from members while keeping its data. '
            'Deleting is permanent and removes classes, bookings and logs.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: appMutedText, height: 1.5),
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

/// Settings ▸ Class types: the four built-ins plus the box's own types,
/// with their calendar colour and default class size. Owners add and remove
/// their own types here.
class _ClassTypesTable extends ConsumerWidget {
  const _ClassTypesTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = ref.watch(classTypesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: AppPrimaryButton(
            label: 'Create class type',
            icon: Icons.add_rounded,
            size: AppButtonSize.md,
            expand: false,
            onPressed: () => showAppSidePanel<void>(
              context,
              builder: (_) => const _ClassTypePanel(),
            ),
          ),
        ),
        const SizedBox(height: appSpaceLg),
        AppDataTable<ClassType>(
          shrinkWrap: true,
          columns: const [
            AppTableColumn('Name', flex: 3),
            AppTableColumn('Default limit', flex: 2),
            AppTableColumn('', flex: 1),
          ],
          rows: [...ClassType.builtIns, ...?custom.value],
          cells: (type) => [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: classTypeColor(type),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: appSpaceSm),
                Flexible(
                  child: Text(
                    type.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: appText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              '${type.defaultCapacity} participants',
              style: const TextStyle(color: appMutedText),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: type.isCustom
                  ? IconButton(
                      tooltip: 'Delete ${type.label}',
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      color: appMutedText,
                      onPressed: () => _delete(context, ref, type),
                    )
                  : Text(
                      'BUILT-IN',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: appMono(fontSize: 9, color: appMutedText),
                    ),
            ),
          ],
        ),
        if (custom.hasError) ...[
          const SizedBox(height: appSpaceSm),
          Text(
            errorMessageFrom(
              custom.error!,
              fallback: 'Could not load your class types.',
            ),
            style: const TextStyle(color: appDanger),
          ),
        ],
      ],
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ClassType type,
  ) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete ${type.label}?',
      message:
          'New classes and plans can no longer use it. Classes that already '
          'have this type keep it.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await ref.read(classTypesRepositoryProvider).delete(type.id!);
      if (context.mounted) {
        ref.invalidate(classTypesProvider);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessageFrom(error, fallback: 'Could not delete the type.'),
            ),
          ),
        );
      }
    }
  }
}

/// Create flow for a custom class type: name, colour, default limit.
class _ClassTypePanel extends ConsumerStatefulWidget {
  const _ClassTypePanel();

  @override
  ConsumerState<_ClassTypePanel> createState() => _ClassTypePanelState();
}

class _ClassTypePanelState extends ConsumerState<_ClassTypePanel> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _capacity = TextEditingController(text: '12');
  String _color = 'info';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(classTypesRepositoryProvider)
          .create(
            name: _name.text.trim(),
            colorKey: _color,
            defaultCapacity: int.parse(_capacity.text.trim()),
          );
      ref.invalidate(classTypesProvider);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessageFrom(error, fallback: 'Could not create the type.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final taken = {
      for (final type in ClassType.values) type.wireValue.toLowerCase(),
    };
    return AppSidePanel(
      title: 'New class type',
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Creating...' : 'Create'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Hyrox',
              ),
              validator: (value) {
                final name = (value ?? '').trim();
                if (name.isEmpty) {
                  return 'Enter a name';
                }
                if (taken.contains(name.toLowerCase())) {
                  return 'That type already exists';
                }
                return null;
              },
            ),
            const SizedBox(height: appSpaceLg),
            Text('COLOUR', style: appMono(fontSize: 10)),
            const SizedBox(height: appSpaceSm),
            Wrap(
              spacing: appSpaceSm,
              runSpacing: appSpaceSm,
              children: [
                for (final key in classTypeColorKeys)
                  Semantics(
                    button: true,
                    selected: _color == key,
                    label: 'Colour ${classTypeColorName(key)}',
                    child: InkWell(
                      onTap: () => setState(() => _color = key),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: _color == key
                              ? Border.all(
                                  color: classTypeColorFor(key),
                                  width: 2,
                                )
                              : null,
                        ),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: classTypeColorFor(key),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: appSpaceLg),
            TextFormField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Default limit',
                suffixText: 'participants',
              ),
              validator: (value) {
                final n = int.tryParse((value ?? '').trim());
                return n == null || n < 1 || n > 200
                    ? 'Between 1 and 200'
                    : null;
              },
            ),
            const SizedBox(height: appSpaceSm),
            Text(
              'New classes of this type start with this many spots.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: appMutedText),
            ),
          ],
        ),
      ),
    );
  }
}
