import 'dart:async';

enum ExecutionReaction { idle, loading, success, error, cancelled }

/// Keeps feedback attached to the current execution, never a stale completion.
class ExecutionFeedback {
  final void Function() onChanged;
  final Duration loadingDelay;
  ExecutionFeedback(
    this.onChanged, {
    this.loadingDelay = const Duration(milliseconds: 700),
  });
  Timer? _timer;
  int _generation = 0;
  int get generation => _generation;
  bool _disposed = false;
  ExecutionReaction reaction = ExecutionReaction.idle;
  String get animation => switch (reaction) {
    ExecutionReaction.idle => 'idle',
    ExecutionReaction.loading => 'loading',
    ExecutionReaction.success => 'success',
    ExecutionReaction.error => 'error',
    ExecutionReaction.cancelled => 'waiting',
  };
  String get message => switch (reaction) {
    ExecutionReaction.idle => '',
    ExecutionReaction.loading => 'Собираю и запускаю программу на устройстве…',
    ExecutionReaction.success =>
      'Запуск завершён. Сравни вывод с ожидаемым результатом.',
    ExecutionReaction.error =>
      'Посмотрим первую ошибку в выводе. Исправляй по одной — я рядом.',
    ExecutionReaction.cancelled =>
      'Запуск остановлен. Можно изменить код и попробовать снова.',
  };
  int begin() {
    if (_disposed) return -1;
    clear();
    final ticket = _generation;
    _timer = Timer(loadingDelay, () {
      if (_disposed || ticket != _generation) return;
      reaction = ExecutionReaction.loading;
      onChanged();
    });
    return ticket;
  }

  void finish(int ticket, {required bool ok, bool cancelled = false}) {
    if (_disposed || ticket != _generation) return;
    _timer?.cancel();
    reaction = cancelled
        ? ExecutionReaction.cancelled
        : ok
        ? ExecutionReaction.success
        : ExecutionReaction.error;
    onChanged();
  }

  void clear() {
    if (_disposed) return;
    _generation++;
    _timer?.cancel();
    reaction = ExecutionReaction.idle;
    onChanged();
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
  }
}
