import 'package:arbiter_mock_server/domain/entities/endpoint.dart';
import 'package:arbiter_mock_server/domain/entities/profile.dart';
import 'package:arbiter_mock_server/ui/bloc/endpoint/endpoint_bloc.dart';
import 'package:arbiter_mock_server/ui/bloc/profile/profile_bloc.dart';
import 'package:arbiter_mock_server/ui/bloc/server/server_bloc.dart';
import 'package:arbiter_mock_server/ui/screens/desktop/desktop_endpoints_pane.dart';
import 'package:arbiter_mock_server/ui/screens/mobile/mobile_endpoints_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Regression tests for opening the *wrong server's* endpoints.
///
/// Two independent defects produced the same symptom — tapping a server card
/// landed on another server's endpoint list, most visibly right after adding
/// or deleting a server:
///
///  1. [MobileEndpointsScreen] resolved its own server from `ProfileBloc`'s
///     active profile. Callers dispatch `SwitchActiveProfileEvent` immediately
///     before pushing it, but that handler is async, so the active id in state
///     was still the *previous* one when `initState` ran.
///  2. [DesktopEndpointsPane] rendered whatever `EndpointBloc` last loaded
///     without checking which profile it belonged to, so the previous server's
///     endpoints stayed on screen while the new load was in flight.
void main() {
  setUpAll(() {
    // Tests have no network; keep google_fonts from attempting a fetch.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Profile profile(String id, String name) => Profile(
        id: id,
        name: name,
        settings: const ProfileSettings(),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  Endpoint endpoint(String id, String profileId, String pattern) => Endpoint(
        id: id,
        profileId: profileId,
        pattern: pattern,
        matchType: MatchType.exact,
        mode: EndpointMode.mock,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  Widget host({
    required Widget child,
    required FakeEndpointBloc endpoints,
    required ProfileState profileState,
  }) =>
      MultiBlocProvider(
        providers: [
          BlocProvider<EndpointBloc>.value(value: endpoints),
          BlocProvider<ProfileBloc>.value(value: FakeProfileBloc(profileState)),
          BlocProvider<ServerBloc>.value(value: FakeServerBloc()),
        ],
        child: MaterialApp(home: child),
      );

  group('MobileEndpointsScreen loads the server it was handed', () {
    testWidgets('ignores a stale active profile from ProfileBloc', (tester) async {
      final endpoints = FakeEndpointBloc();
      // The active profile still points at "alpha" — the switch to "beta"
      // hasn't been processed yet. The screen must not read this.
      await tester.pumpWidget(host(
        endpoints: endpoints,
        profileState: ProfileLoaded(
          [profile('alpha', 'Alpha'), profile('beta', 'Beta')],
          'alpha',
        ),
        child: const MobileEndpointsScreen(profileId: 'beta'),
      ));

      expect(endpoints.loadedProfileIds, ['beta']);
      expect(find.text('Beta'), findsOneWidget, reason: 'app bar names the server opened');
      expect(find.text('Alpha'), findsNothing);
    });

    testWidgets('opens a freshly created server, not the one still active',
        (tester) async {
      // Creating a profile emits ProfileLoaded with the active id unchanged,
      // so tapping the brand new card used to open the old active server.
      final endpoints = FakeEndpointBloc();
      await tester.pumpWidget(host(
        endpoints: endpoints,
        profileState: ProfileLoaded(
          [profile('default', 'Default'), profile('new-id', 'Staging')],
          'default',
        ),
        child: const MobileEndpointsScreen(profileId: 'new-id'),
      ));

      expect(endpoints.loadedProfileIds, ['new-id']);
      expect(find.text('Staging'), findsOneWidget);
    });

    testWidgets('opens the tapped server after a delete reset the active id to default',
        (tester) async {
      // Deleting the active profile makes ProfileBloc fall back to 'default'.
      final endpoints = FakeEndpointBloc();
      await tester.pumpWidget(host(
        endpoints: endpoints,
        profileState: ProfileLoaded(
          [profile('default', 'Default'), profile('kept', 'Kept')],
          'default',
        ),
        child: const MobileEndpointsScreen(profileId: 'kept'),
      ));

      expect(endpoints.loadedProfileIds, ['kept']);
      expect(find.text('Kept'), findsOneWidget);
    });
  });

  group('DesktopEndpointsPane only renders its own profile', () {
    Widget pane(FakeEndpointBloc endpoints, String profileId) => host(
          endpoints: endpoints,
          profileState: ProfileLoaded([profile(profileId, 'Whatever')], profileId),
          child: Scaffold(
            body: DesktopEndpointsPane(
              profileId: profileId,
              profileName: 'Whatever',
              selectedEndpointId: null,
              onEndpointSelected: (_) {},
              onAddEndpoint: () {},
            ),
          ),
        );

    testWidgets('ignores endpoints still loaded for the previous server',
        (tester) async {
      final endpoints = FakeEndpointBloc();
      await tester.pumpWidget(pane(endpoints, 'beta'));

      endpoints.push(EndpointLoaded([endpoint('e1', 'alpha', '/alpha/thing')], 'alpha'));
      await tester.pumpAndSettle();

      expect(endpoints.state, isA<EndpointLoaded>(),
          reason: 'the bloc really is holding the other server\'s load');
      expect(find.text('/alpha/thing'), findsNothing,
          reason: "another server's endpoint must never be tappable here");
      expect(find.text('No endpoints yet'), findsOneWidget);
    });

    testWidgets('renders once the matching load lands', (tester) async {
      final endpoints = FakeEndpointBloc();
      await tester.pumpWidget(pane(endpoints, 'beta'));

      endpoints.push(EndpointLoaded([endpoint('e1', 'alpha', '/alpha/thing')], 'alpha'));
      await tester.pumpAndSettle();
      endpoints.push(EndpointLoaded([endpoint('e2', 'beta', '/beta/thing')], 'beta'));
      await tester.pumpAndSettle();

      expect(find.text('/beta/thing'), findsOneWidget);
      expect(find.text('/alpha/thing'), findsNothing);
      expect(find.text('1 endpoint'), findsOneWidget);
    });
  });
}

/// Records the [LoadEndpointsEvent]s the UI dispatches and lets a test drive
/// the bloc's state, without standing up the nine real use cases.
class FakeEndpointBloc extends Bloc<EndpointEvent, EndpointState>
    implements EndpointBloc {
  FakeEndpointBloc() : super(EndpointInitial()) {
    on<_PushState>((event, emit) => emit(event.state));
    // Swallow everything the screens dispatch; the assertions read
    // [loadedProfileIds] instead of any resulting state.
    on<EndpointEvent>((_, __) {});
  }

  final List<EndpointEvent> _received = [];

  List<String> get loadedProfileIds =>
      _received.whereType<LoadEndpointsEvent>().map((e) => e.profileId).toList();

  void push(EndpointState state) => add(_PushState(state));

  @override
  void add(EndpointEvent event) {
    if (event is! _PushState) _received.add(event);
    super.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PushState extends EndpointEvent {
  _PushState(this.state);
  final EndpointState state;

  @override
  List<Object?> get props => [state];
}

class FakeProfileBloc extends Bloc<ProfileEvent, ProfileState> implements ProfileBloc {
  FakeProfileBloc(super.initialState) {
    on<ProfileEvent>((_, __) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeServerBloc extends Bloc<ServerEvent, ServerState> implements ServerBloc {
  FakeServerBloc() : super(ServerInitial()) {
    on<ServerEvent>((_, __) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
