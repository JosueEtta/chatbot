# Alice — AI Assistant for Android

Alice is a Flutter-based AI chat application connected to a Python/FastAPI backend. It is designed to provide conversational assistance and to return structured command suggestions for tasks such as opening an application or searching for information.

The repository keeps the mobile client and API server on separate branches:

- **`frontend`** — Flutter application (Dart, Android/iOS project files and UI).
- **`backend`** — FastAPI service that communicates with the Groq API using the OpenAI-compatible Python client.

> **Important:** The current Flutter client displays command responses as JSON; it does not execute operating-system actions itself. Also, the Vercel entry point currently imports `backend.grok`, while the checked-in backend source is `backend/main.py`. See [Known limitations and deployment notes](#known-limitations-and-deployment-notes) before deploying.

## Contents

- [Features](#features)
- [How Alice works](#how-alice-works)
- [Technology stack](#technology-stack)
- [Repository branches](#repository-branches)
- [Requirements](#requirements)
- [Installation and setup](#installation-and-setup)
  - [1. Get the source code](#1-get-the-source-code)
  - [2. Configure and run the backend](#2-configure-and-run-the-backend)
  - [3. Configure and run the Flutter app](#3-configure-and-run-the-flutter-app)
- [Configuration reference](#configuration-reference)
- [API reference](#api-reference)
- [Project structure](#project-structure)
- [Troubleshooting](#troubleshooting)
- [Known limitations and deployment notes](#known-limitations-and-deployment-notes)
- [Security](#security)
- [Contributing](#contributing)

## Features

### Chat interface

- Send messages to Alice using the message field.
- View user messages and assistant responses in a chat timeline.
- Receive assistant responses progressively through Server-Sent Events (SSE), rather than waiting for the entire answer.
- Display an animated three-dot indicator while Alice is preparing a response.
- Stop an active response stream.
- Select and copy message text.
- Use the suggested prompts on the welcome screen to start a conversation.

### Appearance and interaction

- Light and dark themes.
- Smooth animated transition between themes.
- Saves the selected theme locally and restores it on the next launch.
- Animated suggestion chips, send/stop button, message entrance and typing indicator.
- DM Sans font bundled with the Flutter application.

### AI response modes

Alice's backend prompt defines two response styles:

1. **Chat:** normal conversational text, streamed to the app as it is generated.
2. **Command suggestion:** a JSON object describing an intended action. The documented shapes are:

```json
{"task": "open", "target": "Application Name"}
```

```json
{"task": "search", "target": "Search Query"}
```

The command response is sent as a separate SSE event and shown in a monospace-style command section in the app.

## How Alice works

The application has two main parts: a Flutter client and a FastAPI backend.

### 1. The user sends a message

The Flutter application reads the text field (or a welcome-screen suggestion), adds the user's message to the conversation, displays an empty assistant message as a thinking indicator, and prepares the previous conversation turns.

The client sends an HTTP `POST` request to the configured API URL. The JSON request body contains:

- `question`: the new user message.
- `history`: previous user and assistant messages, each with a `role` and `content`.

The client requests an SSE response by setting the `Accept: text/event-stream` header.

### 2. FastAPI receives the request

The backend exposes a FastAPI application with a `POST /` endpoint.

Pydantic validates the incoming request:

- A question is required and must contain between 1 and 4,000 characters.
- Each history item has a role of `user` or `assistant`.
- Each history message is limited to 20,000 characters.
- The history list can contain up to 40 items.

Before sending the request to the model, the endpoint keeps at most the latest 20 history turns and builds the model message list:

1. Alice's system instructions.
2. The retained conversation history.
3. The new user question.

### 3. The backend calls the language model

The backend uses the `AsyncOpenAI` client with Groq's OpenAI-compatible API endpoint:

```text
https://api.groq.com/openai/v1
```

The API key is read from the `GROQ_API_KEY` environment variable. The model is selected using `GROQ_MODEL`; if it is not set, the code uses `qwen/qwen3.8-27b`.

The system prompt instructs the model to return ordinary text for normal conversation and a JSON command object for automation-style requests.

### 4. The backend streams the response

The FastAPI endpoint consumes the model's streamed output and determines the response type from the first non-whitespace character:

- If the response begins with `{`, it is treated as a command. The backend buffers it and sends it when generation finishes.
- Otherwise, it is treated as chat. Text chunks are sent as they arrive.

The SSE events use these names:

| Event | Purpose |
| --- | --- |
| `chat` | A piece of ordinary assistant text |
| `command` | A completed command JSON response |
| `error` | A model/API error message |

Each event's data is JSON containing a `text` field, for example:

```text
event: chat
data: {"text":"Hello! How can I help?"}

```

### 5. Flutter reads the SSE stream

The Flutter client decodes the response as UTF-8, splits it into lines, reads the `event:` and `data:` fields, decodes the JSON payload and appends the received text to the current assistant message.

UI updates are batched to approximately 20 updates per second to avoid rebuilding the interface for every individual token. The app also:

- Shows a connection error when the server cannot be reached.
- Shows an error when the server returns a non-200 status.
- Detects an idle/interrupted stream.
- Preserves a partial assistant answer if an error occurs after some text has arrived.
- Closes the HTTP client and stream subscription when the user stops generation or leaves the screen.

### 6. Conversation history

Before a new message is sent, the client builds a history from the messages already displayed. It sends up to the latest 20 turns. The backend independently limits the history it forwards to the model to 20 turns.

The conversation is currently held in the app's in-memory state. The theme preference is persisted with `shared_preferences`, but chat messages are not saved across application restarts.

## Technology stack

| Area | Technology |
| --- | --- |
| Mobile application | Flutter / Dart |
| UI | Flutter Material widgets |
| Local preference storage | `shared_preferences` |
| HTTP communication | `http` |
| Environment configuration | `flutter_dotenv` |
| Backend API | Python, FastAPI |
| Request validation | Pydantic |
| Streaming | Server-Sent Events (SSE) |
| Model API client | OpenAI Python SDK (`AsyncOpenAI`) |
| AI inference provider | Groq API |
| Model default | `qwen/qwen3.8-27b` |
| Local API server | Uvicorn |
| Backend environment variables | `python-dotenv` |

## Repository branches

The project is split across two branches. The default branch is `backend`.

| Branch | Contains | Main files |
| --- | --- | --- |
| `frontend` | Flutter application | `lib/main.dart`, `pubspec.yaml`, `android/`, `ios/`, `assets/` |
| `backend` | Python API and deployment configuration | `backend/main.py`, `backend/requirements.txt`, `api/index.py`, `vercel.json` |

You can work with the branches in separate folders, or fetch both branches into one local Git repository.

## Requirements

Install the following before starting:

- Git.
- Flutter SDK compatible with the Dart SDK constraint in `pubspec.yaml` (Dart SDK `^3.13.3`).
- Python 3.12 or a compatible Python version.
- A Groq API key.
- Android Studio and an Android SDK for Android development, or Xcode on macOS for iOS development.

Check your local installations:

```bash
git --version
flutter --version
dart --version
python --version
```

## Installation and setup

### 1. Get the source code

Clone the backend branch:

```bash
git clone --branch backend https://github.com/JosueEtta/chatbot.git alice-backend
```

Clone the Flutter branch into a separate folder:

```bash
git clone --branch frontend https://github.com/JosueEtta/chatbot.git alice-frontend
```

You should now have two folders:

```text
alice-backend/
  api/
  backend/
  vercel.json

alice-frontend/
  android/
  assets/
  ios/
  lib/
  pubspec.yaml
```

### 2. Configure and run the backend

Open a terminal in the backend folder:

```bash
cd alice-backend/backend
```

Create and activate a virtual environment.

**Linux / macOS:**

```bash
python3 -m venv .venv
source .venv/bin/activate
```

**Windows PowerShell:**

```powershell
py -3.12 -m venv .venv
.venv\Scripts\Activate.ps1
```

Install the Python dependencies:

```bash
python -m pip install --upgrade pip
pip install -r requirements.txt
```

Create a file named `.env` inside the `alice-backend/backend/` directory:

```env
GROQ_API_KEY=your_groq_api_key
GROQ_MODEL=qwen/qwen3.8-27b
CORS_ORIGINS=*
```

Replace `your_groq_api_key` with your own key from the Groq developer console. Do not commit this file.

Start the FastAPI application locally:

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

The API should be available at:

- API endpoint: `http://127.0.0.1:8000/`
- FastAPI interactive documentation: `http://127.0.0.1:8000/docs`

Keep this terminal running while you use the Flutter application.

> The local Uvicorn command above runs the checked-in `backend/main.py` application. The current Vercel adapter points to a different module; review the deployment warning below before using Vercel.

### 3. Configure and run the Flutter app

Open a second terminal:

```bash
cd alice-frontend
flutter pub get
```

Create or edit the `.env` file in the Flutter project root (the same directory as `pubspec.yaml`):

```env
API_URL=http://10.0.2.2:8000/
```

Use the correct address for your environment:

| Where the Flutter app runs | Example `API_URL` |
| --- | --- |
| Android Emulator | `http://10.0.2.2:8000/` |
| iOS Simulator | `http://127.0.0.1:8000/` |
| Desktop on the same computer | `http://127.0.0.1:8000/` |
| Physical Android phone | `http://YOUR_COMPUTER_LAN_IP:8000/` |

For a physical phone, connect the phone and computer to the same network, replace `YOUR_COMPUTER_LAN_IP` with the computer's local network IP address, and allow the backend port through the computer's firewall. Do not use `localhost` or `127.0.0.1` on the phone: those addresses refer to the phone itself.

The Flutter source optionally sends an `API_KEY` value in an `X-API-Key` request header if one is defined in the client `.env`. The current FastAPI backend does not validate that header, so it is not an authentication mechanism.

#### Android internet permission

Before testing on Android, check `android/app/src/main/AndroidManifest.xml`. The current manifest does not declare the Android internet permission. Add this line directly inside the `<manifest>` element, before `<application>`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

For local HTTP development, Android may also require cleartext HTTP traffic to be explicitly allowed by the app configuration. Prefer HTTPS for production.

Run the app:

```bash
flutter run
```

To list available devices:

```bash
flutter devices
```

To build an Android APK:

```bash
flutter build apk --release
```

The APK is generated at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Configuration reference

### Backend variables

| Variable | Required | Description |
| --- | --- | --- |
| `GROQ_API_KEY` | Yes | Secret API key used to authenticate with Groq. The backend exits during startup if it is missing. |
| `GROQ_MODEL` | No | Model identifier sent to Groq. Defaults to `qwen/qwen3.8-27b` in the current source. |
| `CORS_ORIGINS` | No | Comma-separated allowed origins. Defaults to `*`. |

### Flutter variables

| Variable | Required | Description |
| --- | --- | --- |
| `API_URL` | Practically yes | Full URL of the FastAPI endpoint. Defaults to `http://10.0.2.2:8000/` if absent. |
| `API_KEY` | No | Optional header value sent as `X-API-Key`; it is not currently checked by the backend. |

The Flutter project declares `.env` as a bundled asset. Treat any value placed in the mobile app's environment file as extractable from the application package. Never put a private provider key such as `GROQ_API_KEY` in the Flutter app.

## API reference

### `POST /`

Accepts a chat question and optional conversation history. The response is an SSE stream.

**Request body:**

```json
{
  "question": "Hello Alice",
  "history": [
    {
      "role": "user",
      "content": "Hi"
    },
    {
      "role": "assistant",
      "content": "Hello! How can I help?"
    }
  ]
}
```

**Headers:**

```text
Content-Type: application/json
Accept: text/event-stream
```

**Response events:**

- `chat`: incremental natural-language response chunks.
- `command`: completed JSON command suggestion.
- `error`: an error message if model generation fails.

Example local request using curl:

```bash
curl -N http://127.0.0.1:8000/ \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{"question":"Hello Alice","history":[]}'
```

The `-N` option disables curl's output buffering so streamed events are visible as they arrive.

## Project structure

### Flutter branch (`frontend`)

```text
alice-frontend/
├── android/                  # Android application wrapper and native config
├── assets/
│   └── fonts/                # Bundled DM Sans font
├── ios/                      # iOS application wrapper
├── lib/
│   └── main.dart             # App startup, chat UI, API/SSE client and widgets
├── .env                      # Local API configuration (create locally)
├── pubspec.yaml              # Flutter dependencies and assets
├── pubspec.lock              # Resolved Dart/Flutter dependency versions
└── analysis_options.yaml     # Dart analyzer and lint configuration
```

The main Dart file contains:

- Application initialization and environment loading.
- Theme palette and saved light/dark preference.
- Chat message model and state management.
- HTTP request construction and conversation-history handling.
- SSE line parsing and streamed message updates.
- Welcome screen, message list and input area.
- Theme toggle, suggestion chips, send/stop button, thinking dots and message animations.

### Backend branch (`backend`)

```text
alice-backend/
├── api/
│   └── index.py              # Serverless adapter (currently references backend.grok)
├── backend/
│   ├── main.py               # FastAPI app, validation, Groq client and SSE endpoint
│   ├── requirements.txt      # Python dependencies
│   └── Modelfile             # Ollama model configuration
├── vercel.json               # Vercel routing and function configuration
└── .vercelignore              # Files excluded from Vercel deployment
```

The checked-in backend source also contains a small SSE test example in `backend/test.py`.

## Troubleshooting

### The app says it cannot connect to the server

1. Confirm Uvicorn is running.
2. Confirm `API_URL` points to the correct host and port.
3. Use `10.0.2.2` from the Android Emulator to reach the development computer.
4. On a physical phone, use the computer's LAN IP address and check firewall/network settings.
5. Confirm Android internet permission is present.
6. Check that the backend is listening on `0.0.0.0` when a physical device needs to connect.

### Backend stops during startup because the API key is missing

Make sure `GROQ_API_KEY` is set in `alice-backend/backend/.env`, or exported in the shell environment. The backend reads the file next to `main.py`.

### Groq returns an authentication or model error

- Verify that the API key is valid and active.
- Verify that the model identifier is available to your Groq account.
- Check the backend terminal logs for the provider's error details.

### The response stops or the connection stalls

The Flutter client has a 15-second connection timeout and a 120-second stream-idle timeout. Check the backend logs, network connection and provider availability.

### CORS errors

Set `CORS_ORIGINS` to the exact origin(s) that should be allowed, separated by commas. The default is permissive and should not be used as a substitute for a production security policy.

### Flutter cannot load the environment file

Confirm that `.env` exists in the Flutter project root and that `pubspec.yaml` includes it under `flutter.assets`. Then run:

```bash
flutter pub get
```

## Known limitations and deployment notes

The following are observations from the current repository source, not assumptions about future functionality:

1. **Command execution is not implemented in the Flutter client.** The backend can generate `open` and `search` JSON suggestions, but the Flutter code currently displays the JSON response. There is no Android intent, app-launching integration, browser-launching integration or command dispatcher in `lib/main.dart`.
2. **The intent-classification helper is not used by the chat endpoint.** `classify_intent()` is defined in `backend/main.py`, but `ask()` does not call it. The actual response mode is selected by checking whether the model's generated response starts with `{`.
3. **Vercel's Python import currently does not match the checked-in source.** `api/index.py` imports `app` from `backend.grok`, but the backend branch contains `backend/main.py` and no `backend/grok.py`. As checked in, that import will fail unless the module is added or the adapter is changed to import the actual application module. The local Uvicorn command in this README uses `main:app` from inside the `backend/` directory.
4. **The Android manifest currently lacks the internet permission.** Add `android.permission.INTERNET` before testing API calls on Android.
5. **Chat history is not persisted.** Only the theme preference is saved locally.
6. **The optional client `API_KEY` header is not authenticated by the backend.** Do not expose the API publicly on the assumption that this header protects it.
7. **The backend's default CORS setting allows all origins.** Restrict it to trusted origins for a deployed service.
8. **The Ollama `Modelfile` is not the model runtime used by the current FastAPI endpoint.** The endpoint currently calls Groq through the OpenAI-compatible client. The Modelfile describes a separate local Ollama configuration.

Before deploying, resolve the Vercel import mismatch, configure secrets in the hosting provider's environment settings, add appropriate authentication/rate limiting, restrict CORS, and use HTTPS.

## Security

- Keep `GROQ_API_KEY` on the backend only.
- Do not commit local `.env` files or virtual environments.
- Rotate any API key that has accidentally been committed or shared.
- Do not treat a mobile application's bundled environment variables as secrets.
- Add authentication and rate limiting before exposing the API to public traffic.
- Use HTTPS and restrict CORS origins in production.

## Contributing

1. Create a feature branch from the relevant project branch.
2. Keep Flutter changes on `frontend` and API changes on `backend`.
3. Test the Flutter client and backend independently.
4. Do not commit secrets, `.env` files, or virtual environments.
5. Submit a pull request with a description of the change and how it was tested.

---

**Repository:** [JosueEtta/chatbot](https://github.com/JosueEtta/chatbot)  
**Mobile client branch:** [frontend](https://github.com/JosueEtta/chatbot/tree/frontend)  
**API branch:** [backend](https://github.com/JosueEtta/chatbot/tree/backend)
