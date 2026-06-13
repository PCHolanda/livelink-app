import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

import 'services/supabase_service.dart';
import 'services/livekit_service.dart';
import 'views/login_view.dart';
import 'views/admin/admin_dashboard_view.dart';
import 'views/admin/user_management_view.dart';
import 'views/broadcaster/broadcaster_home_view.dart';
import 'views/broadcaster/stream_view.dart';
import 'views/spectator/spectator_view.dart';

// CONFIGURAÇÃO: Credenciais do Supabase fornecidas
const String supabaseUrl = 'https://pefhdfcihmtvemlzzpvo.supabase.co';
const String supabaseAnonKey = 'sb_publishable_rzezM1I42DaxPU2c9WPBcA_RBf1U_UE';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Remove o '#' da URL no Flutter Web
  usePathUrlStrategy();

  // Inicializa o Supabase. Em produção, insira suas chaves reais aqui.
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      debug: kDebugMode,
    );
  } catch (e) {
    debugPrint('Supabase Init Error: $e. Certifique-se de configurar chaves válidas no main.dart.');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SupabaseService()),
        ChangeNotifierProvider(create: (_) => LiveKitService()),
      ],
      child: const LiveLinkApp(),
    ),
  );
}

class LiveLinkApp extends StatelessWidget {
  const LiveLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    final supabaseService = Provider.of<SupabaseService>(context);

    final GoRouter router = GoRouter(
      initialLocation: '/login',
      refreshListenable: supabaseService,
      redirect: (context, state) {
        final user = supabaseService.currentUser;
        final isLoggingIn = state.matchedLocation == '/login';
        final isSpectator = state.matchedLocation.startsWith('/live/');

        // Permite que qualquer um acesse as páginas de espectador
        if (isSpectator) return null;

        if (user == null) {
          return isLoggingIn ? null : '/login';
        }

        // Redirecionamentos se já estiver logado
        if (isLoggingIn) {
          return user.isAdmin ? '/admin' : '/broadcaster';
        }

        // Bloqueia se tentar acessar áreas não permitidas por perfil
        if (state.matchedLocation.startsWith('/admin') && !user.isAdmin) {
          return '/broadcaster';
        }
        if (state.matchedLocation.startsWith('/broadcaster') && !user.isBroadcaster) {
          return '/admin';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginView(),
        ),
        GoRoute(
          path: '/admin',
          builder: (context, state) => const AdminDashboardView(),
        ),
        GoRoute(
          path: '/admin/users',
          builder: (context, state) => const UserManagementView(),
        ),
        GoRoute(
          path: '/broadcaster',
          builder: (context, state) => const BroadcasterHomeView(),
        ),
        GoRoute(
          path: '/broadcaster/stream/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return StreamView(liveId: id);
          },
        ),
        GoRoute(
          path: '/live/:slug',
          builder: (context, state) {
            final slug = state.pathParameters['slug']!;
            return SpectatorView(slug: slug);
          },
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Text('Página não encontrada: ${state.error}'),
        ),
      ),
    );

    return MaterialApp.router(
      title: 'LiveLink',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      // Design Premium: Material 3 com esquemas de cores refinados
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1), // Indigo vibrante
          brightness: Brightness.light,
          primary: const Color(0xFF4F46E5),
          secondary: const Color(0xFF06B6D4),
          background: const Color(0xFFF8FAFC),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
          primary: const Color(0xFF818CF8),
          secondary: const Color(0xFF22D3EE),
          background: const Color(0xFF0F172A), // Slate 900 (Visual Premium Dark)
          surface: const Color(0xFF1E293B), // Slate 800
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardTheme: CardTheme(
          color: const Color(0xFF1E293B),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}
