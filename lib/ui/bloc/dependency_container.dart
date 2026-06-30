import 'package:arbiter_mock_server/core/theme/theme_cubit.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/foreground_service.dart';
import '../../core/services/server_manager.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../data/datasources/local/endpoint_local_datasource.dart';
import '../../data/datasources/local/log_local_datasource.dart';
import '../../data/datasources/local/profile_local_datasource.dart';
import '../../data/datasources/server/interception_manager.dart';
import '../../data/repositories/endpoint_repository.dart';
import '../../data/repositories/log_respository.dart';
import '../../data/repositories/interception_repository_impl.dart';
import '../../data/repositories/profile_repository_impl.dart';
import '../../data/repositories/server_repository_impl.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/repositories/endpoint_repository.dart';
import '../../domain/repositories/log_repository.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/repositories/server_repository.dart';
import '../../domain/repositories/interception_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/entities/request_log.dart';
import '../../domain/usecases/endpoint_usecases.dart';
import '../../domain/usecases/log_usecases.dart';
import '../../domain/usecases/profile_usecases.dart';
import '../../domain/usecases/server_usecases.dart';
import '../../domain/usecases/interception_usecases.dart';
import '../../domain/usecases/foreground_service_usecases.dart';
import 'endpoint/endpoint_bloc.dart';
import 'log/log_bloc.dart';
import 'profile/profile_bloc.dart';
import 'server/server_bloc.dart';
import 'interception/interception_bloc.dart';
import 'settings/settings_bloc.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // Core - Initialize SharedPreferences FIRST and await it
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerSingleton(sharedPreferences);

  // BLoCs
  sl.registerFactory(
        () => ServerBloc(
      startServer: sl(),
      stopServer: sl(),
      getServerStatus: sl(),
      getServerUrl: sl(),
      setServerPort: sl(),
      setGlobalPassThroughUrl: sl(),
      getGlobalPassThroughUrl: sl(),
      setAutoPassThrough: sl(),
      getAutoPassThrough: sl(),
      setUseDeviceIp: sl(),
      getUseDeviceIp: sl(),
      getDeviceIpAddress: sl(),
      startProfile: sl(),
      stopProfile: sl(),
      stopAllProfiles: sl(),
      getRunningServers: sl(),
    ),
  );

  sl.registerFactory(
        () => EndpointBloc(
      getAllEndpoints: sl(),
      createEndpoint: sl(),
      updateEndpoint: sl(),
      deleteEndpoint: sl(),
      importEndpoints: sl(),
      exportEndpoints: sl(),
      toggleAllEndpoints: sl(),
      batchCreateEndpointsFromLogs: sl(),
    ),
  );

  sl.registerFactory(
        () => LogBloc(
      getAllLogs: sl(),
      clearLogs: sl(),
      clearFilteredLogs: sl(),
      exportLogs: sl(),
      watchNewLogs: sl(),
    ),
  );

  sl.registerFactory(
        () => InterceptionBloc(
      watchPendingInterceptions: sl(),
      modifyAndContinue: sl(),
      continueWithoutModification: sl(),
      cancelInterception: sl(),
      setInterceptionMode: sl(),
      getInterceptionMode: sl(),
      setInterceptionTimeout: sl(),
      getInterceptionTimeout: sl(),
    ),
  );

  sl.registerFactory(() => SettingsBloc(sl()));

  sl.registerFactory(
        () => ProfileBloc(
      getAllProfiles: sl(),
      createProfile: sl(),
      updateProfile: sl(),
      deleteProfile: sl(),
      getActiveProfileId: sl(),
      setActiveProfileId: sl(),
    ),
  );

  // Use cases - Server
  sl.registerLazySingleton(() => StartServer(sl()));
  sl.registerLazySingleton(() => StopServer(sl()));
  sl.registerLazySingleton(() => GetServerStatus(sl()));
  sl.registerLazySingleton(() => GetServerUrl(sl()));
  sl.registerLazySingleton(() => SetServerPort(sl()));
  sl.registerLazySingleton(() => SetGlobalPassThroughUrl(sl()));
  sl.registerLazySingleton(() => GetGlobalPassThroughUrl(sl()));
  sl.registerLazySingleton(() => SetAutoPassThrough(sl()));
  sl.registerLazySingleton(() => GetAutoPassThrough(sl()));
  sl.registerLazySingleton(() => SetUseDeviceIp(sl()));
  sl.registerLazySingleton(() => GetUseDeviceIp(sl()));
  sl.registerLazySingleton(() => GetDeviceIpAddress(sl()));
  sl.registerLazySingleton(() => SetServerInterceptionEnabled(sl()));
  sl.registerLazySingleton(() => GetServerInterceptionEnabled(sl()));
  sl.registerLazySingleton(() => SetServerInterceptionMode(sl()));
  sl.registerLazySingleton(() => GetServerInterceptionMode(sl()));
  sl.registerLazySingleton(() => StartProfile(sl()));
  sl.registerLazySingleton(() => StopProfile(sl()));
  sl.registerLazySingleton(() => StopAllProfiles(sl()));
  sl.registerLazySingleton(() => GetRunningServers(sl()));
  sl.registerLazySingleton(() => IsProfileRunning(sl()));

  // Use cases - Endpoint
  sl.registerLazySingleton(() => GetAllEndpoints(sl()));
  sl.registerLazySingleton(() => CreateEndpoint(sl()));
  sl.registerLazySingleton(() => UpdateEndpoint(sl()));
  sl.registerLazySingleton(() => DeleteEndpoint(sl()));
  sl.registerLazySingleton(() => ImportEndpoints(sl()));
  sl.registerLazySingleton(() => ExportEndpoints(sl()));
  sl.registerLazySingleton(() => ToggleAllEndpoints(sl()));
  sl.registerLazySingleton(() => BatchCreateEndpointsFromLogs(sl()));

  // Use cases - Log
  sl.registerLazySingleton(() => GetAllLogs(sl()));
  sl.registerLazySingleton(() => CreateLog(sl()));
  sl.registerLazySingleton(() => ClearLogs(sl()));
  sl.registerLazySingleton(() => ClearFilteredLogs(sl()));
  sl.registerLazySingleton(() => ExportLogs(sl()));
  sl.registerLazySingleton(() => WatchNewLogs(sl()));

  // Use cases - Interception
  sl.registerLazySingleton(() => WatchPendingInterceptions(sl()));
  sl.registerLazySingleton(() => ModifyAndContinue(sl()));
  sl.registerLazySingleton(() => ContinueWithoutModification(sl()));
  sl.registerLazySingleton(() => CancelInterception(sl()));
  sl.registerLazySingleton(() => SetInterceptionMode(sl()));
  sl.registerLazySingleton(() => GetInterceptionMode(sl()));
  sl.registerLazySingleton(() => SetInterceptionTimeout(sl()));
  sl.registerLazySingleton(() => GetInterceptionTimeout(sl()));

  // Use cases - Profile
  sl.registerLazySingleton(() => GetAllProfiles(sl()));
  sl.registerLazySingleton(() => GetProfileById(sl()));
  sl.registerLazySingleton(() => CreateProfile(sl()));
  sl.registerLazySingleton(() => UpdateProfile(sl()));
  sl.registerLazySingleton(() => DeleteProfile(sl()));
  sl.registerLazySingleton(() => GetActiveProfileId(sl()));
  sl.registerLazySingleton(() => SetActiveProfileId(sl()));

  // Repositories
  sl.registerLazySingleton<ServerRepository>(
        () => ServerRepositoryImpl(sl(), sl(), sl()),
  );

  sl.registerLazySingleton<EndpointRepository>(
        () => EndpointRepositoryImpl(sl()),
  );

  sl.registerLazySingleton<LogRepository>(
        () => LogRepositoryImpl(sl()),
  );

  sl.registerLazySingleton<InterceptionRepository>(
        () => InterceptionRepositoryImpl(sl()),
  );

  sl.registerLazySingleton<SettingsRepository>(
        () => SettingsRepositoryImpl(sl()),
  );

  sl.registerLazySingleton<ProfileRepository>(
        () => ProfileRepositoryImpl(sl(), sl()),
  );

  // Data sources
  sl.registerLazySingleton<EndpointLocalDataSource>(
        () => EndpointLocalDataSourceImpl(sl()),
  );

  sl.registerLazySingleton<LogLocalDataSource>(
        () => LogLocalDataSourceImpl(sl()),
  );

  sl.registerLazySingleton<ProfileLocalDataSource>(
        () => ProfileLocalDataSourceImpl(sl()),
  );

  sl.registerLazySingleton(
        () => InterceptionManager(),
  );

  sl.registerLazySingleton(
        () => ServerManager(
      logDataSource: sl(),
      interceptionManager: sl(),
      onEndpointsNeeded: (profileId) async {
        final endpoints = await sl<GetAllEndpoints>()(profileId: profileId);
        return endpoints;
      },
      onRequestReceived: null, // Will be set after all dependencies are registered
    ),
  );

  // Core
  sl.registerLazySingleton(() => DatabaseHelper.instance);
  sl.registerLazySingleton(() => ForegroundService());
  sl.registerLazySingleton(() => ThemeCubit());

  // Use cases - Foreground Service
  sl.registerLazySingleton(() => StartForegroundService(sl()));
  sl.registerLazySingleton(() => StopForegroundService(sl()));
  sl.registerLazySingleton(() => UpdateForegroundServiceNotification(sl()));
}

// Feed the Android Live Activity notification with the live request log feed.
// Set up after all dependencies are registered. The native side keeps only the
// latest few rows and tracks running totals, so this fire-and-forget subscription
// stays lightweight on the request hot path.
Future<void> setupRequestNotificationCallback() async {
  final foregroundService = sl<ForegroundService>();
  sl<WatchNewLogs>()().listen((log) async {
    try {
      final settings = await sl<SettingsRepository>().getSettings();
      if (!settings.showEndpointHitsInNotifications) return;
      await foregroundService.pushLog(
        method: log.method.name,
        path: log.url,
        statusCode: log.statusCode,
      );
    } catch (_) {
      // Silently handle errors in the notification feed.
    }
  });
}
