/// Pointer/keyboard activity wakes ambient cats without rebuilding the app or
/// making hover sounds. A listener decides whether any visible frame changed.
abstract final class MascotActivity {
  static final _listeners = <void Function()>{};
  static void Function() listen(void Function() callback) {
    _listeners.add(callback);
    return () => _listeners.remove(callback);
  }

  static void touch() {
    for (final callback in List.of(_listeners)) {
      callback();
    }
  }
}
