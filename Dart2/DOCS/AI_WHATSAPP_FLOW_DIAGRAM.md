# Diagrama del bot WhatsApp + IA local

Este documento explica, a nivel ejecutivo, que hace el nuevo bot Dart2 y donde entra la IA local.

## Idea principal

El bot usa WhatsApp Web para recibir/enviar mensajes, pero usa una capa de IA local para generar respuestas. La IA no se llama directo desde WhatsApp: el mensaje pasa primero por el bot Dart, luego por un servicio generico de IA, y finalmente por Ollama local.

## Diagrama de flujo

```mermaid
flowchart TD
    A[Persona escribe por WhatsApp] --> B[WhatsApp / WhatsApp Web]
    B --> C[Chrome controlado por Dart + Puppeteer]
    C --> D[Bot Dart2 whatsapp_web_puppeteer]

    D --> E{Recepcion del mensaje}
    E -->|Evento WA-JS| F[chat.new_message]
    E -->|Respaldo| G[Polling chats no leidos cada 3s]
    F --> H[Normalizar mensaje]
    G --> H

    H --> I[AIService]
    I --> J[Construye prompt de sistema + mensaje del usuario]
    J --> K[AIProvider contrato generico]
    K --> L[OllamaProvider]
    L --> M[HTTP local localhost:11434]
    M --> N[Ollama local]
    N --> O[Modelo LLM local llama3.2 / qwen / mistral]
    O --> N
    N --> L
    L --> I

    I --> P[Respuesta generada]
    P --> Q[Enviar respuesta por WA-JS]
    Q --> B
    B --> R[Persona recibe respuesta en WhatsApp]
```

## Que queda local y que usa internet

```mermaid
flowchart LR
    subgraph Internet
      W[WhatsApp / servidores Meta]
    end

    subgraph Maquina local
      C[Chrome WhatsApp Web]
      D[Bot Dart]
      S[AIService / AIProvider]
      O[Ollama localhost:11434]
      M[Modelo LLM local]
    end

    W <--> C
    C <--> D
    D --> S
    S --> O
    O --> M
    M --> O
    O --> S
    S --> D
```

- **Si usa Ollama local**, el prompt hacia la IA va a `localhost:11434`, es decir, a la misma computadora.
- **WhatsApp Web si usa internet**, porque necesita conectarse a WhatsApp para recibir y enviar mensajes.
- **No se usan tokens de OpenAI/Anthropic** en esta configuracion.
- **NanoClaw no se usa como dependencia**: se tomo el enfoque modular de adaptadores.

## Responsabilidad de cada pieza

| Pieza | Responsabilidad |
| --- | --- |
| WhatsApp Web | Canal de entrada/salida de mensajes |
| Chrome + Puppeteer | Mantener la sesion web vinculada por QR |
| Bot Dart2 | Orquestar mensajes, eventos, polling y respuestas |
| `AIService` | Armar el prompt y pedir respuesta al proveedor |
| `AIProvider` | Contrato para cambiar proveedores de IA |
| `OllamaProvider` | Implementacion HTTP contra Ollama local |
| Ollama | Ejecutar modelos locales y exponer API |
| Modelo LLM | Generar la respuesta inteligente |

## Como se arma la respuesta

El mensaje del usuario no se manda solo al modelo. Antes se le agrega contexto:

```text
Eres un asistente de WhatsApp para un negocio que trabaja por citas.
Responde siempre en español.
Se breve, amable y claro.
No inventes disponibilidad, precios, ubicaciones ni datos medicos.

Mensaje del usuario:
<mensaje recibido por WhatsApp>

Respuesta:
```

Ese texto completo llega a Ollama. Ollama se lo pasa al modelo local y devuelve la respuesta al bot.

## Punto importante para futuras mejoras

Hoy el conocimiento del bot vive principalmente en el prompt base. Para saber horarios, servicios o disponibilidad real, el siguiente paso debe ser agregar una capa de conocimiento/datos, por ejemplo:

```mermaid
flowchart TD
    A[Mensaje del usuario] --> B[Bot Dart]
    B --> C[BusinessKnowledgeService]
    C --> D[JSON local / Supabase / agenda]
    D --> C
    C --> E[Datos concretos: servicios, horarios, disponibilidad]
    E --> F[AIService]
    A --> F
    F --> G[Ollama + modelo local]
    G --> H[Respuesta basada en datos reales]
```

Con esto se evita que la IA invente horarios y se obliga a responder usando datos reales del negocio.
