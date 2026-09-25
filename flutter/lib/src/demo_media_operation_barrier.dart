import 'dart:async';

/// Serializes Example-owned media work and lets session teardown wait for it.
final class DemoMediaOperationBarrier {
  Future<void>? _operation;
  bool _closing = false;

  bool get accepting => !_closing;

  Future<void> run(Future<void> Function() operation) {
    final Future<void>? active = _operation;
    if (active != null) return active;
    if (_closing) return Future<void>.value();

    late final Future<void> tracked;
    tracked = Future<void>.sync(operation).whenComplete(() {
      if (identical(_operation, tracked)) _operation = null;
    });
    _operation = tracked;
    return tracked;
  }

  void beginClosing() {
    _closing = true;
  }

  void reopen() {
    _closing = false;
  }

  Future<void> drain() async {
    while (true) {
      final Future<void>? active = _operation;
      if (active == null) return;
      await active;
    }
  }
}
