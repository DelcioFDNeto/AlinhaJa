import 'package:supabase_flutter/supabase_flutter.dart';

/// Acesso global ao cliente Supabase.
/// Usar: `supabase.from('table').select()`
final supabase = Supabase.instance.client;
