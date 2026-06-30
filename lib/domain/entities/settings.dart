import 'package:equatable/equatable.dart';

class Settings extends Equatable {
  final bool showEndpointHitsInNotifications;
  final bool showFloatingOverlay;

  // What the floating overlay bubble shows.
  final bool overlayShowMethod;
  final bool overlayShowEndpoint;
  final bool overlayShowStatus;
  final bool overlayShowTime;

  const Settings({
    this.showEndpointHitsInNotifications = false,
    this.showFloatingOverlay = false,
    this.overlayShowMethod = true,
    this.overlayShowEndpoint = true,
    this.overlayShowStatus = true,
    this.overlayShowTime = false,
  });

  Settings copyWith({
    bool? showEndpointHitsInNotifications,
    bool? showFloatingOverlay,
    bool? overlayShowMethod,
    bool? overlayShowEndpoint,
    bool? overlayShowStatus,
    bool? overlayShowTime,
  }) {
    return Settings(
      showEndpointHitsInNotifications: showEndpointHitsInNotifications ?? this.showEndpointHitsInNotifications,
      showFloatingOverlay: showFloatingOverlay ?? this.showFloatingOverlay,
      overlayShowMethod: overlayShowMethod ?? this.overlayShowMethod,
      overlayShowEndpoint: overlayShowEndpoint ?? this.overlayShowEndpoint,
      overlayShowStatus: overlayShowStatus ?? this.overlayShowStatus,
      overlayShowTime: overlayShowTime ?? this.overlayShowTime,
    );
  }

  @override
  List<Object?> get props => [
        showEndpointHitsInNotifications,
        showFloatingOverlay,
        overlayShowMethod,
        overlayShowEndpoint,
        overlayShowStatus,
        overlayShowTime,
      ];
}
