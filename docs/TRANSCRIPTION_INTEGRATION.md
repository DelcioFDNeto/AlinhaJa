# Integração de Transcrição IA com N8N

## Visão Geral

Este documento explica como implementar a transcrição de reuniões usando:
- **Agora Cloud Recording** - para gravar chamadas
- **N8N** - para orquestrar o fluxo de transcrição
- **Supabase** - para armazenar transcrições

---

## 1. Cloud Recording do Agora

### Opções de Recording

| Modo | Descrição | Uso |
|------|-----------|-----|
| **Composite** | Combina todos os streams em um único arquivo | Reuniões |
| **Individual** | Grava cada stream separadamente | Análise por participante |
| **Audio Only** | Grava apenas áudio | Transcrição pura |

### Implementação no Flutter

O Agora Flutter SDK não tem Cloud Recording nativo. É necessário usar a **REST API** do lado do servidor.

```dart
// No Flutter: inicia recording via API backend
class RecordingService {
  static Future<void> startRecording({
    required String channelName,
    required String recordingUid,
  }) async {
    // POST para seu backend
    await http.post(
      Uri.parse('https://seu-backend.com/api/recording/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'channelName': channelName,
        'uid': recordingUid,
        'type': 'composite',
      }),
    );
  }

  static Future<void> stopRecording({
    required String channelName,
    required String resourceId,
    required String sessionId,
  }) async {
    await http.post(
      Uri.parse('https://seu-backend.com/api/recording/stop'),
      body: jsonEncode({
        'channelName': channelName,
        'resourceId': resourceId,
        'sessionId': sessionId,
      }),
    );
  }
}
```

### Backend (Node.js/Express)

```javascript
// Backend que chama a API REST do Agora
app.post('/api/recording/start', async (req, res) => {
  const { channelName, uid, type } = req.body;
  
  const response = await axios.post(
    `https://api.agora.io/v1/apps/${process.env.AGORA_APP_ID}/cloud_recording/resourceid`,
    {
      cname: channelName,
      uid: uid,
      clientRequest: {
        recordingConfig: {
          maxIdleTime: 300,
          streamTypes: type === 'audio' ? 0 : 2,
          audioProfile: 1,
        },
        storageConfig: {
          vendor: 1, // AWS
          region: 1,
          bucket: process.env.AGORA_BUCKET,
        },
      }
    },
    {
      headers: {
        'Authorization': `Basic ${Buffer.from(`${process.env.AGORA_APP_ID}:${process.env.AGORA_APP_CERT}`).toString('base64')}`,
        'Content-Type': 'application/json'
      }
    }
  );
  
  const resourceId = response.data.resourceId;
  // Salvar resourceId no banco para usar no stop
  await db.saveRecordingSession({ channelName, resourceId });
  
  // Iniciar a sessão
  await axios.post(
    `https://api.agora.io/v1/apps/${process.env.AGORA_APP_ID}/cloud_recording/mode/composite/start`,
    {
      cname: channelName,
      uid: uid,
      resourceId: resourceId,
      clientRequest: {
        recordingConfig: {
          maxIdleTime: 300,
          streamTypes: 2,
        },
        storageConfig: {
          vendor: 1,
          bucket: process.env.AGORA_BUCKET,
        }
      }
    }
  );
  
  res.json({ success: true, resourceId });
});
```

---

## 2. Configuração N8N

### Opção A: PostgreSQL Trigger (Recomendado)

O N8N tem nó de **PostgreSQL Trigger** que escuta diretamente o banco:

```
┌──────────────────┐
│  PostgreSQL      │
│  Trigger         │ ← Escuta tabela "calls" ou "meetings"
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  HTTP Request    │ ← Baixa gravação do S3/Agora
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  AI / Whisper    │ ← Transcreve áudio
│  (OpenAI/本地)    │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Supabase        │ ← Salva na tabela
│  (Insert)        │   meeting_transcriptions
└──────────────────┘
```

### Configuração do Nodo PostgreSQL Trigger:

1. **Credential**: Conectar ao Supabase (PostgreSQL)
2. **Table**: `calls` (ou criar função que notifica)
3. **Event**: `UPDATE`
4. **WHERE**: `status = 'ended'`

### Fluxo N8N:

```javascript
// 1. PostgreSQL Trigger
{
  "table": "calls",
  "filter": "status = 'ended'"
}

// 2. HTTP Request (baixa áudio do S3)
{
  "url": "https://{{ $json.bucket_url }}",
  "method": "GET",
  "authentication": "genericCredentialType",
  "genericAuthType": "httpHeaderAuth"
}

// 3. OpenAI Whisper (transcreve)
{
  "operation": "transcribe",
  "file": "{{ $json.audio }}",
  "model": "whisper-1",
  "language": "pt-BR"
}

// 4. Supabase (insere transcrição)
{
  "operation": "insert",
  "table": "meeting_transcriptions",
  "meeting_id": "{{ $json.meeting_id }}",
  "user_id": "{{ $json.caller_id }}",
  "content": "{{ $json.transcription }}",
  "is_final": true
}
```

### Opção B: Supabase Realtime

Se preferir usar Realtime (mais leve):

```
Supabase Realtime → Webhook → N8N
```

---

## 3. Tabelas Criadas

### meetings (027)
```sql
-- já criado em supabase/migrations/027_create_meetings_table.sql
```

### meeting_transcriptions (028)
```sql
-- já criado em supabase/migrations/028_create_meeting_transcriptions.sql
```

### Trigger (029)
```sql
-- já criado em supabase/migrations/029_create_meeting_webhook_trigger.sql
```

---

## 4. Próximos Passos

| Passo | Ação | Prioridade |
|-------|------|------------|
| 1 | Executar as 3 migrations no Supabase | Alta |
| 2 | Configurar bucket S3 na AWS/Space para gravações | Alta |
| 3 | Criar endpoint backend para Cloud Recording API | Alta |
| 4 | Configurar N8N com PostgreSQL Trigger | Média |
| 5 | Integrar OpenAI Whisper para transcrição | Média |
| 6 | Exibir transcrição no Flutter | Baixa |

---

## 5. Referências

- [Agora Cloud Recording Docs](https://docs.agora.io/en/cloud-recording/get-started/getstarted)
- [N8N PostgreSQL Trigger](https://docs.n8n.io/integrations/builtin/trigger-nodes/n8n-nodes-base.postgrestrigger/)
- [Supabase Realtime](https://supabase.com/docs/guides/realtime/postgres-changes)
- [OpenAI Whisper API](https://platform.openai.com/docs/guides/speech-to-text)
