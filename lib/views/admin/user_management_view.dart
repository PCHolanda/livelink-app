import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../services/supabase_service.dart';

class UserManagementView extends StatefulWidget {
  const UserManagementView({super.key});

  @override
  State<UserManagementView> createState() => _UserManagementViewState();
}

class _UserManagementViewState extends State<UserManagementView> {
  late Future<List<UserModel>> _usersFuture;
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _allUsers = [];
  List<UserModel> _filteredUsers = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadUsers() {
    final authService = Provider.of<SupabaseService>(context, listen: false);
    setState(() {
      _usersFuture = authService.getAllUsers().then((users) {
        _allUsers = users;
        _filteredUsers = users;
        return users;
      });
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredUsers = _allUsers.where((user) {
        return user.name.toLowerCase().contains(query) ||
            user.email.toLowerCase().contains(query);
      }).toList();
    });
  }

  // ==========================================
  // API CRUDS
  // ==========================================

  Future<void> _createUser(String name, String email, String password, String role) async {
    final service = Provider.of<SupabaseService>(context, listen: false);
    try {
      await service.adminCreateUser(
        email: email,
        password: password,
        name: name,
        role: role,
      );
      _showSuccessSnackBar('Usuário criado com sucesso!');
      _loadUsers();
    } catch (e) {
      _showErrorSnackBar('Falha ao criar usuário: $e');
    }
  }

  Future<void> _updateUser(String id, String name, String email, String role, bool active) async {
    final service = Provider.of<SupabaseService>(context, listen: false);
    try {
      await service.adminUpdateUser(
        id: id,
        email: email,
        name: name,
        role: role,
        active: active,
      );
      _showSuccessSnackBar('Usuário atualizado com sucesso!');
      _loadUsers();
    } catch (e) {
      _showErrorSnackBar('Falha ao atualizar usuário: $e');
    }
  }

  Future<void> _deleteUser(String id) async {
    final service = Provider.of<SupabaseService>(context, listen: false);
    try {
      await service.adminDeleteUser(id);
      _showSuccessSnackBar('Usuário removido com sucesso!');
      _loadUsers();
    } catch (e) {
      _showErrorSnackBar('Falha ao remover usuário: $e');
    }
  }

  Future<void> _resetPassword(String id, String newPassword) async {
    final service = Provider.of<SupabaseService>(context, listen: false);
    try {
      await service.adminResetPassword(id: id, newPassword: newPassword);
      _showSuccessSnackBar('Senha resetada com sucesso!');
    } catch (e) {
      _showErrorSnackBar('Falha ao resetar senha: $e');
    }
  }

