import 'package:flutter/material.dart';

class FinanceDashboardScreen extends StatelessWidget {
  const FinanceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visão Geral Financeira')),
      body: const Center(
        child: Text('Dashboard Financeiro em construção (Fase 10).'),
      ),
    );
  }
}
