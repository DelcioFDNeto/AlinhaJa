/// Contrato único do campo `metadata` (JSONB) para mensagens estruturadas.
///
/// Chat 1:1/grupo e canais gravam em tabelas diferentes (`messages` e
/// `channel_messages`), mas o formato do metadata é o mesmo — é o que permite
/// que os cards de enquete, evento, localização e contato sejam um só widget
/// para os dois lados.
///
/// O `content_type` no banco continua sendo `text`: o enum do Postgres só
/// aceita text/image/audio/file/video/meeting, então o discriminador real é a
/// chave `type` daqui.
library;

class MessageExtras {
  MessageExtras._();

  static const String typePoll = 'poll';
  static const String typeEvent = 'date_event';
  static const String typeLocation = 'location';
  static const String typeContact = 'contact';
  static const String typeMeeting = 'meeting';
  static const String typeAnnouncement = 'announcement';
  static const String typeWhiteboard = 'whiteboard';

  /// Quadro branco colaborativo. O desenho vive em `whiteboard_strokes`; a
  /// mensagem é só a porta de entrada.
  static Map<String, dynamic> whiteboard({
    required String boardId,
    required String title,
  }) =>
      {
        'type': typeWhiteboard,
        'whiteboard_id': boardId,
        'whiteboard_title': title,
      };

  /// Enquete: a pergunta vai no `content` da mensagem.
  static Map<String, dynamic> poll({
    required List<String> options,
    bool multipleChoice = false,
  }) =>
      {
        'type': typePoll,
        'options': options,
        if (multipleChoice) 'multiple_choice': true,
      };

  /// Evento com data/hora. O título vai no `content` (prefixado com 📅 para
  /// prévias de lista) e repetido em `event_title` para o card renderizar limpo.
  static Map<String, dynamic> event({
    required String title,
    required DateTime date,
  }) =>
      {
        'type': typeEvent,
        'event_title': title,
        'event_date': date.toIso8601String(),
      };

  static Map<String, dynamic> location({
    required double latitude,
    required double longitude,
    double? accuracy,
    String? label,
  }) =>
      {
        'type': typeLocation,
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        if (label != null && label.isNotEmpty) 'label': label,
      };

  static Map<String, dynamic> contact({
    required String userId,
    required String name,
    String? subtitle,
    String? phone,
    String? email,
    String? avatarUrl,
  }) =>
      {
        'type': typeContact,
        'contact_id': userId,
        'contact_name': name,
        if (subtitle != null && subtitle.isNotEmpty) 'contact_subtitle': subtitle,
        if (phone != null && phone.isNotEmpty) 'contact_phone': phone,
        if (email != null && email.isNotEmpty) 'contact_email': email,
        if (avatarUrl != null && avatarUrl.isNotEmpty) 'contact_avatar': avatarUrl,
      };
}

/// Leitura tolerante do metadata cru. Aceita número em string, lista de
/// dynamic e chaves ausentes sem estourar — o JSONB vem de várias origens
/// (app antigo, bot, webhook) e nem sempre está no formato ideal.
extension MessageExtrasReader on Map<String, dynamic> {
  String? get extraType => this['type']?.toString();

  bool get isPoll => extraType == MessageExtras.typePoll || this['options'] is List;
  bool get isEvent => extraType == MessageExtras.typeEvent || this['event_date'] != null;
  bool get isLocation =>
      extraType == MessageExtras.typeLocation || (latitude != null && longitude != null);
  bool get isContact =>
      extraType == MessageExtras.typeContact ||
      contactId != null ||
      contactName != null;

  bool get isWhiteboard =>
      extraType == MessageExtras.typeWhiteboard || whiteboardId != null;

  /// Qualquer card estruturado que substitui o corpo de texto da bolha.
  bool get isStructured =>
      isPoll || isEvent || isLocation || isContact || isWhiteboard;

  String? get whiteboardId => this['whiteboard_id']?.toString();
  String? get whiteboardTitle => this['whiteboard_title']?.toString();

  List<String> get pollOptions => this['options'] is List
      ? (this['options'] as List).map((e) => e.toString()).toList()
      : const [];

  bool get pollAllowsMultiple => this['multiple_choice'] == true;

  String? get eventTitle => this['event_title']?.toString();

  DateTime? get eventDate {
    final raw = this['event_date']?.toString();
    return raw == null ? null : DateTime.tryParse(raw);
  }

  double? get latitude => _asDouble(this['latitude'] ?? this['lat']);
  double? get longitude => _asDouble(this['longitude'] ?? this['lng'] ?? this['lon']);
  double? get locationAccuracy => _asDouble(this['accuracy']);
  String? get locationLabel => this['label']?.toString();

  String? get contactId =>
      this['contact_id']?.toString() ??
      this['user_id']?.toString() ??
      this['userId']?.toString();

  String? get contactName =>
      this['contact_name']?.toString() ?? this['name']?.toString();

  String? get contactSubtitle =>
      this['contact_subtitle']?.toString() ?? this['subtitle']?.toString();

  String? get contactPhone =>
      this['contact_phone']?.toString() ?? this['phone']?.toString();

  String? get contactEmail =>
      this['contact_email']?.toString() ?? this['email']?.toString();

  String? get contactAvatar =>
      this['contact_avatar']?.toString() ??
      this['avatar_url']?.toString() ??
      this['avatarUrl']?.toString();
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
