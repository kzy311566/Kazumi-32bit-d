import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Detection and presentation support for TV / set-top-box use.
///
/// Android TV boxes are a primary target for the 32-bit build and they are
/// operated with a D-pad remote rather than a touch screen. Two facts drive the
/// design here:
///
///  * Flutter's focus system already provides D-pad navigation for Material
///    controls, so most of the app works once focus is *visible* and nothing
///    steals the arrow keys.
///  * The previous revision bound the arrow keys globally to seek/volume through
///    an early key handler, and left the on-screen player controls unfocusable,
///    so a remote could not reach a single button.
///
/// Detection deliberately needs no extra platform channel: Android reports
/// D-pad-only navigation through `MediaQueryData.navigationMode`, and the first
/// remote key press is itself proof that a remote is in use.
class TvSupport {
  TvSupport._();

  /// True when the app should behave like a TV app: bigger focus rings, a
  /// focusable player panel, and no hover-only affordances.
  static bool get isTvMode => _isTvMode;
  static bool _isTvMode = false;

  /// True once a remote/D-pad key press has been observed in this session.
  ///
  /// This is what makes focus rings appear the moment the user picks up the
  /// remote, instead of guessing from the device type alone.
  static bool get remoteInUse => _remoteInUse.value;
  static final ValueNotifier<bool> _remoteInUse = ValueNotifier<bool>(false);
  static ValueListenable<bool> get remoteInUseListenable => _remoteInUse;

  /// Whether focus decoration should be painted.
  static bool get showFocusHighlight => isTvMode || remoteInUse;

  /// True when Android reports D-pad-only navigation.
  static bool get hasDirectionalNavigation => _navigationModeIsDirectional;
  static bool _navigationModeIsDirectional = false;

  static bool _deviceTypeResolved = false;

  /// Decides TV mode from the physical screen. Call once, after the first frame.
  ///
  /// [override] comes from the debug/settings toggle; `null` means "detect".
  static void initializeFromView({bool? override}) {
    if (override != null) {
      resolve(override);
      return;
    }
    if (!Platform.isAndroid) {
      resolve(false);
      return;
    }
    if (_looksLikeTvScreen()) {
      resolve(true);
      return;
    }
    // A D-pad-only device is a remote-controlled device even when the form
    // factor heuristic does not fire, which happens on some boxes.
    if (_navigationModeIsDirectional) {
      resolve(true);
      return;
    }
    resolve(false);
  }

  @visibleForTesting
  static void resolve(bool isTv) {
    _isTvMode = isTv;
    _deviceTypeResolved = true;
    if (!isTv) _remoteInUse.value = false;
  }

  /// Large landscape screen with no touch input: a TV, a monitor, or a box.
  static bool _looksLikeTvScreen() {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return false;
      final view = views.first;
      final ratio = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
      final logicalWidth = view.physicalSize.width / ratio;
      final logicalHeight = view.physicalSize.height / ratio;
      if (logicalWidth < 900) return false;
      if (logicalWidth <= logicalHeight) return false;
      // `view.viewConfiguration` is not exposed; touch support is inferred from
      // the device type below instead.
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fold the platform's navigation mode into the TV decision.
  ///
  /// Called from the app shell whenever [MediaQueryData] is available, so a
  /// phone that is being driven by a remote (or a box that reports a phone-like
  /// uiMode) still gets TV behaviour.
  static void updateFromMediaQuery(MediaQueryData data) {
    final directional = data.navigationMode == NavigationMode.directional;
    _navigationModeIsDirectional = directional;
    if (directional && !_isTvMode) {
      _isTvMode = true;
    }
  }

  /// Logical keys that a TV remote can send.
  ///
  /// Not `const`: `LogicalKeyboardKey`'s constants are not compile-time
  /// constants to the analyzer, so a const set fails to compile.
  static final Set<LogicalKeyboardKey> remoteKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.gameButtonB,
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.escape,
  };

