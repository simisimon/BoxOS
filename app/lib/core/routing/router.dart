import 'package:app/features/admin_analytics/presentation/screens/admin_analytics_screen.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/application/auth_state.dart';
import 'package:app/features/auth/presentation/screens/auth_loading_screen.dart';
import 'package:app/features/auth/presentation/screens/auth_callback_screen.dart';
import 'package:app/features/auth/presentation/screens/change_password_screen.dart';
import 'package:app/features/auth/presentation/screens/delete_account_screen.dart';
import 'package:app/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:app/features/auth/presentation/screens/login_screen.dart';
import 'package:app/features/auth/presentation/screens/admin_sign_up_screen.dart';
import 'package:app/features/auth/presentation/screens/reset_password_screen.dart';
import 'package:app/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:app/features/auth/presentation/screens/verify_email_screen.dart';
import 'package:app/features/gyms/presentation/screens/create_gym_screen.dart';
import 'package:app/features/gyms/presentation/screens/gym_directory_screen.dart';
import 'package:app/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:app/features/home/presentation/screens/authenticated_shell_screen.dart';
import 'package:app/features/home/presentation/screens/home_screen.dart';
import 'package:app/features/logbook/presentation/screens/logbook_screen.dart';
import 'package:app/features/members/presentation/screens/members_screen.dart';
import 'package:app/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:app/features/profile/presentation/screens/notification_settings_screen.dart';
import 'package:app/features/profile/presentation/screens/notifications_screen.dart';
import 'package:app/features/profile/presentation/screens/profile_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);
  final authStatus = authState.value ?? AuthStatus.unknown;
  const authLoadingRoute = '/auth-loading';
  const publicRoutes = <String>{
    '/login',
    '/sign-up',
    '/admin-sign-up',
    '/owner-sign-up',
    '/verify-email',
    '/forgot-password',
    '/reset-password',
    '/auth/callback',
    authLoadingRoute,
  };

  return GoRouter(
    initialLocation: authLoadingRoute,
    redirect: (context, state) {
      final matchedRoute = state.matchedLocation;
      final isPublicRoute = publicRoutes.contains(matchedRoute);

      if (authStatus == AuthStatus.unknown) {
        return matchedRoute == authLoadingRoute ? null : authLoadingRoute;
      }

      if (authStatus == AuthStatus.authenticated && isPublicRoute) {
        return '/home';
      }

      if (authStatus == AuthStatus.unauthenticated &&
          matchedRoute == authLoadingRoute) {
        return '/login';
      }

      if (authStatus == AuthStatus.unauthenticated && !isPublicRoute) {
        return '/login';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: authLoadingRoute,
        name: 'auth-loading',
        builder: (context, state) => const AuthLoadingScreen(),
      ),
      GoRoute(
        path: '/auth/callback',
        name: 'auth-callback',
        builder: (context, state) => AuthCallbackScreen(
          type: state.uri.queryParameters['type'],
          tokenHash: state.uri.queryParameters['token_hash'],
          errorDescription: state.uri.queryParameters['error_description'],
        ),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AuthenticatedShellScreen(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/my-box',
                name: 'my-box',
                builder: (context, state) => const MyBoxScreen(),
              ),
              GoRoute(
                path: '/calendar',
                redirect: (context, state) => '/my-box',
              ),
              GoRoute(
                path: '/programming',
                redirect: (context, state) => '/my-box',
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/logbook',
                name: 'logbook',
                builder: (context, state) => const LogbookScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/members',
                name: 'members',
                builder: (context, state) => const MembersScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: 'profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/edit-profile',
        name: 'edit-profile',
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/notification-settings',
        name: 'notification-settings',
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      // Legacy alias. The Members surface now lives at /members (sidebar tab);
      // any in-app links or bookmarks to /role-management land on the same
      // page without a 404.
      GoRoute(
        path: '/role-management',
        redirect: (context, state) => '/members',
      ),
      GoRoute(
        path: '/admin-analytics',
        name: 'admin-analytics',
        builder: (context, state) => const AdminAnalyticsScreen(),
      ),
      GoRoute(
        path: '/change-password',
        name: 'change-password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/delete-account',
        name: 'delete-account',
        builder: (context, state) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        name: 'sign-up',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: '/admin-sign-up',
        name: 'admin-sign-up',
        builder: (context, state) => const AdminSignUpScreen(),
      ),
      GoRoute(
        path: '/owner-sign-up',
        redirect: (context, state) => '/admin-sign-up',
      ),
      GoRoute(
        path: '/verify-email',
        name: 'verify-email',
        builder: (context, state) =>
            VerifyEmailScreen(initialEmail: state.uri.queryParameters['email']),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        name: 'reset-password',
        builder: (context, state) => ResetPasswordScreen(
          initialToken: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        path: '/create-gym',
        name: 'create-gym',
        builder: (context, state) => const CreateGymScreen(),
      ),
      GoRoute(
        path: '/gyms',
        name: 'gyms',
        builder: (context, state) => const GymDirectoryScreen(),
      ),
      // Legacy alias. Join requests now live at the top of /members.
      GoRoute(
        path: '/gym-requests',
        redirect: (context, state) => '/members',
      ),
    ],
  );
});
