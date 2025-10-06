import 'package:get_it/get_it.dart';

import '../../data/datasources/local/database_helper.dart';
import '../../data/datasources/local/endpoint_local_datasource.dart';
import '../../data/datasources/local/log_local_datasource.dart';
import '../../data/datasources/server/http_server_service.dart';
import '../../data/repositories/endpoint_repository.dart';
import '../../data/repositories/log_respository.dart';
import '../../data/repositories/server_repository.dart';
import '../../domain/repositories/endpoint_repository.dart';
import '../../domain/repositories/log_repository.dart';
import '../../domain/repositories/server_repository.dart';
import '../../domain/usecases/endpoint_usecases.dart';
import '../../domain/usecases/log_usecases.dart';
import '../../domain/usecases/server_usecases.dart';
import 'endpoint/endpoint_bloc.dart';
import 'log/log_bloc.dart';
import 'server/server_bloc.dart';

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

  // Use cases - Server
  sl.registerLazySingleton(() => StartServer(sl()));
  sl.registerLazySingleton(() => StopServer(sl()));
  sl.registerLazySingleton(() => GetServerStatus(sl()));
  sl.registerLazySingleton(() => GetServerUrl(sl()));
  sl.registerLazySingleton(() => SetServerPort(sl()));

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

  // Repositories
  sl.registerLazySingleton<ServerRepository>(
        () => ServerRepositoryImpl(sl()),
  );

  sl.registerLazySingleton<EndpointRepository>(
        () => EndpointRepositoryImpl(sl()),
  );

  sl.registerLazySingleton<LogRepository>(
        () => LogRepositoryImpl(sl()),
  );

  // Data sources
  sl.registerLazySingleton<EndpointLocalDataSource>(
        () => EndpointLocalDataSourceImpl(sl()),
  );

  sl.registerLazySingleton<LogLocalDataSource>(
        () => LogLocalDataSourceImpl(sl()),
  );

  sl.registerLazySingleton(
        () => HttpServerService(
      logDataSource: sl(),
      onEndpointsNeeded: () async {
        final endpoints = await sl<GetAllEndpoints>()();
        sl<HttpServerService>().updateEndpoints(endpoints);
      },
    ),
  );

  // Core
  sl.registerLazySingleton(() => DatabaseHelper.instance);
}