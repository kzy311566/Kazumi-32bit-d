import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/tv_support.dart';

void main() {
  // TvSupport keeps process-wide state; always start from a known point.
  setUp(() {
    TvSupport.resolve(false);
  });
  tearDown(() {
    TvSupport.resolve(false);
  });

  group('remote key detection', () {
    test('recognises D-pad and centre keys', () {
      expect(TvSupport.noteKey(LogicalKeyboardKey.arrowUp), isTrue);
      expect(TvSupport.noteKey(LogicalKeyboardKey.arrowDown), isTrue);
      expect(TvSupport.noteKey(LogicalKeyboardKey.arrowLeft), isTrue);
      expect(TvSupport.noteKey(LogicalKeyboardKey.arrowRight), isTrue);
      expect(TvSupport.noteKey(LogicalKeyboardKey.select), isTrue);
      expect(TvSupport.noteKey(LogicalKeyboardKey.goBack), isTrue);
    });

    test('ignores ordinary typing so focus rings do not flash in the UI', () {
      expect(TvSupport.noteKey(LogicalKeyboardKey.keyA), isFalse);
      expect(TvSupport.noteKey(LogicalKeyboardKey.space), isFalse);
    });

    test('a remote key press switches the session into remote mode', () {
      TvSupport.resolve(false);
      expect(TvSupport.showFocusHighlight, isFalse);
      TvSupport.noteKey(LogicalKeyboardKey.arrowDown);
      expect(TvSupport.remoteInUse, isTrue);
      expect(TvSupport.showFocusHighlight, isTrue);
    });

    test('noteKey is idempotent', () {
      TvSupport.noteKey(LogicalKeyboardKey.arrowUp);
      TvSupport.noteKey(LogicalKeyboardKey.arrowUp);
      expect(TvSupport.remoteInUse, isTrue);
    });
  });

  group('activate keys', () {
    test('accepts every key a remote might use for OK', () {
      // A remote's centre button arrives as `select`; gamepad-style controllers
      // and some remotes send `enter` / `gameButtonA` instead.
      expect(TvSupport.isActivateKey(LogicalKeyboardKey.select), isTrue);
      expect(TvSupport.isActivateKey(LogicalKeyboardKey.enter), isTrue);
      expect(TvSupport.isActivateKey(LogicalKeyboardKey.numpadEnter), isTrue);
      expect(TvSupport.isActivateKey(LogicalKeyboardKey.gameButtonA), isTrue);
    });

    test('rejects navigation keys', () {
      expect(TvSupport.isActivateKey(LogicalKeyboardKey.arrowUp), isFalse);
      expect(TvSupport.isActivateKey(LogicalKeyboardKey.goBack), isFalse);
      expect(TvSupport.isActivateKey(LogicalKeyboardKey.space), isFalse);
    });
  });

  group('TvSupport.applyTo', () {
    test('leaves the theme untouched when not highlighting focus', () {
      TvSupport.resolve(false);
      final base = ThemeData(useMaterial3: true);
      expect(identical(TvSupport.applyTo(base), base), isTrue);
    });

    test('adds focus styling once focus highlighting is active', () {
      TvSupport.resolve(true);
      final base = ThemeData(useMaterial3: true);
      final themed = TvSupport.applyTo(base);
      expect(identical(themed, base), isFalse);
      expect(themed.iconButtonTheme.style, isNotNull);
      expect(themed.focusColor, isNot(base.focusColor));
    });

    test('focused icon buttons get a filled background for visibility', () {
      TvSupport.resolve(true);
      final themed = TvSupport.applyTo(ThemeData(useMaterial3: true));
      final background = themed.iconButtonTheme.style!.backgroundColor!;
      final focused = background.resolve({WidgetState.focused});
      final idle = background.resolve(<WidgetState>{});
      expect(focused, isNotNull);
      expect(idle, isNull);
    });
  });

  group('detection fallback', () {
    test('explicitly resolved TV mode wins over detection', () {
      TvSupport.resolve(true);
      expect(TvSupport.isTvMode, isTrue);
      expect(TvSupport.showFocusHighlight, isTrue);
    });

    test('resolving non-TV clears the remote flag', () {
      TvSupport.resolve(true);
      TvSupport.noteKey(LogicalKeyboardKey.arrowUp);
      expect(TvSupport.remoteInUse, isTrue);
      TvSupport.resolve(false);
      expect(TvSupport.isTvMode, isFalse);
      expect(TvSupport.remoteInUse, isFalse);
    });
  });
}
