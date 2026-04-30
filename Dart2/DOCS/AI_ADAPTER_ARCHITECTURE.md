# Arquitectura de adaptadores de IA en Dart2

## Objetivo

Tomar el enfoque de herramientas tipo NanoClaw y aplicarlo al bot Dart que ya funciona: separar la logica de WhatsApp de la logica de IA, para poder cambiar de proveedor sin reescribir el bot.

La idea no es copiar NanoClaw linea por linea. La idea es usar su enfoque:

- un contrato comun para proveedores de IA;
- implementaciones intercambiables;
- un servicio central que el bot consume;
- cero dependencia de Node/npm.

## Estructura

Dentro de `Dart2/whatsapp_web_puppeteer/lib`:

```text
ai/
  ai_provider.dart
  ai_service.dart
  providers/
    ollama_provider.dart
```

## `AIProvider`

`AIProvider` es el contrato minimo que debe cumplir cualquier proveedor:

```dart
abstract interface class AIProvider {
  Future<String> generateResponse(String prompt);
}
```

Si mañana se agrega OpenAI, Anthropic, Gemini u otro motor local, solo debe implementar ese metodo.

## `OllamaProvider`

`OllamaProvider` implementa `AIProvider` usando HTTP contra Ollama local:

- URL por defecto: `http://localhost:11434`
- endpoint: `/api/generate`
- modo: `stream: false`
- modelo configurable por variable de entorno `OLLAMA_MODEL`

Ejemplo conceptual:

```dart
final provider = OllamaProvider(model: 'llama3.2:3b');
final text = await provider.generateResponse('Hola');
```

## `AIService`

`AIService` es la capa que usa el bot. Recibe un `AIProvider` y construye un prompt de sistema sencillo:

- responder en español;
- ser breve;
- no inventar disponibilidad, precios ni datos medicos;
- pedir datos minimos si el usuario quiere agendar;
- ofrecer pasar a humano si falta informacion.

El bot no conoce detalles de Ollama. Solo hace:

```dart
final reply = await aiService.getResponse(body);
```

## Integracion con WhatsApp

Antes el bot tenia respuesta fija:

```dart
final reply = body.toLowerCase() == 'ping' ? 'pong' : 'Recibido: $body';
```

Ahora el handler de mensajes llama a la IA:

```dart
final reply = await aiService.getResponse(body);
await _sendReply(client, to: from, message: reply, replyMessageId: id);
```

Esto deja la puerta abierta para respuestas dinamicas y para cambiar proveedor sin tocar el codigo de WhatsApp.

## Recepcion de mensajes: evento + polling

El camino principal sigue siendo el evento de WA-JS:

```dart
client.on(WhatsappEvent.chatNewMessage, ...);
```

En la prueba posterior, WhatsApp Web quedo conectado pero al enviar un mensaje no aparecia ningun `[RX]`. Eso significa que el evento no siempre se dispara en esta combinacion de WhatsApp Web + WA-JS + Puppeteer.

Para no depender de un solo mecanismo, el bot ahora tambien tiene un respaldo:

- cada 3 segundos consulta chats de usuario con `unreadCount > 0`;
- toma los ultimos mensajes entrantes;
- evita duplicados con un set de ids ya procesados;
- si detecta algo por esta ruta, imprime `[RX/poll]`.

Esto mantiene el codigo simple y hace al bot mas tolerante a cambios de WhatsApp Web.

## Configuracion de Ollama

Variables soportadas:

```powershell
$env:OLLAMA_BASE_URL="http://localhost:11434"
$env:OLLAMA_MODEL="llama3.2:3b"
dart run
```

Si el modelo no existe:

```powershell
ollama pull llama3.2:3b
```

O puedes probar otro modelo compatible con tu Windows, por ejemplo:

```powershell
ollama pull qwen2.5:3b
$env:OLLAMA_MODEL="qwen2.5:3b"
dart run
```

## Por que esta separacion ayuda

- WhatsApp queda en una capa.
- IA queda en otra capa.
- Ollama es solo una implementacion.
- Agregar OpenAI despues seria crear `OpenAIProvider` sin romper el bot.
- El bot puede seguir funcionando con otro proveedor si Ollama no conviene.

## Limitaciones actuales

- No hay memoria conversacional persistida todavia.
- No hay tool calling ni integracion con agenda real.
- El prompt de sistema es basico y debe afinarse cuando exista base de conocimiento o Supabase.
- Si Ollama no esta corriendo, el bot manda un fallback informativo.
- El polling es un respaldo pragmatico; cuando WA-JS entregue eventos de forma estable, el evento sigue siendo el camino preferido.
