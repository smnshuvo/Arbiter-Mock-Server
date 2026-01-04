import 'package:equatable/equatable.dart';

class Settings extends Equatable {
  final bool showEndpointHitsInNotifications;

  const Settings({
    this.showEndpointHitsInNotifications = false,
  });

  Settings copyWith({
    bool? showEndpointHitsInNotifications,
  }) {
    return Settings(
      showEndpointHitsInNotifications: showEndpointHitsInNotifications ?? this.showEndpointHitsInNotifications,
    );
  }

  @override
  List<Object?> get props => [showEndpointHitsInNotifications];
}
