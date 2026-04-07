import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../domain/entities/supplier.dart';
import '../providers/supplier_providers.dart';

class SupplierFormPage extends ConsumerStatefulWidget {
  const SupplierFormPage({super.key, this.initialSupplier});

  final Supplier? initialSupplier;

  @override
  ConsumerState<SupplierFormPage> createState() => _SupplierFormPageState();
}

class _SupplierFormPageState extends ConsumerState<SupplierFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _tradeNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _documentController;
  late final TextEditingController _contactController;
  late final TextEditingController _notesController;
  late bool _isActive;
  bool _isSaving = false;

  bool get _isEditing => widget.initialSupplier != null;

  @override
  void initState() {
    super.initState();
    final supplier = widget.initialSupplier;
    _nameController = TextEditingController(text: supplier?.name ?? '');
    _tradeNameController = TextEditingController(
      text: supplier?.tradeName ?? '',
    );
    _phoneController = TextEditingController(text: supplier?.phone ?? '');
    _emailController = TextEditingController(text: supplier?.email ?? '');
    _addressController = TextEditingController(text: supplier?.address ?? '');
    _documentController = TextEditingController(text: supplier?.document ?? '');
    _contactController = TextEditingController(
      text: supplier?.contactPerson ?? '',
    );
    _notesController = TextEditingController(text: supplier?.notes ?? '');
    _isActive = supplier?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tradeNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _documentController.dispose();
    _contactController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar fornecedor' : 'Novo fornecedor'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome'),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Informe o nome do fornecedor';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tradeNameController,
              decoration: const InputDecoration(
                labelText: 'Nome fantasia',
                hintText: 'Opcional',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Telefone',
                hintText: 'Opcional',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                hintText: 'Opcional',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _documentController,
              decoration: const InputDecoration(
                labelText: 'Documento',
                hintText: 'CPF, CNPJ ou referencia interna',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _contactController,
              decoration: const InputDecoration(
                labelText: 'Contato responsavel',
                hintText: 'Opcional',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Endereco',
                hintText: 'Opcional',
              ),
              minLines: 2,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Observacao',
                hintText: 'Opcional',
              ),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              title: const Text('Fornecedor ativo'),
              onChanged: (value) => setState(() => _isActive = value),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: Text(
                _isEditing ? 'Salvar alteracoes' : 'Criar fornecedor',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(supplierRepositoryProvider);
      final input = SupplierInput(
        name: _nameController.text,
        tradeName: _tradeNameController.text,
        phone: _phoneController.text,
        email: _emailController.text,
        address: _addressController.text,
        document: _documentController.text,
        contactPerson: _contactController.text,
        notes: _notesController.text,
        isActive: _isActive,
      );

      if (_isEditing) {
        await repository.update(widget.initialSupplier!.id, input);
      } else {
        await repository.create(input);
      }

      ref.invalidate(supplierListProvider);
      ref.read(appDataRefreshProvider.notifier).state++;

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar fornecedor: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
