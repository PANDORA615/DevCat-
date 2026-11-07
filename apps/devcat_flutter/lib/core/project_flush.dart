/// Installers may only open after all mounted editors have saved successfully.
class ProjectFlush {
  static final _callbacks = <Future<void> Function()>{};
  static void Function() register(Future<void> Function() save) {
    _callbacks.add(save);
    return () => _callbacks.remove(save);
  }

  static Future<void> saveAll() async {
    for (final save in List.of(_callbacks)) {
      await save();
    }
  }
}