  // Helper dialogs
  void _showSuccessSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }

  void _showErrorSnackBar(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
    );
  }

  // ==========================================
  // DIALOGS & OVERLAYS
  // ==========================================

  void _openCreateDialog() {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String role = 'broadcaster';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Adicionar Novo Usuário'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Nome Completo', prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) => v == null || v.isEmpty ? 'Informe o nome' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.email_outlined)),
                        validator: (v) => v == null || v.isEmpty ? 'Informe o e-mail' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Senha Inicial', prefixIcon: Icon(Icons.lock_outline)),
                        validator: (v) => v == null || v.length < 6 ? 'A senha precisa de pelo menos 6 caracteres' : null,
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        value: role,
                        decoration: const InputDecoration(labelText: 'Perfil / Permissão', prefixIcon: Icon(Icons.shield_outlined)),
                        items: const [
                          DropdownMenuItem(value: 'broadcaster', child: Text('Usuário Transmissor (Broadcaster)')),
                          DropdownMenuItem(value: 'admin', child: Text('Administrador')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              role = val;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      _createUser(nameCtrl.text.trim(), emailCtrl.text.trim(), passCtrl.text, role);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openEditDialog(UserModel user) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: user.name);
    final emailCtrl = TextEditingController(text: user.email);
    String role = user.role;
    bool active = user.active;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Editar Usuário'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Nome Completo', prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) => v == null || v.isEmpty ? 'Informe o nome' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.email_outlined)),
                        validator: (v) => v == null || v.isEmpty ? 'Informe o e-mail' : null,
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        value: role,
                        decoration: const InputDecoration(labelText: 'Perfil / Permissão', prefixIcon: Icon(Icons.shield_outlined)),
                        items: const [
                          DropdownMenuItem(value: 'broadcaster', child: Text('Usuário Transmissor')),
                          DropdownMenuItem(value: 'admin', child: Text('Administrador')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              role = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      SwitchListTile(
                        title: const Text('Conta Ativa'),
                        subtitle: Text(active ? 'Usuário autorizado a logar' : 'Acesso bloqueado na plataforma'),
                        value: active,
                        onChanged: (val) {
                          setDialogState(() {
                            active = val;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      _updateUser(user.id, nameCtrl.text.trim(), emailCtrl.text.trim(), role, active);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Salvar Alterações'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openResetPasswordDialog(UserModel user) {
    final formKey = GlobalKey<FormState>();
    final passCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Forçar Reset de Senha: ${user.name}'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Nova Senha',
                prefixIcon: Icon(Icons.lock_reset_rounded),
              ),
              validator: (v) => v == null || v.length < 6 ? 'Mínimo 6 caracteres' : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  _resetPassword(user.id, passCtrl.text);
                  Navigator.pop(context);
                }
              },
              child: const Text('Confirmar Novo Reset'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(UserModel user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Conta'),
        content: Text('Deseja realmente excluir a conta de "${user.name}"? Esta ação removerá permanentemente o usuário e todas as suas lives cadastradas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () {
              _deleteUser(user.id);
              Navigator.pop(context);
            },
            child: const Text('Excluir'),
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
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 768;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciamento de Usuários'),
        actions: [
          ElevatedButton.icon(
            onPressed: _openCreateDialog,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Novo Usuário'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Search Box
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Filtrar por nome ou e-mail...',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => _searchController.clear(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // User List
            Expanded(
              child: FutureBuilder<List<UserModel>>(
                future: _usersFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Erro ao carregar usuários: ${snapshot.error}'));
                  }
                  if (_filteredUsers.isEmpty) {
                    return const Center(child: Text('Nenhum usuário correspondente encontrado.'));
                  }

                  return isDesktop ? _buildDesktopTable(theme) : _buildMobileList(theme);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTable(ThemeData theme) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Nome')),
            DataColumn(label: Text('E-mail')),
            DataColumn(label: Text('Perfil')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Ações')),
          ],
          rows: _filteredUsers.map((user) {
            return DataRow(
              cells: [
                DataCell(Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text(user.email)),
                DataCell(_buildRoleChip(theme, user.role)),
                DataCell(_buildStatusIndicator(user.active)),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Editar',
                        onPressed: () => _openEditDialog(user),
                      ),
                      IconButton(
                        icon: const Icon(Icons.lock_reset_rounded),
                        tooltip: 'Resetar Senha',
                        onPressed: () => _openResetPasswordDialog(user),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                        tooltip: 'Excluir',
                        onPressed: () => _confirmDelete(user),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMobileList(ThemeData theme) {
    return ListView.builder(
      itemCount: _filteredUsers.length,
      itemBuilder: (context, index) {
        final user = _filteredUsers[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: user.active ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
              child: Icon(
                user.active ? Icons.person_rounded : Icons.person_off_rounded,
                color: user.active ? Colors.green : Colors.grey,
              ),
            ),
            title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(user.email),
            trailing: _buildRoleChip(theme, user.role),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openEditDialog(user),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Editar'),
                    ),
                    TextButton.icon(
                      onPressed: () => _openResetPasswordDialog(user),
                      icon: const Icon(Icons.lock_reset_rounded, size: 18),
                      label: const Text('Resetar Senha'),
                    ),
                    TextButton.icon(
                      onPressed: () => _confirmDelete(user),
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                      label: const Text('Excluir', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoleChip(ThemeData theme, String role) {
    final isAdmin = role == 'admin';
    return Chip(
      label: Text(
        isAdmin ? 'ADMINISTRADOR' : 'TRANSMISSOR',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isAdmin ? Colors.purple : Colors.indigo,
        ),
      ),
      backgroundColor: isAdmin ? Colors.purple.withOpacity(0.1) : Colors.indigo.withOpacity(0.1),
      side: BorderSide.none,
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildStatusIndicator(bool active) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Colors.green : Colors.grey,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          active ? 'Ativo' : 'Inativo',
          style: TextStyle(color: active ? Colors.green : Colors.grey, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
