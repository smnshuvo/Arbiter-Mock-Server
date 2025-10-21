import 'package:get_it/get_it.dart';

import '../../data/datasources/local/database_helper.dart';
import '../../data/datasources/local/endpoint_local_datasource.dart';
import '../../data/datasources/local/log_local_datasource.dart';
import '../../data/datasources/local/profile_local_datasource.dart';
import '../../data/datasources/server/http_server_service.dart';
import '../../data/datasources/server/server_manager.dart';
import '../../data/repositories/endpoint_repository.dart';
import '../../data/repositories/log_respository.dart';
import '../../data/repositories/profile_repository_impl.dart';
import '../../data/repositories/server_repository.dart';
import '../../domain/repositories/endpoint_repository.dart';
import '../../domain/repositories/log_repository.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/repositories/server_repository.dart';
import '../../domain/usecases/endpoint_usecases.dart';
import '../../domain/usecases/log_usecases.dart';
import '../../domain/usecases/profile_usecases.dart';
import '../../domain/usecases/server_usecases.dart';

import 'endpoint/endpoint_bloc.dart';
import 'log/log_bloc.dart';

import 'profile/profile_bloc.dart';
import 'server/server_bloc.dart'; // NEW

final sl = GetIt.instance;

Future<void> init() async {
  // ========== BLoCs ==========

  // Server BLoC (Updated - now uses new architecture)
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
    ),
  );

  // Endpoint BLoC
  sl.registerFactory(
        () => EndpointBloc(
      getAllEndpoints: sl(),
      createEndpoint: sl(),
      updateEndpoint: sl(),
      deleteEndpoint: sl(),
      importEndpoints: sl(),
      exportEndpoints: sl(),
    ),
  );

  // Log BLoC
  sl.registerFactory(
        () => LogBloc(
      getAllLogs: sl(),
      clearLogs: sl(),
      clearFilteredLogs: sl(),
      exportLogs: sl(),
    ),
  );

  // NEW - Profile BLoC
  sl.registerFactory(
        () => ProfileBloc(
      getAllProfiles: sl(),
      getProfileById: sl(),
      createProfile: sl(),
      updateProfile: sl(),
      deleteProfile: sl(),
      duplicateProfile: sl(),
      getActiveProfiles: sl(),
      exportProfile: sl(),
      importProfile: sl(),
      assignEndpointsToProfile: sl(),
      startProfileServer: sl(),
      stopProfileServer: sl(),
      stopAllServers: sl(),
      getRunningProfiles: sl(),
    ),
  );

  // ========== Use cases - Server ==========

  // Legacy server use cases
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

  // NEW - Profile-based server use cases
  sl.registerLazySingleton(() => StartProfileServer(sl()));
  sl.registerLazySingleton(() => StopProfileServer(sl()));
  sl.registerLazySingleton(() => StopAllServers(sl()));
  sl.registerLazySingleton(() => GetRunningProfiles(sl()));
  sl.registerLazySingleton(() => IsProfileServerRunning(sl()));
  sl.registerLazySingleton(() => GetServerUrlForProfile(sl()));
  sl.registerLazySingleton(() => GetRunningServerCount(sl()));
  sl.registerLazySingleton(() => IsPortAvailable(sl()));

  // ========== Use cases - Endpoint ==========

  sl.registerLazySingleton(() => GetAllEndpoints(sl()));
  sl.registerLazySingleton(() => CreateEndpoint(sl()));
  sl.registerLazySingleton(() => UpdateEndpoint(sl()));
  sl.registerLazySingleton(() => DeleteEndpoint(sl()));
  sl.registerLazySingleton(() => ImportEndpoints(sl()));
  sl.registerLazySingleton(() => ExportEndpoints(sl()));

  // ========== Use cases - Log ==========

  sl.registerLazySingleton(() => GetAllLogs(sl()));
  sl.registerLazySingleton(() => CreateLog(sl()));
  sl.registerLazySingleton(() => ClearLogs(sl()));
  sl.registerLazySingleton(() => ClearFilteredLogs(sl()));
  sl.registerLazySingleton(() => ExportLogs(sl()));

  // ========== NEW - Use cases - Profile ==========

  sl.registerLazySingleton(() => GetAllProfiles(sl()));
  sl.registerLazySingleton(() => GetProfileById(sl()));
  sl.registerLazySingleton(() => CreateProfile(sl()));
  sl.registerLazySingleton(() => UpdateProfile(sl()));
  sl.registerLazySingleton(() => DeleteProfile(sl()));
  sl.registerLazySingleton(() => DuplicateProfile(sl()));
  sl.registerLazySingleton(() => GetActiveProfiles(sl()));
  sl.registerLazySingleton(() => ExportProfile(sl()));
  sl.registerLazySingleton(() => ImportProfile(sl()));
  sl.registerLazySingleton(() => AssignEndpointsToProfile(sl()));
  sl.registerLazySingleton(() => GetEndpointsForProfile(sl()));

  // ========== Repositories ==========

  // Server Repository (Updated - now uses ServerManager)
  sl.registerLazySingleton<ServerRepository>(
        () => ServerRepositoryImpl(
      serverManager: sl(),
      profileRepository: sl(),
      endpointRepository: sl(),
    ),
  );

  // Endpoint Repository
  sl.registerLazySingleton<EndpointRepository>(
        () => EndpointRepositoryImpl(sl()),
  );

  // Log Repository
  sl.registerLazySingleton<LogRepository>(
        () => LogRepositoryImpl(sl()),
  );

  // NEW - Profile Repository
  sl.registerLazySingleton<ProfileRepository>(
        () => ProfileRepositoryImpl(sl()),
  );

  // ========== Data sources ==========

  // Endpoint Local Data Source
  sl.registerLazySingleton<EndpointLocalDataSource>(
        () => EndpointLocalDataSourceImpl(sl()),
  );

  // Log Local Data Source
  sl.registerLazySingleton<LogLocalDataSource>(
        () => LogLocalDataSourceImpl(sl()),
  );

  // NEW - Profile Local Data Source
  sl.registerLazySingleton<ProfileLocalDataSource>(
        () => ProfileLocalDataSourceImpl(sl()),
  );

  // NEW - Server Manager (replaces single HttpServerService)
  sl.registerLazySingleton(
        () => ServerManager(
      logDataSource: sl(),
    ),
  );

  // Legacy HttpServerService registration (kept for backward compatibility)
  // Note: This is now handled by ServerManager, but kept for any legacy code
  sl.registerLazySingleton(
        () => HttpServerService(
      profileId: 'legacy', // Special ID for legacy mode
      logDataSource: sl(),
      onEndpointsNeeded: () async {
        final endpoints = await sl<GetAllEndpoints>()();
        sl<HttpServerService>().updateEndpoints(endpoints);
      },
    ),
  );

  // ========== Core ==========

  // Database Helper
  sl.registerLazySingleton(() => DatabaseHelper.instance);
}