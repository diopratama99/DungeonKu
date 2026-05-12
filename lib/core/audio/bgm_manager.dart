import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Per-campaign-template music sets. The current asset pack ships:
///   ashfall_exploration / ashfall_boss
///   the_clockwork_heist_exploration / the_clockwork_heist_chase
///   the_sunken_crown_exploration / the_sunken_crown_boss
///
/// Adding a new template just means dropping new mp3s in
/// `assets/audio/bgm/<template>_<intensity>.mp3` and wiring an entry below.
class _TrackSet {
  const _TrackSet({required this.exploration, required this.intense});

  /// Calmer track for exploration / dialogue beats.
  final String exploration;

  /// Higher-tension track. We use it for boss combat or any "chase"-style
  /// pursuit phase. Some templates ship `_boss.mp3`, others `_chase.mp3`;
  /// the field name is intensity-agnostic on purpose.
  final String intense;
}

const _trackMap = <String, _TrackSet>{
  'ashfall': _TrackSet(
    exploration: 'assets/audio/bgm/ashfall_exploration.mp3',
    intense: 'assets/audio/bgm/ashfall_boss.mp3',
  ),
  'the_clockwork_heist': _TrackSet(
    exploration: 'assets/audio/bgm/the_clockwork_heist_exploration.mp3',
    intense: 'assets/audio/bgm/the_clockwork_heist_chase.mp3',
  ),
  'the_sunken_crown': _TrackSet(
    exploration: 'assets/audio/bgm/the_sunken_crown_exploration.mp3',
    intense: 'assets/audio/bgm/the_sunken_crown_boss.mp3',
  ),
};

const _menuTheme = 'assets/audio/bgm/main_menu_theme.mp3';
const _questCompleteJingle = 'assets/audio/bgm/quest_complete.mp3';

/// Thin wrapper around two [AudioPlayer]s — one for the looping BGM that
/// follows the player from screen to screen, and one short-lived player per
/// stinger (so quest-complete jingle doesn't clobber the BGM).
///
/// Why two players: just_audio's single-player [setAsset] always stops the
/// current clip first. If we used one shared player for stingers we'd lose
/// the BGM playback head; tracking a second instance lets the BGM keep
/// looping under the stinger.
class BgmManager with WidgetsBindingObserver {
  BgmManager() : _bgm = AudioPlayer() {
    // Hook into the global app lifecycle so we can pause when the OS
    // backgrounds us. Without this just_audio happily loops in the
    // background until the process is force-killed.
    WidgetsBinding.instance.addObserver(this);
  }

  final AudioPlayer _bgm;
  String? _currentTrack;
  bool _enabled = true;

  /// Set when the lifecycle observer pauses playback for us; used to
  /// decide whether to auto-resume on `AppLifecycleState.resumed`. We
  /// only resume what *we* paused — never override an explicit mute.
  bool _pausedByLifecycle = false;

  /// Default BGM volume when not ducked. ~60% leaves headroom for game SFX
  /// and OS notifications without forcing the player to reach for the
  /// volume rocker.
  static const double _bgmVolume = 0.55;
  static const double _stingerVolume = 0.85;

  bool get enabled => _enabled;

  /// Master kill switch. Used by a future settings screen / "mute" toggle.
  /// Stops current playback when toggled off; doesn't auto-resume on toggle
  /// back on (caller can re-invoke [playMenu]/[playForGame]).
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value) {
      await _bgm.stop();
      _currentTrack = null;
    }
  }

  /// Loops the main-menu theme. Idempotent: re-calling with the same track
  /// already playing is a no-op so navigating around the menu doesn't
  /// restart the song.
  Future<void> playMenu() => _playLoop(_menuTheme);

  /// Loops the appropriate per-template track. Resolves intensity from
  /// [inIntenseCombat] (true = boss / chase track when available).
  /// If the template is unknown we silently keep whatever is currently
  /// playing — better than abruptly cutting to silence.
  Future<void> playForGame({
    required String templateId,
    required bool inIntenseCombat,
  }) async {
    final set = _trackMap[templateId];
    if (set == null) return;
    final asset = inIntenseCombat ? set.intense : set.exploration;
    await _playLoop(asset);
  }

  /// Stops looping playback. Use when leaving any music-bearing screen so
  /// silence + state changes don't get mixed across navigation events.
  Future<void> stop() async {
    _currentTrack = null;
    await _bgm.stop();
  }

  /// Fires the quest-complete fanfare on top of the current BGM. Each
  /// invocation creates a one-shot player that disposes itself when
  /// playback completes; the BGM continues underneath unaffected.
  Future<void> playQuestComplete() => _playStinger(_questCompleteJingle);

  Future<void> _playLoop(String asset) async {
    if (!_enabled) return;
    if (_currentTrack == asset && _bgm.playing) return;
    _currentTrack = asset;
    try {
      await _bgm.setAsset(asset);
      await _bgm.setLoopMode(LoopMode.one);
      await _bgm.setVolume(_bgmVolume);
      await _bgm.play();
    } catch (_) {
      // Don't blow up the UI on audio failures (asset missing on some build
      // flavour, hot-restart races, etc). Silent BGM is acceptable.
      _currentTrack = null;
    }
  }

  Future<void> _playStinger(String asset) async {
    if (!_enabled) return;
    final stinger = AudioPlayer();
    try {
      await stinger.setAsset(asset);
      await stinger.setVolume(_stingerVolume);
      stinger.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          stinger.dispose();
        }
      });
      await stinger.play();
    } catch (_) {
      await stinger.dispose();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // App went to background (recent-apps switcher, home button,
        // screen off, …). Pause and remember so we can resume on the
        // way back in.
        if (_bgm.playing) {
          _pausedByLifecycle = true;
          _bgm.pause();
        }
        break;
      case AppLifecycleState.resumed:
        // Only auto-resume what *we* paused. If the user toggled
        // [setEnabled] off while in the background we must not
        // override that.
        if (_pausedByLifecycle && _enabled && _currentTrack != null) {
          _bgm.play();
        }
        _pausedByLifecycle = false;
        break;
      case AppLifecycleState.inactive:
        // Transient state on iOS (notification pull, control center,
        // incoming call ring). Pausing here would stutter the music
        // every time the user swipes the status bar — leave alone.
        break;
      case AppLifecycleState.detached:
        // Process is about to die — stop hard so audio doesn't linger
        // even for the brief window before Android tears the engine
        // down. Belt + braces with [dispose].
        _bgm.stop();
        break;
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _bgm.dispose();
  }
}

/// App-wide singleton. We deliberately put it at the root so screen
/// navigations don't tear the player down and re-create it (which would
/// stop the music every time you push/pop a route).
final bgmManagerProvider = Provider<BgmManager>((ref) {
  final mgr = BgmManager();
  ref.onDispose(mgr.dispose);
  return mgr;
});
