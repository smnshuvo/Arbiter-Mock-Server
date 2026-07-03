import 'dart:async';
import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_config.dart';

/// Centralized AdMob controller: SDK init, throttled interstitials, and the
/// rewarded-ad flow that unlocks the remote seekbar/volume for 12 hours.
///
/// Every method no-ops on platforms where `google_mobile_ads` is unsupported
/// (desktop) so the rest of the app is unaffected.
class AdService {
  AdService(this._prefs);

  final SharedPreferences _prefs;

  bool _initialized = false;

  /// Interstitials/rewarded/banners are only supported on Android and iOS.
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  static const Duration _interstitialInterval = Duration(hours: 1);
  static const Duration _seekbarUnlockDuration = Duration(hours: 12);
  static const String _seekbarUnlockKey = 'remote_seekbar_unlock_until';

  Future<void> init() async {
    if (!isSupported || _initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  // ---- Interstitials ------------------------------------------------------

  /// Shows a full-screen interstitial for [gateKey], but no more than once per
  /// hour for that gate. Each trigger (start-server, open-remote) passes its own
  /// [gateKey] so their hourly limits are independent. Fire-and-forget.
  void maybeShowInterstitial(String gateKey, String adUnitId) {
    if (!isSupported) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _prefs.getInt(gateKey) ?? 0;
    if (now - last < _interstitialInterval.inMilliseconds) return;

    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (ad) {
              // Record only once the ad actually shows, so a failed load
              // doesn't burn the hourly window.
              _prefs.setInt(gateKey, DateTime.now().millisecondsSinceEpoch);
            },
            onAdDismissedFullScreenContent: (ad) => ad.dispose(),
            onAdFailedToShowFullScreenContent: (ad, error) => ad.dispose(),
          );
          ad.show();
        },
        onAdFailedToLoad: (error) {/* ignore — no ad this time */},
      ),
    );
  }

  // ---- Rewarded (seekbar/volume unlock) -----------------------------------

  bool isSeekbarUnlocked() {
    final until = _prefs.getInt(_seekbarUnlockKey) ?? 0;
    return DateTime.now().millisecondsSinceEpoch < until;
  }

  /// Remaining unlock time, or null if currently locked.
  Duration? seekbarUnlockRemaining() {
    final until = _prefs.getInt(_seekbarUnlockKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= until) return null;
    return Duration(milliseconds: until - now);
  }

  /// Loads and shows a rewarded ad. Returns true if the user earned the reward,
  /// in which case the seekbar/volume is unlocked for 12 hours.
  Future<bool> showRewardedForSeekbar() async {
    if (!isSupported) return false;
    final completer = Completer<bool>();
    var earned = false;

    RewardedAd.load(
      adUnitId: AdConfig.rewardedSeekbar,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete(earned);
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete(false);
            },
          );
          ad.show(
            onUserEarnedReward: (ad, reward) {
              earned = true;
              _prefs.setInt(
                _seekbarUnlockKey,
                DateTime.now()
                    .add(_seekbarUnlockDuration)
                    .millisecondsSinceEpoch,
              );
            },
          );
        },
        onAdFailedToLoad: (error) {
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    return completer.future;
  }
}
