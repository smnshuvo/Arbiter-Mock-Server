import 'package:arbiter_mock_server/core/theme/app_theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/theme_cubit.dart';
import 'ui/bloc/dependency_container.dart' as di;
import 'ui/bloc/endpoint/endpoint_bloc.dart';
import 'ui/bloc/interception/interception_bloc.dart';
import 'ui/bloc/log/log_bloc.dart';
import 'ui/bloc/server/server_bloc.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/welcome_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await di.init();
  runApp(
      BlocProvider(create: (_) => di.sl<ThemeCubit>(), child: const MyApp()));
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
        BlocProvider(create: (_) => di.sl<InterceptionBloc>())
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp(
            title: 'Network Interceptor',
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
