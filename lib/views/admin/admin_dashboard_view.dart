import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../services/supabase_service.dart';

class AdminDashboardView extends StatefulWidget {
  const AdminDashboardView({super.key});

  @override
  State<AdminDashboardView> createState() => _AdminDashboardViewState();
}

class _AdminDashboardViewState extends State<AdminDashboardView> {
  late Future<Map<String, dynamic>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _refreshStats();
  }

  void _refreshStats() {
    setState(() {
      _statsFuture = Provider.of<SupabaseService>(context, listen: false).fetchDashboardStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;
    final authService = Provider.of<SupabaseService>(context);

    // Sidebar navigation items
    final drawerItems = [
      ListTile(
        leading: const Icon(Icons.dashboard_rounded),
        title: const Text('Dashboard'),
        selected: true,
        onTap: () => Navigator.pop(context),
      ),
      ListTile(
        leading: const Icon(Icons.people_alt_rounded),
        title: const Text('Gerenciar Usuários'),
        onTap: () {
          Navigator.pop(context);
          context.push('/admin/users');
        },
      ),
      ListTile(
        leading: const Icon(Icons.sensors_rounded),
        title: const Text('Área do Transmissor'),
        onTap: () {
          Navigator.pop(context);
          context.push('/broadcaster');
        },
      ),
      ListTile(
        leading: const Icon(Icons.logout_rounded),
        title: const Text('Sair'),
        onTap: () async {
          await authService.signOut();
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.admin_panel_settings_rounded, size: 28),
            const SizedBox(width: 8),
            Text(
              'Painel Administrativo',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshStats,
            tooltip: 'Atualizar Dados',
          ),
          if (!isDesktop)
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: () async => await authService.signOut(),
              tooltip: 'Sair',
            ),
          const SizedBox(width: 12),
        ],
      ),
      drawer: isDesktop
          ? null
          : Drawer(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const CircleAvatar(
                          backgroundColor: Colors.white,
                          child: Icon(Icons.person_rounded, color: Colors.blue),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          authService.currentUser?.name ?? 'Administrador',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          authService.currentUser?.email ?? '',
                          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  ...drawerItems,
                ],
              ),
            ),
      body: Row(
        children: [
          // Permanent Sidebar on Desktop
          if (isDesktop)
            Container(
              width: 260,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: theme.dividerColor, width: 0.5)),
                color: theme.cardColor,
              ),
              child: Column(
                children: [
                  UserAccountsDrawerHeader(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
                    ),
                    currentAccountPicture: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                      child: Text(
                        authService.currentUser?.name.substring(0, 1).toUpperCase() ?? 'A',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                      ),
                    ),
                    accountName: Text(
                      authService.currentUser?.name ?? 'Admin',
                      style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
                    ),
                    accountEmail: Text(
                      authService.currentUser?.email ?? '',
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.dashboard_rounded),
                          title: const Text('Dashboard'),
                          selected: true,
                          selectedColor: theme.colorScheme.primary,
                          selectedTileColor: theme.colorScheme.primary.withOpacity(0.08),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          onTap: () {},
                        ),
                        const SizedBox(height: 4),
                        ListTile(
                          leading: const Icon(Icons.people_alt_rounded),
                          title: const Text('Gerenciar Usuários'),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          onTap: () => context.push('/admin/users'),
                        ),
                        const SizedBox(height: 4),
                        ListTile(
                          leading: const Icon(Icons.sensors_rounded),
                          title: const Text('Área do Transmissor'),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          onTap: () => context.push('/broadcaster'),
                        ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.logout_rounded),
                          title: const Text('Sair'),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          onTap: () async => await authService.signOut(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // Main Dashboard Page
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _statsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 60, color: Colors.redAccent),
                        const SizedBox(height: 16),
                        Text('Erro ao carregar indicadores: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _refreshStats,
                          child: const Text('Tentar Novamente'),
                        )
                      ],
                    ),
                  );
                }

                final stats = snapshot.data!;
                final ranking = stats['ranking'] as List<dynamic>;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Indicadores da Plataforma',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      // Responsive Grid of KPI Cards
                      GridView.count(
                        crossAxisCount: isDesktop ? 4 : (size.width > 600 ? 2 : 1),
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 1.5,
                        children: [
                          _buildKpiCard(
                            context,
                            title: 'Total de Usuários',
                            value: '${stats['totalUsers']}',
                            subtitle: 'Ativos: ${stats['activeUsers']}',
                            icon: Icons.people_rounded,
                            color: Colors.indigo,
                          ),
                          _buildKpiCard(
                            context,
                            title: 'Transmissões',
                            value: '${stats['totalLives']}',
                            subtitle: 'Em andamento: ${stats['livesInProgress']}',
                            icon: Icons.video_call_rounded,
                            color: Colors.redAccent,
                          ),
                          _buildKpiCard(
                            context,
                            title: 'Total de Espectadores',
                            value: '${stats['totalViewers']}',
                            subtitle: 'Picos acumulados',
                            icon: Icons.visibility_rounded,
                            color: Colors.cyan,
                          ),
                          _buildKpiCard(
                            context,
                            title: 'Horas Transmitidas',
                            value: '${stats['totalHours']}h',
                            subtitle: 'Consumo: ${stats['bandwidthGB']} GB',
                            icon: Icons.schedule_rounded,
                            color: Colors.amber,
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Ranking section
                          Expanded(
                            flex: isDesktop ? 3 : 1,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ranking de Transmissores',
                                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Por pico de espectadores nas lives',
                                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                                    ),
                                    const SizedBox(height: 20),
                                    if (ranking.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 40.0),
                                        child: Center(
                                          child: Text('Nenhuma transmissão realizada até o momento.'),
                                        ),
                                      )
                                    else
                                      ListView.separated(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: ranking.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                                        itemBuilder: (context, index) {
                                          final item = ranking[index];
                                          final maxVal = (ranking[0]['audience'] as int);
                                          final percentage = maxVal > 0 ? (item['audience'] as int) / maxVal : 0.0;

                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    '${index + 1}. ${item['name']}',
                                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                                  ),
                                                  Text(
                                                    '${item['audience']} espectadores',
                                                    style: TextStyle(
                                                      color: theme.colorScheme.primary,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Stack(
                                                children: [
                                                  Container(
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      color: theme.colorScheme.primary.withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                  ),
                                                  FractionallySizedBox(
                                                    widthFactor: percentage.clamp(0.02, 1.0),
                                                    child: Container(
                                                      height: 8,
                                                      decoration: BoxDecoration(
                                                        color: theme.colorScheme.primary,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Logs section (desktop only)
                          if (isDesktop) ...[
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 4,
                              child: _buildRecentAuditLogsSection(theme),
                            ),
                          ],
                        ],
                      ),
                      if (!isDesktop) ...[
                        const SizedBox(height: 20),
                        _buildRecentAuditLogsSection(theme),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onBackground.withOpacity(0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentAuditLogsSection(ThemeData theme) {
    final authService = Provider.of<SupabaseService>(context, listen: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Registro de Atividades (Auditoria)',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Icon(Icons.history_toggle_off_rounded, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 20),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: authService.getAuditLogs(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 150,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('Erro ao carregar logs: ${snapshot.error}'),
                  );
                }

                final logs = snapshot.data!;
                if (logs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.0),
                    child: Center(child: Text('Nenhuma atividade recente registrada.')),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: logs.take(5).length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final creatorData = log['users'];
                    final userName = creatorData != null ? creatorData['name'] as String : 'Sistema';
                    final date = DateTime.parse(log['created_at'] as String);

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        log['action'] as String,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        'Por: $userName • ${_formatDate(date)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                      ),
                      leading: const CircleAvatar(
                        radius: 16,
                        child: Icon(Icons.info_outline_rounded, size: 16),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    // Basic date formatting helper
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
