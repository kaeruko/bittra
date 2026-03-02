import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _teaserController = TextEditingController();
  final _bodyController = TextEditingController();

  @override
  void dispose() {
    _teaserController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      // For now, just show a snackbar and pop
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Starting BLE advertising with this message!')),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post to Venue')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _teaserController,
              decoration: const InputDecoration(
                labelText: 'Teaser (Required)',
                hintText: 'Max 8 characters',
                border: OutlineInputBorder(),
                helperText: 'Broadcasted to everyone nearby',
              ),
              maxLength: 8,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a teaser';
                }
                if (value.length > 8) {
                  return 'Teaser must be 8 characters or less';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _bodyController,
              decoration: const InputDecoration(
                labelText: 'Full Text (Optional)',
                hintText: 'Max 300 characters',
                border: OutlineInputBorder(),
                helperText: 'Sent only when someone requests it',
                alignLabelWithHint: true,
              ),
              maxLength: 300,
              maxLines: 8,
              validator: (value) {
                if (value != null && value.length > 300) {
                  return 'Full text must be 300 characters or less';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.podcasts),
              label: const Text('Broadcast to Venue'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

