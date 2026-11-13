import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/members/domain/member_booking.dart';
import 'package:app/features/members/presentation/widgets/booking_table.dart';
import 'package:app/features/memberships/data/membership_repository.dart';
import 'package:app/features/memberships/presentation/my_membership_card.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/gym_membership.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Profile sub views, picked with `/profile?section=`. Athletes get all three;
/// owners and trainers only [account] (trainers are never limited by a plan,
/// owners manage plans in Settings).
enum ProfileSection {
  account('account', 'Account'),
  membership('membership', 'Membership'),
  bookings('bookings', 'Bookings');

  const ProfileSection(this.slug, this.label);

  final String slug;
  final String label;

  static ProfileSection fromSlug(String? slug) => values.firstWhere(
    (section) => section.slug == slug,
    orElse: () => account,
  );
}

/// Profile page in the admin layout (docs/admin-ui-reference.md §0, §4.2's
/// header card, §12's grouped cards): a header card with the person, then
/// the sub views as a segmented control.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, this.section = ProfileSection.account});

  final ProfileSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).value;
    final displayName = (profile?.displayName ?? '').isEmpty
        ? (profile?.role.label ?? 'Athlete')
        : profile!.displayName;
    final sections =
        profile?.role == UserRole.athlete && profile?.activeGym != null
        ? ProfileSection.values
        : const [ProfileSection.account];
    final current = sections.contains(section) ? section : sections.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        appSpaceLg,
        appSpaceLg,
        appSpaceLg,
        appSpace3xl,
      ),
      children: [
        _ProfileHeader(
          displayName: displayName,
          nickname: profile?.nickname,
          email: profile?.email,
          roleLabel: profile?.role.label ?? 'Athlete',
          gymName: profile?.activeGym?.name,
          profileImageUrl: profile?.profileImageUrl ?? '',
        ),
        if (sections.length > 1) ...[
          const SizedBox(height: appSpaceLg),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<ProfileSection>(
              showSelectedIcon: false,
              segments: [
                for (final s in sections)
                  ButtonSegment(value: s, label: Text(s.label)),
              ],
              selected: {current},
              onSelectionChanged: (selected) =>
                  context.go('/profile?section=${selected.first.slug}'),
            ),
          ),
        ],
        const SizedBox(height: appSpaceLg),
        switch (current) {
          ProfileSection.account => const _AccountSection(),
          ProfileSection.membership => const MyMembershipCard(),
          ProfileSection.bookings => const MyBookingsSection(),
        },
      ],
    );
  }
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: appSurface,
  borderRadius: BorderRadius.circular(appRadiusLg),
  border: Border.all(color: appBorder),
);

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.nickname,
    required this.email,
    required this.roleLabel,
    required this.gymName,
    required this.profileImageUrl,
  });

  final String displayName;
  final String? nickname;
  final String? email;
  final String roleLabel;
  final String? gymName;
  final String profileImageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(appSpaceLg),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          AppAvatar(
            displayName: displayName,
            imageUrl: profileImageUrl.isEmpty ? null : profileImageUrl,
            size: 56,
          ),
          const SizedBox(width: appSpaceLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: appSpaceSm,
                  runSpacing: appSpaceXs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: appText,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    AppPill(
                      label: roleLabel,
                      intent: AppPillIntent.primary,
                      dense: true,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if ((nickname ?? '').isNotEmpty) '@$nickname',
                    email ?? '',
                    gymName ?? 'No box selected',
                  ].where((part) => part.isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: appMutedText, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Account: grouped cards of settings rows, two columns on wide screens.
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(authControllerProvider).isLoading;
    final profile = ref.watch(currentProfileProvider).value;
    final memberships = profile?.memberships ?? const <GymMembership>[];

    final account = _SettingsCard(
      title: 'Account',
      rows: [
        _SettingsRow(
          icon: Icons.edit_outlined,
          title: 'Edit profile',
          subtitle: 'Name, nickname and photo',
          enabled: !isLoading,
          onTap: () => context.go('/edit-profile'),
        ),
        if (profile?.accountType == AccountType.admin &&
            profile?.activeGym == null)
          _SettingsRow(
            icon: Icons.storefront_outlined,
            title: 'Create box',
            subtitle: 'Set up your box so members can join',
            enabled: !isLoading,
            onTap: () => context.go('/create-gym'),
          )
        else
          _SettingsRow(
            icon: Icons.search_outlined,
            title: 'Find a box',
            subtitle: 'Browse boxes and send a join request',
            enabled: !isLoading,
            onTap: () => context.go('/gyms'),
          ),
      ],
    );
    final security = _SettingsCard(
      title: 'Preferences & security',
      rows: [
        _SettingsRow(
          icon: Icons.notifications_outlined,
          title: 'Notification settings',
          subtitle: 'Bookings, waiting list, WODs and payments',
          enabled: !isLoading,
          onTap: () => context.go('/notification-settings'),
        ),
        _SettingsRow(
          icon: Icons.lock_outline,
          title: 'Change password',
          subtitle: 'Keep your account secure',
          enabled: !isLoading,
          onTap: () => context.go('/change-password'),
        ),
        _SettingsRow(
          icon: Icons.logout,
          title: 'Sign out',
          subtitle: 'Leave this session on this device',
          enabled: !isLoading,
          onTap: () => ref.read(authControllerProvider.notifier).signOut(),
        ),
        _SettingsRow(
          icon: Icons.delete_outline,
          title: 'Delete account',
          subtitle: 'Permanently remove your BoxOS account',
          enabled: !isLoading,
          destructive: true,
          onTap: () => context.go('/delete-account'),
        ),
      ],
    );
    final boxes = memberships.isEmpty
        ? null
        : _SettingsCard(
            title: 'Boxes',
            rows: [
              for (final membership in memberships)
                _BoxRow(
                  membership: membership,
                  isCurrent: profile?.activeGym?.id == membership.gym.id,
                  enabled: !isLoading,
                  onSwitch: () => _switchGym(context, ref, membership.gym.id),
                ),
            ],
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 840) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              account,
              const SizedBox(height: appSpaceLg),
              security,
              if (boxes != null) ...[const SizedBox(height: appSpaceLg), boxes],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  account,
                  if (boxes != null) ...[
                    const SizedBox(height: appSpaceLg),
                    boxes,
                  ],
                ],
              ),
            ),
            const SizedBox(width: appSpaceLg),
            Expanded(child: security),
          ],
        );
      },
    );
  }

  static Future<void> _switchGym(
    BuildContext context,
    WidgetRef ref,
    int gymId,
  ) async {
    try {
      await ref.read(profileRepositoryProvider).updateActiveGym(gymId: gymId);
      ref.invalidate(currentProfileProvider);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to switch box.')));
    }
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    // Material so the rows' ink works wherever the page is shown.
    return Material(
      color: appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(appRadiusLg),
        side: const BorderSide(color: appBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              appSpaceLg,
              appSpaceLg,
              appSpaceLg,
              appSpaceSm,
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: appText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final row in rows) ...[
            const Divider(height: 1, color: appBorder),
            row,
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: appSpaceLg,
          vertical: appSpaceMd,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: destructive ? appDanger : appMutedText),
            const SizedBox(width: appSpaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: destructive ? appDanger : appText,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: appSubtleText,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: appSubtleText),
          ],
        ),
      ),
    );
  }
}

