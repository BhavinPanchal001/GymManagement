import 'package:flutter/material.dart';

/// Global navigation and scaffold messenger keys to allow safe context access
/// even when transient widgets (like bottom sheets or dialogs) have been popped/unmounted.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
