/// Decides whether a media completion event should advance playback.
///
/// A new media open must call [reset] before events from that media are
/// processed. Completion notifications emitted while loading are ignored, and
/// only the first accepted completion notification advances playback.
class PlaybackCompletionStrategy {
  bool _handled = false;

  /// Starts a new media-open cycle.
  void reset() {
    _handled = false;
  }

  /// Returns whether this completion event should be handled.
  bool shouldHandle({required bool completed, required bool isLoading}) {
    if (!completed || isLoading || _handled) {
      return false;
    }
    _handled = true;
    return true;
  }
}
