import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'runtime/agent_runtime.dart';
import 'runtime/storage.dart';
import 'ui/audit_page.dart';
import 'ui/chat_page.dart';
import 'ui/data_page.dart';
import 'ui/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final rt = await AgentRuntime.load(PrefsStorage(prefs));
  runApp(AgentDeckApp(rt));
}

class AgentDeckApp extends StatelessWidget {
  const AgentDeckApp(this.rt, {super.key});
  final AgentRuntime rt;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'NEXU AgentDeck',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1B5E68),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF5F7F7),
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            scrolledUnderElevation: 0,
            backgroundColor: Color(0xFFF5F7F7),
            surfaceTintColor: Colors.transparent,
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: Colors.white,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFE3EAEA)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFDCE5E5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFDCE5E5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFF1B5E68), width: 1.5),
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            height: 72,
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFFD9EEEE),
            elevation: 8,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                  fontSize: 12,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w700
                      : FontWeight.w500,
                )),
          ),
        ),
        home: HomeShell(rt),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell(this.rt, {super.key});
  final AgentRuntime rt;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;
  @override
  Widget build(BuildContext context) {
    final rt = widget.rt;
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        reverseDuration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.025, 0), end: Offset.zero)
                .animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey(_i),
          child: [ChatPage(rt), DataPage(rt), AuditPage(rt), SettingsPage(rt)][_i],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Agent'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Data'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), label: 'Audit'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
