import 'package:get_it/get_it.dart';

import '../../data/datasources/local/database_helper.dart';
import '../../data/datasources/local/endpoint_local_datasource.dart';
import '../../data/datasources/local/log_local_datasource.dart';
import '../../data/datasources/server/http_server_service.dart';
import '../../data/datasources/server/interception_manager.dart';
import '../../data/repositories/endpoint_repository.dart';
import '../../data/repositories/log_respository.dart';
import '../../data/repositories/interception_repository_impl.dart';
import '../../data/repositories/server_repository_impl.dart';
import '../../domain/repositories/endpoint_repository.dart';
import '../../domain/repositories/log_repository.dart';
import '../../domain/repositories/server_repository.dart';
import '../../domain/repositories/interception_repository.dart';
import '../../domain/usecases/endpoint_usecases.dart';
import '../../domain/usecases/log_usecases.dart';
import '../../domain/usecases/server_usecases.dart';
import '../../domain/usecases/interception_usecases.dart';
import 'endpoint/endpoint_bloc.dart';
import 'log/log_bloc.dart';
import 'server/server_bloc.dart';
import 'interception/interception_bloc.dart';

final sl = GetIt.instance;

Future<void> init() async {
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
    ),
  );

  sl.registerFactory(
        () => LogBloc(
      getAllLogs: sl(),
      clearLogs: sl(),
      clearFilteredLogs: sl(),
      exportLogs: sl(),
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

  // Use cases - Endpoint
  sl.registerLazySingleton(() => GetAllEndpoints(sl()));
  sl.registerLazySingleton(() => CreateEndpoint(sl()));
  sl.registerLazySingleton(() => UpdateEndpoint(sl()));
  sl.registerLazySingleton(() => DeleteEndpoint(sl()));
  sl.registerLazySingleton(() => ImportEndpoints(sl()));
  sl.registerLazySingleton(() => ExportEndpoints(sl()));

  // Use cases - Log
  sl.registerLazySingleton(() => GetAllLogs(sl()));
  sl.registerLazySingleton(() => CreateLog(sl()));
  sl.registerLazySingleton(() => ClearLogs(sl()));
  sl.registerLazySingleton(() => ClearFilteredLogs(sl()));
  sl.registerLazySingleton(() => ExportLogs(sl()));

  // Use cases - Interception
  sl.registerLazySingleton(() => WatchPendingInterceptions(sl()));
  sl.registerLazySingleton(() => ModifyAndContinue(sl()));
  sl.registerLazySingleton(() => ContinueWithoutModification(sl()));
  sl.registerLazySingleton(() => CancelInterception(sl()));
  sl.registerLazySingleton(() => SetInterceptionMode(sl()));
  sl.registerLazySingleton(() => GetInterceptionMode(sl()));
  sl.registerLazySingleton(() => SetInterceptionTimeout(sl()));
  sl.registerLazySingleton(() => GetInterceptionTimeout(sl()));

  // Repositories
  sl.registerLazySingleton<ServerRepository>(
        () => ServerRepositoryImpl(sl(), sl()),
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

  // Data sources
  sl.registerLazySingleton<EndpointLocalDataSource>(
        () => EndpointLocalDataSourceImpl(sl()),
  );

  sl.registerLazySingleton<LogLocalDataSource>(
        () => LogLocalDataSourceImpl(sl()),
  );

  sl.registerLazySingleton(
        () => InterceptionManager(),
  );

  sl.registerLazySingleton(
        () => HttpServerService(
      logDataSource: sl(),
      interceptionManager: sl(),
      onEndpointsNeeded: () async {
        final endpoints = await sl<GetAllEndpoints>()();
        sl<HttpServerService>().updateEndpoints(endpoints);
      },
    ),
  );

  // Core
  sl.registerLazySingleton(() => DatabaseHelper.instance);
}