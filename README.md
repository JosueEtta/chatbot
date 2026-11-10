# Alice — Flutter AI Chatbot Frontend

Alice is a Flutter chat application that provides the user interface for an AI assistant. It sends messages to an HTTP backend, receives the assistant's response as a Server-Sent Events (SSE) stream, and displays the response progressively as text arrives.

This repository branch contains the **Flutter frontend**. The AI processing and response generation are handled by the backend; the mobile app is the client that communicates with it.

## Table of contents

- [Features](#features)
- [How the application works](#how-the-application-works)
- [Frontend and backend communication](#frontend-and-backend-communication)
- [Technology stack](#technology-stack)
- [Project structure](#project-structure)
- [Requirements](#requirements)
- [Installation and setup](#installation-and-setup)
- [Configure the backend URL](#configure-the-backend-url)
- [Run the application](#run-the-application)
- [Build an APK](#build-an-apk)
- [Important implementation details](#important-implementation-details)
- [Troubleshooting](#troubleshooting)
- [Related branch](#related-branch)

## Features

### 1. AI chat interface

- Users can enter a message in the text field and send it to the backend.
- The keyboard's send action can also submit a message.
- User messages appear on the right in rounded message bubbles.
- Assistant messages appear on the left as plain text.
- Message text can be selected and copied.

### 2. Suggested prompts

The welcome screen displays three ready-made prompts:

- Help plan my day
- I want to chat with a girl
- Give latest sport news

Selecting a suggestion sends it through the same message-handling process as a message typed by the user.

### 3. Real-time streamed responses

Alice uses Server-Sent Events (SSE) to receive responses progressively instead of waiting for the complete answer.

- A three-dot animated indicator appears while waiting for the first response content.
- Incoming text chunks are appended to the current assistant message.
- The interface refreshes in batches to avoid rebuilding the screen for every individual token.
- The chat automatically scrolls as new content arrives when the user is already near the bottom.

### 4. Conversation context

Before sending a new message, the app builds a conversation history from previous user and assistant messages.

- Each turn is represented by a role and content.
- The most recent 20 messages are included in the request.
- Error messages are excluded from the history.
- The history is held in memory for the current app session; this implementation does not persist chat messages between launches.

### 5. Light and dark themes

- Users can switch between light and dark mode using the sun/moon control.
- Theme changes are animated.
- The selected theme is saved with SharedPreferences.
- The saved theme is loaded before the first screen is displayed, avoiding an initial theme flash.

### 6. Request controls and error handling

- The send button changes into a stop button while a response is streaming.
- Users can stop an active stream.
- The app handles connection failures, non-200 HTTP responses, connection timeouts and interrupted or idle streams.
- If a stream fails after some text has arrived, the partial answer is retained and the error is displayed separately.

### 7. Responsive interaction and animation

The interface includes animated message entrance effects, animated suggestion buttons, hover/press feedback, and an animated thinking indicator. The layout uses Flutter widgets and adapts to the available screen width.

## How the application works

The main application logic is in `lib/main.dart`.

### Application startup

When the app starts:

1. Flutter bindings are initialized.
2. The app attempts to load environment variables from the root `.env` file using `flutter_dotenv`.
3. SharedPreferences is opened.
4. The previously selected `dark_mode` value is read.
5. The Flutter application is launched with the saved theme preference.

If the `.env` file cannot be loaded, the app logs the problem and can fall back to its default API URL. You should still create the file as described below so the backend address is configured correctly.

### Sending a message

The `_send()` method handles both typed messages and suggested prompts:

1. It reads and trims the message.
2. It ignores empty messages and prevents a second request while a stream is already active.
3. It builds the previous conversation history.
4. It adds the user's message and an empty assistant placeholder to the chat.
5. It clears the input field and marks the app as streaming.
6. It creates an HTTP POST request to the configured API URL.
7. It sends the message and conversation history as JSON.
8. It listens for the streamed response.

The request body has this structure:

```json
{
  "question": "Hello, Alice!",
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

The history array may be empty for the first message.

### Receiving the response with SSE

The frontend requests a streamed response by setting the `Accept` header to `text/event-stream`.

The stream parser:

1. Decodes incoming bytes as UTF-8.
2. Splits the stream into lines.
3. Reads the SSE `event:` field to identify the event type.
4. Reads one or more `data:` lines.
5. Treats a blank line as the end of an event.
6. Parses the event data as JSON.
7. Reads the JSON `text` property and appends it to the current assistant message.

The frontend recognizes the event types `chat`, `command` and `error`. Command events are visually labelled **COMMAND** and displayed in a monospace font. Error events are displayed using the error colour.

The expected event format is:

```text
event: chat
data: {"text":"Hello"}

event: chat
data: {"text":"! How can I help you?"}

```

A command event can be sent using the same data structure:

```text
event: command
data: {"text":"command output or instruction"}

```

The backend must send valid SSE events with a JSON object containing a string `text` field. Events should be separated by a blank line. The frontend also flushes a final event when the stream closes without a trailing blank line.

### Stopping a response

While a request is active, the send button becomes a stop button. Pressing it cancels the stream subscription and closes the HTTP client. This stops the frontend from continuing to receive and display that response.

### Finishing a request

When a stream completes, fails or is stopped, the frontend:

- Cancels pending UI refresh work.
- Closes the HTTP client.
- Removes an empty assistant placeholder if no content was received.
- Preserves any partial response if an error occurs.
- Resets the streaming state so another message can be sent.

## Frontend and backend communication

The frontend and backend are separate parts of the project.

| Component | Responsibility |
|---|---|
| Flutter frontend | Chat interface, user input, theme, request handling and streamed message display |
| HTTP API | Receives the question and conversation history |
| AI backend | Processes the request and generates assistant output |
| SSE stream | Transfers the generated output to the frontend progressively |

The frontend does not contain the AI model or independently generate answers. A running, reachable backend that implements the expected API contract is required for chat functionality.

### API contract

| Item | Expected value |
|---|---|
| Method | `POST` |
| URL | Value of `API_URL` |
| Content-Type | `application/json` |
| Accept | `text/event-stream` |
| Optional authentication header | `X-API-Key` |
| Request fields | `question` and `history` |
| Successful status | HTTP `200` |
| Stream data | SSE events containing JSON with a `text` field |

If the backend requires authentication, configure the same API key expected by that backend. The frontend sends the optional key in the `X-API-Key` header.

## Technology stack

| Technology / package | Purpose |
|---|---|
| Flutter | Cross-platform application UI |
| Dart | Application programming language |
| `http` | HTTP requests and streamed responses |
| `flutter_dotenv` | Loads API configuration from `.env` |
| `shared_preferences` | Stores the selected theme |
| Material Design | UI components and icons |
| DM Sans | Bundled application font |

The package versions are managed in `pubspec.yaml` and `pubspec.lock`.

## Project structure

Important files and directories in this branch:

```text
.
├── assets/
│   └── fonts/
│       └── DMSans-VariableFont_opsz,wght.ttf
├── lib/
│   └── main.dart
├── android/
│   └── app/
│       └── src/
│           └── main/
│               └── AndroidManifest.xml
├── ios/
├── linux/
├── pubspec.yaml
├── pubspec.lock
├── analysis_options.yaml
├── .env
└── README.md
```

### Main source file

Most of the frontend implementation is currently contained in `lib/main.dart`.

| Class / method | Responsibility |
|---|---|
| `main()` | Initializes Flutter, environment variables and saved preferences |
| `MyApp` | Creates the root MaterialApp |
| `Palette` | Defines light and dark colour palettes |
| `ChatMessage` | Represents a user or assistant message |
| `HomeScreen` | Main chat screen and application state |
| `_send()` | Builds and sends a chat request |
| `_buildHistory()` | Prepares recent conversation turns |
| `_listen()` | Parses the SSE response |
| `_appendAiChunk()` | Appends streamed text to the assistant message |
| `_finish()` | Cleans up a completed, stopped or failed request |
| `ThemeToggle` | Animated light/dark mode control |
| `SuggestionChip` | Welcome-screen prompt button |
| `SendButton` | Send/stop control |
| `ThinkingDots` | Animated waiting indicator |
| `FadeSlideIn` | Message entrance animation |

## Requirements

Before installing the frontend, make sure you have:

- Flutter SDK installed and configured.
- A compatible Dart SDK (the required SDK constraint is declared in `pubspec.yaml`).
- Android Studio or VS Code with Flutter and Dart extensions.
- An Android emulator or a physical Android device for Android testing.
- A running Alice backend that implements the API contract above.
- Network access from the device to the backend.

Check your Flutter installation:

```bash
flutter doctor
```

## Installation and setup

### 1. Clone the repository

Clone the repository:

```bash
git clone https://github.com/JosueEtta/chatbot.git
cd chatbot
```

Switch to the frontend branch:

```bash
git switch frontend
```

If you have not cloned the repository yet and want to clone this branch directly:

```bash
git clone --branch frontend https://github.com/JosueEtta/chatbot.git
cd chatbot
```

### 2. Install Flutter dependencies

From the project root, run:

```bash
flutter pub get
```

This installs the dependencies declared in `pubspec.yaml`.

### 3. Create the environment file

Create a file named `.env` in the same directory as `pubspec.yaml`.

Add:

```env
API_URL=http://10.0.2.2:8000/
API_KEY=
```

Replace the URL with the address of your running backend. Set `API_KEY` only if your backend is configured to require it.

The project declares `.env` as a Flutter asset in `pubspec.yaml`, so keep the file at the project root.

**Security:** Do not commit real API keys or other secrets to a public repository. The current frontend configuration includes a root `.env` file in the repository and the current `.gitignore` does not ignore it. Before publishing or sharing credentials, add `.env` to `.gitignore`, remove any real secrets from the tracked file, and rotate any credentials that have already been exposed. A key embedded in a client application should not be treated as a secure secret.

### 4. Configure the backend

Start the backend separately and make sure it is listening on the host and port configured in `API_URL`.

The frontend expects the backend to:

- Accept POST requests at the configured URL.
- Accept JSON containing `question` and `history`.
- Return HTTP 200 for a successful request.
- Stream SSE events with JSON data containing a `text` value.
- Use the event names expected by the frontend when sending chat, command or error content.

See the backend branch for its own installation instructions and implementation details.

## Configure the backend URL

The correct URL depends on where the Flutter app is running.

### Android emulator

Use:

```env
API_URL=http://10.0.2.2:8000/
```

For the standard Android emulator, `10.0.2.2` refers to the development computer's localhost.

### Physical Android device

Use the development computer's local network IP address, for example:

```env
API_URL=http://192.168.1.10:8000/
```

Replace the example IP with your computer's actual LAN IP. Both devices must be on a network that allows them to communicate, and the backend must listen on an address reachable from the phone (not only `127.0.0.1`).

### iOS simulator

The iOS simulator can generally reach services running on the development Mac through its localhost address. Configure the URL for the actual host and port used by your backend.

### Deployed backend

For a deployed backend, use its reachable HTTPS endpoint:

```env
API_URL=https://your-backend-domain.example/
```

Use the actual API endpoint expected by your backend. The example domain above is a placeholder, not a live service.

## Run the application

Make sure the backend is running and the `.env` file contains the correct URL.

List available devices:

```bash
flutter devices
```

Run the application:

```bash
flutter run
```

To select a particular device:

```bash
flutter run -d DEVICE_ID
```

Replace `DEVICE_ID` with an ID shown by `flutter devices`.

## Build an APK

To create a debug APK:

```bash
flutter build apk --debug
```

To create a release APK:

```bash
flutter build apk --release
```

The APK is normally generated at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

For a production release, configure proper Android release signing before distributing the APK. Also verify that the backend URL is configured for the production environment.

## Important implementation details

- **Connection timeout:** The frontend allows up to 15 seconds for the initial HTTP connection.
- **Stream idle timeout:** The stream is treated as stalled after 120 seconds without incoming data.
- **History limit:** Up to 20 recent user/assistant messages are sent with a request.
- **UI update batching:** Streamed text triggers a UI refresh approximately every 50 milliseconds rather than once per token.
- **Scroll behavior:** The app follows new content when the user is already near the bottom; it does not forcibly interrupt someone reading older messages.
- **Theme persistence:** Only the light/dark preference is saved locally. Chat history is not persisted.
- **Default API URL:** If `API_URL` is missing, the app falls back to `http://10.0.2.2:8000/`, which is intended for the standard Android emulator setup.

## Troubleshooting

### The app says it cannot connect to the server

- Confirm that the backend is running.
- Check that `API_URL` points to the correct host, port and endpoint.
- For an Android emulator, use `10.0.2.2` rather than `localhost` to reach the development computer.
- For a physical phone, use the computer's LAN IP and ensure both devices can communicate.
- Check firewall rules and backend host binding.

### The server returns a non-200 status

The frontend currently treats only HTTP 200 as a successful streaming response. Check the backend logs and verify the request URL, HTTP method, request body and authentication configuration.

### The app connects but no answer appears

Verify that the backend returns an SSE response, not a normal JSON response. Each event should contain a JSON object with a string `text` field and events should be separated by a blank line.

### The response stops unexpectedly

Check the backend logs and network stability. The frontend reports an interrupted stream or a stalled connection if no stream data arrives within the configured idle timeout.

### Flutter cannot load the environment file

- Confirm that the file is named exactly `.env`.
- Confirm that it is in the project root, beside `pubspec.yaml`.
- Confirm that `.env` is listed under `flutter.assets` in `pubspec.yaml`.
- Run `flutter pub get` and restart the app.

### Dependencies or generated files are out of date

Try:

```bash
flutter clean
flutter pub get
flutter run
```

## Related branch

- **Backend:** [backend branch](https://github.com/JosueEtta/chatbot/tree/backend)
- **Frontend:** [frontend branch](https://github.com/JosueEtta/chatbot/tree/frontend)

The frontend branch contains the Flutter client. Run the backend separately to provide AI responses.
