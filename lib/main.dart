import 'dart:async';
import 'dart:io' show Platform;

import 'package:arbiter_mock_server/core/ads/ad_service.dart';
import 'package:arbiter_mock_server/core/theme/app_theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/services/json_document_service.dart';
import 'core/theme/theme_cubit.dart';
import 'ui/bloc/dependency_container.dart' as di;
import 'ui/screens/json_docs/android_json_editor_screen.dart';
import 'ui/screens/json_docs/json_docs_controller.dart';
import 'ui/screens/json_docs/json_docs_screen.dart';
import 'ui/bloc/endpoint/endpoint_bloc.dart';
import 'ui/bloc/interception/interception_bloc.dart';
import 'ui/bloc/log/log_bloc.dart';
import 'ui/bloc/profile/profile_bloc.dart';
import 'ui/bloc/server/server_bloc.dart';
import 'ui/bloc/settings/settings_bloc.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/welcome_screen.dart';

/// Navigator key so the .json document window can be pushed from outside the
/// widget tree (launch-time and runtime file-open events).
final rootNavigatorKey = GlobalKey<NavigatorState>();

bool _jsonDocsRouteOpen = false;

void _showJsonDocs() {
  final nav = rootNavigatorKey.currentState;
  if (nav == null || _jsonDocsRouteOpen) return;
  _jsonDocsRouteOpen = true;
  // Android uses a slim single-document editor (RAM-light); macOS a tabbed window.
  final Widget screen = Platform.isAndroid
      ? const AndroidJsonEditorScreen()
      : const JsonDocsScreen();
  nav
      .push(MaterialPageRoute(builder: (_) => screen))
      .then((_) => _jsonDocsRouteOpen = false);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await di.init();
  await di.setupRequestNotificationCallback(); // Setup notification callback after all dependencies are ready
  unawaited(di.sl<AdService>().init()); // Initialize the Mobile Ads SDK (no-op on desktop)

  // macOS/Android: open .json files in a tabbed document window (no-op elsewhere).
  final jsonDocs = JsonDocsController.instance;
  jsonDocs.singleDocument = Platform.isAndroid;
  JsonDocumentService.instance.initialize();
  final pending = await JsonDocumentService.instance.getPending();
  // Not awaited: the doc window shows an "Opening file" loader while reading.
  for (final path in pending) {
    jsonDocs.openPath(path);
  }
  JsonDocumentService.instance.onFilesOpened = (paths) {
    for (final path in paths) {
      jsonDocs.openPath(path);
    }
    _showJsonDocs();
  };

  runApp(
      BlocProvider(create: (_) => di.sl<ThemeCubit>(), child: const MyApp()));

  // If the app was launched by opening .json file(s), show the doc window.
  if (pending.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _showJsonDocs());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<bool> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hasSeenWelcome') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => di.sl<ServerBloc>()),
        BlocProvider(create: (_) => di.sl<EndpointBloc>()),
        BlocProvider(create: (_) => di.sl<LogBloc>()),
        BlocProvider(create: (_) => di.sl<InterceptionBloc>()),
        BlocProvider(create: (_) => di.sl<SettingsBloc>()),
        BlocProvider(create: (_) => di.sl<ProfileBloc>()..add(LoadProfilesEvent())),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp(
            title: 'Arbiter File Server',
            navigatorKey: rootNavigatorKey,
            debugShowCheckedModeBanner: false,
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: themeMode,
            home: FutureBuilder<bool>(
              future: _checkFirstLaunch(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final hasSeenWelcome = snapshot.data ?? false;
                return hasSeenWelcome
                    ? const HomeScreen()
                    : const WelcomeScreen();
              },
            ),
            routes: {
              '/home': (context) => const HomeScreen(),
              '/welcome': (context) => const WelcomeScreen(),
            },
          );
        },
      ),
    );
  }
}