class _BoxRow extends StatelessWidget {
  const _BoxRow({
    required this.membership,
    required this.isCurrent,
    required this.enabled,
    required this.onSwitch,
  });

  final GymMembership membership;
  final bool isCurrent;
  final bool enabled;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: appSpaceLg,
        vertical: appSpaceMd,
      ),
      child: Row(
        children: [
          AppAvatar(displayName: membership.gym.name, size: 32),
          const SizedBox(width: appSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  membership.gym.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: appText,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${membership.role.label} · ${membership.gym.timezone}',
                  style: const TextStyle(color: appSubtleText, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (isCurrent)
            const AppPill(
              label: 'Current',
              intent: AppPillIntent.primary,
              dense: true,
            )
          else
            TextButton(
              onPressed: enabled ? onSwitch : null,
              child: const Text('Switch'),
            ),
        ],
      ),
    );
  }
}

/// Profile › Bookings: every booking of the athlete at the active box,
/// in Upcoming (booked and waiting list, with Cancel), Past and Cancelled.
class MyBookingsSection extends ConsumerStatefulWidget {
  const MyBookingsSection({super.key});

  @override
  ConsumerState<MyBookingsSection> createState() => _MyBookingsSectionState();
}

enum _BookingsView { upcoming, past, cancelled }

