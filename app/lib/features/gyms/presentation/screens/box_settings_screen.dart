import 'dart:typed_data';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/memberships/presentation/membership_plans_panel.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

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

enum _SettingsSection {
  identity,
  scheduling,
  memberships,
  notifications,
  danger,
}

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
        Text(
          'Box settings',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: appText,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: appSpaceLg),
        _SectionNav(
          selected: _section,
          onSelected: (section) => setState(() => _section = section),
        ),
        const SizedBox(height: appSpace2xl),
        _buildPanel(profile!.activeGym!),
      ],
    );
  }

  Widget _buildPanel(GymSummary gym) {
    switch (_section) {
      case _SettingsSection.identity:
        return _IdentityPanel(
          // Rebuild the form from the server values after each save.
          key: ValueKey('${gym.id}|${gym.name}|${gym.logoUrl}|${gym.timezone}'),
          gym: gym,
        );
      case _SettingsSection.scheduling:
        return _SchedulingPanel(
          bookingWindowDays: _bookingWindowDays,
          cancelCutoffHours: _cancelCutoffHours,
          waitlistAutoPromote: _waitlistAutoPromote,
          classTypes: _classTypes,
          onBookingWindowChanged: (v) => setState(() => _bookingWindowDays = v),
          onCancelCutoffChanged: (v) => setState(() => _cancelCutoffHours = v),
          onWaitlistAutoPromoteChanged: (v) =>
              setState(() => _waitlistAutoPromote = v),
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
        return const MembershipPlansPanel();
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
    (_SettingsSection.memberships, 'Memberships', false),
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
    required this.classTypes,
    required this.onBookingWindowChanged,
    required this.onCancelCutoffChanged,
    required this.onWaitlistAutoPromoteChanged,
    required this.onAddClassType,
    required this.onRemoveClassType,
    required this.onSave,
  });

  final int bookingWindowDays;
  final int cancelCutoffHours;
  final bool waitlistAutoPromote;
  final List<_ClassType> classTypes;
  final ValueChanged<int> onBookingWindowChanged;
  final ValueChanged<int> onCancelCutoffChanged;
  final ValueChanged<bool> onWaitlistAutoPromoteChanged;
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
            ],
          ),
        ),
        const SizedBox(height: appSpaceLg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CLASS TYPES & DEFAULT CAPACITY',
                style: appMono(fontSize: 10, letterSpacing: 1.4),
              ),
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
          Text(
            type.name,
            style: const TextStyle(
              color: appText,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '·${type.capacity}',
            style: appMono(fontSize: 11, letterSpacing: 0, color: appPrimary),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(appRadiusPill),
            child: const Icon(
              Icons.close_rounded,
              size: 15,
              color: appSubtleText,
            ),
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
              Text(
                'Add type',
                style: const TextStyle(
                  color: appPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
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
          Text(
            'NEW CLASS TYPE',
            style: appMono(fontSize: 10, letterSpacing: 1.4),
          ),
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
