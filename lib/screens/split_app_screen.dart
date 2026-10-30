import 'package:flutter/material.dart';

import '../data/prefs.dart';
import '../theme/reading_theme.dart';
import '../theme/text_settings.dart';
import 'main_menu_screen.dart';
import 'read_along.dart';

/// True while the app is shown in two halves.
final appSplitOpen = ValueNotifier<bool>(false);

Route<void>? _splitRoute;

/// Opens the app twice on one screen: top and bottom, each with its own
/// main menu, so you can read e.g. a message above and the Bible below.
/// [top]: what to show in the top half (e.g. the message being read); the main menu is
/// under it, so Back in the top half goes to the main menu. The bottom half starts at
/// the main menu.
void openAppSplit(BuildContext context, {WidgetBuilder? top}) {
  if (appSplitOpen.value) return;
  final route = MaterialPageRoute<void>(builder: (_) => SplitAppScreen(top: top));
  _splitRoute = route;
  Navigator.of(context, rootNavigator: true).push(route);
}

/// Back to one app on the whole screen.
void closeAppSplit(BuildContext context) {
  final route = _splitRoute;
  if (route == null || !appSplitOpen.value) return;
  _splitRoute = null;
  Navigator.of(context, rootNavigator: true).removeRoute(route);
}

class SplitAppScreen extends StatefulWidget {
  const SplitAppScreen({super.key, this.top});
  final WidgetBuilder? top;

  @override
  State<SplitAppScreen> createState() => _SplitAppScreenState();
}

class _SplitAppScreenState extends State<SplitAppScreen> {
  final _navs = [GlobalKey<NavigatorState>(), GlobalKey<NavigatorState>()];

  // Each half has its own theme and text settings, remembered for the split view only.
  static final _themes = [ThemeController('split_top_'), ThemeController('split_bottom_')];
  static final _texts = [TextSettingsController('split_top_'), TextSettingsController('split_bottom_')];
  static bool _loaded = false;
  double _ratio = 0.5; // share of the screen for the top half
  int _focused = 0; // the half touched last (system Back goes there)

  @override
  void initState() {
    super.initState();
    appSplitOpen.value = true;
    Prefs.instance.set('resume_split', true);
    if (!_loaded) {
      _loaded = true;
      for (final t in _themes) {
        t.load();
      }
      for (final t in _texts) {
        t.load();
      }
    }
  }

  @override
  void dispose() {
    appSplitOpen.value = false;
    ReadAlong.instance.reset();
    Prefs.instance.set('resume_split', false);
    super.dispose();
  }

  Widget _half(int i) {
    return Listener(
      onPointerDown: (_) => _focused = i,
      // The keyboard is handled once, by the whole split screen (it gets shorter).
      // Without this, each half also made room for the keyboard, squeezed itself to
      // nothing and the search box lost the keyboard straight away.
      child: Builder(
        builder: (context) => MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: Builder(
        builder: (context) => MediaQuery.removePadding(
        context: context,
        removeTop: i == 1,
        removeBottom: i == 0,
        child: ThemeScope(
          controller: _themes[i],
          child: TextSettingsScope(
            controller: _texts[i],
            child: ValueListenableBuilder<ReadingTheme>(
              valueListenable: _themes[i],
              builder: (_, theme, child) => Theme(data: theme.toThemeData(), child: child!),
              child: ClipRect(
                child: SplitHalf(
                  index: i,
                  child: Navigator(
                  key: _navs[i],
                  onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const MainMenuScreen()),
                  onGenerateInitialRoutes: (_, __) => [
                    MaterialPageRoute(builder: (_) => const MainMenuScreen()),
                    if (i == 0 && widget.top != null) MaterialPageRoute(builder: widget.top!),
                  ],
                  ),
                ),
              ),
            ),
          ),
        ),
        ),
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _navs[_focused].currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else {
          Navigator.of(context).pop(); // leave the split view
        }
      },
      child: Scaffold(
        body: LayoutBuilder(builder: (context, box) {
          const bar = 22.0;
          final top = (box.maxHeight - bar) * _ratio;
          return Column(
            children: [
              SizedBox(height: top, child: _half(0)),
              // Drag this bar to resize; ✕ goes back to one screen.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) => setState(() {
                  _ratio = ((top + d.delta.dy) / (box.maxHeight - bar)).clamp(0.2, 0.8);
                }),
                child: Container(
                  height: bar,
                  color: theme.colorScheme.primary.withValues(alpha: 0.55),
                  child: Row(
                    children: [
                      const Spacer(),
                      Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(Icons.close, size: 18, color: theme.colorScheme.onPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: _half(1)),
            ],
          );
        }),
      ),
    );
  }
}