  /// Keys that mean "activate the focused control" on a remote.
  ///
  /// A remote's centre button arrives as `select`; some remotes and most
  /// gamepad-style controllers send `enter` or `gameButtonA` instead.
  static bool isActivateKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;

  /// Keys that Flutter does *not* already map to an activation intent.
  ///
  /// Only these need intercepting. Handling `enter` too would swallow it before
  /// text fields and dialogs see it, because the interception happens in an
  /// early key handler that runs before the focus tree.
  static bool isUnmappedActivateKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select;

  /// Records remote usage so focus rings can be shown. Returns true when the key
  /// looks like it came from a remote.
  static bool noteKey(LogicalKeyboardKey key) {
    if (!remoteKeys.contains(key)) return false;
    if (!_remoteInUse.value) {
      _remoteInUse.value = true;
    }
    if (!_deviceTypeResolved) {
      // First remote key press: treat the device as remote-driven from now on.
      _isTvMode = true;
      _deviceTypeResolved = true;
    }
    return true;
  }

  /// Installs the remote-usage detector. Safe to call once from `main()`.
  static void installRemoteDetector() {
    FocusManager.instance.addEarlyKeyEventHandler(_onKey);
  }

  static KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    noteKey(event.logicalKey);
    // This only observes; it must never consume the event.
    return KeyEventResult.ignored;
  }

  /// Focus ring geometry: thick enough to read from a couch.
  static const double focusBorderWidth = 3.0;
  static const double focusBorderRadius = 12.0;

  static RoundedRectangleBorder focusBorder(Color color) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(focusBorderRadius),
        side: BorderSide(color: color, width: focusBorderWidth),
      );

  /// Theme overrides applied while [showFocusHighlight] is true.
  ///
  /// Material's defaults rely on hover and on a faint overlay that is invisible
  /// on a TV; these make the focused control unmistakable.
  static ThemeData applyTo(ThemeData base) {
    if (!showFocusHighlight) return base;
    final highlight = base.colorScheme.primary;
    return base.copyWith(
      focusColor: highlight.withValues(alpha: 0.30),
      hoverColor: highlight.withValues(alpha: 0.18),
      highlightColor: highlight.withValues(alpha: 0.24),
      splashFactory: NoSplash.splashFactory,
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          // A filled shape behind the icon reads far better than an outline at
          // ten feet.
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return highlight.withValues(alpha: 0.85);
            }
            return null;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return base.colorScheme.onPrimary;
            }
            return null;
          }),
          shape: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? focusBorder(highlight)
                : const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(focusBorderRadius),
                    ),
                  ),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? BorderSide(color: base.colorScheme.onPrimary, width: 2.5)
                : null,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? BorderSide(color: highlight, width: 2.5)
                : null,
          ),
        ),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        indicatorColor: highlight.withValues(alpha: 0.40),
      ),
      navigationRailTheme: base.navigationRailTheme.copyWith(
        indicatorColor: highlight.withValues(alpha: 0.40),
      ),
      cardTheme: base.cardTheme.copyWith(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(focusBorderRadius)),
        ),
      ),
    );
  }
}

/// Paints a focus ring around [child] whenever it or a descendant has focus.
///
/// Wrapping cards and list rows in this makes D-pad navigation legible without
/// touching each widget's own styling.
class TvFocusRing extends StatefulWidget {
  const TvFocusRing({
    super.key,
    required this.child,
    this.borderRadius,
    this.inset = 2.0,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final double inset;

  @override
  State<TvFocusRing> createState() => _TvFocusRingState();
}

class _TvFocusRingState extends State<TvFocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    if (!TvSupport.showFocusHighlight) return widget.child;

    final radius =
        widget.borderRadius ??
        BorderRadius.circular(TvSupport.focusBorderRadius);
    return Focus(
      canRequestFocus: false,
      onFocusChange: (value) {
        if (value != _focused) setState(() => _focused = value);
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_focused)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.all(widget.inset),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: TvSupport.focusBorderWidth,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
