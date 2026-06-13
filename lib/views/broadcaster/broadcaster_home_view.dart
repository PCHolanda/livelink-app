import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../models/live_model.dart';
import '../../services/supabase_service.dart';

class BroadcasterHomeView extends StatefulWidget {
  const BroadcasterHomeView({super.key});

  @override
  State<BroadcasterHomeView> createState() => _BroadcasterHomeViewState();
}

class _BroadcasterHomeViewState extends State<BroadcasterHomeView> {
  final TextEditingController _titleController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  // ==========================================
  // STREAM CREATION & ACTIONS
  // ==========================================

  Future<void> _handleCreateLive() async {
    if (!_formKey.currentState!.validate()) return;

    final service = Provider.of<SupabaseService>(context, listen: false);

    try {
      final newLive = await service.createLive(_titleController.text.trim());
      _titleController.clear();
      if (mounted) {
        Navigator.pop(context); // Close inputs dialog
        _showShareOptionsDialog(newLive);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao criar live: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  String _buildLiveUrl(String slug) {
    // Generate public link. Dynamic host detection.
    final origin = Uri.base.origin;
    // Fallback if not web or empty
    if (origin.isEmpty || origin == 'null') {
      return 'https://livelink.app/live/$slug';
    }
    return '$origin/live/$slug';
  }

  void _showShareOptionsDialog(LiveModel live) {
    final theme = Theme.of(context);
    final publicLink = _buildLiveUrl(live.slug);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('Transmissão Criada!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A sala foi configurada com sucesso. Compartilhe o link exclusivo abaixo para que os espectadores assistam em tempo real sem necessidade de login:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            // Link box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.06),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                publicLink,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: publicLink));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copiado para a área de transferência!')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copiar Link'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366), // WhatsApp Green
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      Share.share(
                        'Assista à minha transmissão ao vivo "${live.title}" no LiveLink: $publicLink',
                      );
                    },
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('WhatsApp'),
                  ),
                ),
              ],
            )
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar para o Painel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context); // close dialog
              context.push('/broadcaster/stream/${live.id}');
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Iniciar Transmissão'),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openCreateLiveDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Criar Nova Transmissão'),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Título da Live',
              hintText: 'Ex: Aula de Flutter Avançado',
              prefixIcon: Icon(Icons.title_rounded),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Insira um título para a live' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: _handleCreateLive,
            child: const Text('Criar'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // VIEW BUILDERS
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = Provider.of<SupabaseService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.sensors_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(width: 8),
            Text(
              'LiveLink Broadcaster',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async => await authService.signOut(),
            tooltip: 'Sair da Conta',
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Olá, ${authService.currentUser?.name ?? 'Transmissor'} 👋',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pronto para iniciar uma nova transmissão ao vivo?',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                  onPressed: _openCreateLiveDialog,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'Criar Live',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 36),
            Text(
              'Histórico de Transmissões',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Dynamic Stream History
            StreamBuilder<List<LiveModel>>(
              stream: authService.streamLivesHistory(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40.0),
                    child: Center(child: Text('Erro ao carregar histórico: ${snapshot.error}')),
                  );
                }

                final lives = snapshot.data!;
                if (lives.isEmpty) {
                  return _buildEmptyHistoryCard(theme);
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: lives.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final live = lives[index];
                    return _buildLiveHistoryTile(theme, live);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHistoryCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60.0, horizontal: 24.0),
        child: Column(
          children: [
            Icon(Icons.video_camera_back_rounded, size: 64, color: theme.hintColor.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text(
              'Nenhuma live encontrada',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Crie uma transmissão clicando no botão "Criar Live" no canto superior.',
              style: TextStyle(color: theme.hintColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveHistoryTile(ThemeData theme, LiveModel live) {
    final duration = _calculateDuration(live.startedAt, live.endedAt);
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(live.createdAt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Row(
          children: [
            // Status Icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getStatusColor(live.status).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getStatusIcon(live.status),
                color: _getStatusColor(live.status),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            // Info text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    live.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Criada em: $dateStr • ${live.slug}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                  const SizedBox(height: 4),
                  if (live.isEnded)
                    Text(
                      'Duração: $duration • Pico de espectadores: ${live.maxViewers}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    )
                  else if (live.isLive)
                    Text(
                      'Transmissão ao vivo agora! • Assistindo: ${live.currentViewers}',
                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12),
                    )
                  else
                    Text(
                      'Aguardando início da transmissão',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Actions
            if (live.isIdle)
              ElevatedButton.icon(
                onPressed: () => context.push('/broadcaster/stream/${live.id}'),
                icon: const Icon(Icons.videocam_rounded, size: 16),
                label: const Text('Transmitir'),
              )
            else if (live.isLive)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                onPressed: () => context.push('/broadcaster/stream/${live.id}'),
                icon: const Icon(Icons.live_tv_rounded, size: 16),
                label: const Text('Retornar'),
              )
            else
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Compartilhar Link Público',
                onPressed: () {
                  final publicLink = _buildLiveUrl(live.slug);
                  Share.share('Assista à gravação/detalhes da live "${live.title}": $publicLink');
                },
              ),
          ],
        ),
      ),
    );
  }

  String _calculateDuration(DateTime? start, DateTime? end) {
    if (start == null || end == null) return 'N/A';
    final diff = end.difference(start);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'idle':
        return Colors.orange;
      case 'live':
        return Colors.redAccent;
      case 'ended':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'idle':
        return Icons.hourglass_empty_rounded;
      case 'live':
        return Icons.sensors_rounded;
      case 'ended':
        return Icons.check_circle_outline_rounded;
      default:
        return Icons.video_call_rounded;
    }
  }
}
