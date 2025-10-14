import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'ui/bloc/dependency_container.dart' as di;
import 'ui/bloc/endpoint/endpoint_bloc.dart';
import 'ui/bloc/log/log_bloc.dart';
import 'ui/bloc/server/server_bloc.dart';
import 'ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await di.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => di.sl<ServerBloc>()),
        BlocProvider(create: (_) => di.sl<EndpointBloc>()),
        BlocProvider(create: (_) => di.sl<LogBloc>()),
      ],
      child: MaterialApp(
        title: 'Network Interceptor',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 2,
          ),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}