class _MyBookingsSectionState extends ConsumerState<MyBookingsSection> {
  _BookingsView _view = _BookingsView.upcoming;

  Future<void> _cancel(MemberBooking booking) async {
    final waitlist = booking.status == 'waitlist';
    final confirmed = await showAppConfirmDialog(
      context,
      title: waitlist ? 'Leave the waiting list?' : 'Cancel booking?',
      message: waitlist
          ? 'You leave the waiting list for ${booking.title}.'
          : 'Your spot in ${booking.title} is given back.',
      confirmLabel: waitlist ? 'Leave' : 'Cancel booking',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repository = ref.read(scheduleRepositoryProvider);
      if (waitlist) {
        await repository.leaveWaitlist(classId: booking.classId);
      } else {
        await repository.cancelBooking(classId: booking.classId);
      }
      ref.invalidate(myBookingsProvider);
      ref.invalidate(scheduleListProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            waitlist ? 'Removed from the waiting list.' : 'Booking cancelled.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Could not cancel the booking'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(myBookingsProvider);
    return Container(
      padding: const EdgeInsets.all(appSpaceLg),
      decoration: _cardDecoration(),
      child: bookings.when(
        loading: () => const AppLoadingState(height: 160),
        error: (error, _) => AppEmptyState.error(
          title: 'Could not load your bookings',
          subtitle: errorMessageFrom(error, fallback: 'Try again'),
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(myBookingsProvider),
        ),
        data: (all) {
          final now = DateTime.now();
          // The server lists the newest class first; upcoming reads soonest
          // first.
          final upcoming = [
            for (final b in all.reversed)
              if (!b.isCancelled && b.end.isAfter(now)) b,
          ];
          final past = [
            for (final b in all)
              if (!b.isCancelled && !b.end.isAfter(now)) b,
          ];
          final cancelled = [
            for (final b in all)
              if (b.isCancelled) b,
          ];
          final (rows, empty) = switch (_view) {
            _BookingsView.upcoming => (upcoming, 'No upcoming classes booked.'),
            _BookingsView.past => (past, 'No past classes yet.'),
            _BookingsView.cancelled => (cancelled, 'No cancelled bookings.'),
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<_BookingsView>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: _BookingsView.upcoming,
                      label: Text('Upcoming ${upcoming.length}'),
                    ),
                    ButtonSegment(
                      value: _BookingsView.past,
                      label: Text('Past ${past.length}'),
                    ),
                    ButtonSegment(
                      value: _BookingsView.cancelled,
                      label: Text('Cancelled ${cancelled.length}'),
                    ),
                  ],
                  selected: {_view},
                  onSelectionChanged: (s) => setState(() => _view = s.first),
                ),
              ),
              const SizedBox(height: appSpaceMd),
              BookingTable(
                rows: rows,
                emptyText: empty,
                shrinkWrap: true,
                onCancel: _view == _BookingsView.upcoming ? _cancel : null,
              ),
            ],
          );
        },
      ),
    );
  }
}
