import 'package:flutter/widgets.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

final RouteObserver<PageRoute<dynamic>> exampleRouteObserver = RouteObserver<PageRoute<dynamic>>();

mixin ExampleRouteLifecycleState<T extends StatefulWidget> on State<T>, WidgetsBindingObserver implements RouteAware {
  bool _routeVisible = false;
  bool _appForeground = true;
  bool _subscribed = false;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subscribed) {
      return;
    }

    final ModalRoute<dynamic>? modalRoute = ModalRoute.of(context);
    if (modalRoute is! PageRoute<dynamic>) {
      return;
    }

    _routeVisible = modalRoute.isCurrent;
    exampleRouteObserver.subscribe(this, modalRoute);
    _subscribed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncLifecycle('initial_frame');
      }
    });
  }

  @override
  void dispose() {
    if (_subscribed) {
      exampleRouteObserver.unsubscribe(this);
      _subscribed = false;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.inactive) {
      _appForeground = true;
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appForeground = false;
    }
    _syncLifecycle('app_$state');
  }

  @override
  void didPush() {
    _routeVisible = true;
    _syncLifecycle('did_push');
  }

  @override
  void didPop() {
    _routeVisible = false;
    _syncLifecycle('did_pop');
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _syncLifecycle('did_pop_next');
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _syncLifecycle('did_push_next');
  }

  void _syncLifecycle(String reason) {
    final bool shouldBeActive = _appForeground && _routeVisible;
    if (_active == shouldBeActive) {
      return;
    }

    _active = shouldBeActive;
    TiRtcLogging.i(
      'flutter_example',
      'route_lifecycle widget=${widget.runtimeType} reason=$reason '
          'active=$_active routeVisible=$_routeVisible foreground=$_appForeground',
    );
    if (_active) {
      onRouteActive(reason);
    } else {
      onRouteInactive(reason);
    }
  }

  @protected
  void onRouteActive(String reason) {}

  @protected
  void onRouteInactive(String reason) {}
}
