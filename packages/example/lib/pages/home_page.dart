import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visual Loop Demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _Tile(
            label: '/login',
            onTap: () => Navigator.pushNamed(context, '/login'),
          ),
          _Tile(
            label: '/product/detail',
            onTap: () => Navigator.pushNamed(
              context,
              '/product/detail',
              arguments: <String, Object?>{'id': 'P-100'},
            ),
          ),
          _Tile(
            label: '/order/detail',
            onTap: () => Navigator.pushNamed(
              context,
              '/order/detail',
              arguments: <String, Object?>{'id': 'ORD-001'},
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
