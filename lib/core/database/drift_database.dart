import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'drift_database.g.dart';

// 1. Cache de metadados de mídia
class MediaCache extends Table {
  TextColumn get id => text()(); // UUID da mensagem ou da mídia
  TextColumn get remoteUrl => text()(); // URL no Supabase Storage
  TextColumn get localPath =>
      text().nullable()(); // Caminho no disco (null na Web)
  TextColumn get mediaType =>
      text()(); // 'image', 'video', 'audio', 'sticker', 'document'
  IntColumn get sizeBytes => integer()(); // Tamanho em bytes
  TextColumn get chatId => text()(); // ID do chat/canal de origem
  DateTimeColumn get downloadedAt => dateTime()();
  DateTimeColumn get lastAccessedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// 2. Backup local de mensagens (espelho do Supabase)
class LocalMessages extends Table {
  TextColumn get id => text()(); // UUID da mensagem
  /// Conta que sincronizou esta linha.
  ///
  /// Sem esta coluna o espelho era anônimo: num aparelho compartilhado ele
  /// acumulava o que a RLS de cada usuário que passou por ali permitiu, e a
  /// exportação levava conversa de terceiro junto. Toda leitura do espelho
  /// filtra por aqui, e a troca de conta apaga o que não é do titular atual.
  TextColumn get ownerId => text().withDefault(const Constant(''))();
  TextColumn get chatId => text()(); // chat_id ou channel_id
  TextColumn get senderId => text()();
  TextColumn get content => text().nullable()();
  TextColumn get contentType => text().withDefault(const Constant('text'))();
  TextColumn get mediaUrl => text().nullable()();
  TextColumn get metadata => text().nullable()(); // JSON serializado
  BoolColumn get isChannel => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get syncedAt =>
      dateTime().nullable()(); // Quando foi sincronizado com servidor

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [MediaCache, LocalMessages])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(
    name: 'alinhaja_db',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  ));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // O espelho da v1 não registra a quem cada linha pertence e foi
            // alimentado por todas as contas que usaram o aparelho. Como não
            // há como atribuí-lo com segurança, ele é descartado: manter dado
            // de terceiro sem dono identificável é o defeito que a v2 corrige.
            await m.deleteTable('local_messages');
            await m.createTable(localMessages);
          }
        },
      );
}

// Instância global para uso no app
final driftDb = AppDatabase();
