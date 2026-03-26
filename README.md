# LAMA S

LAMA S is a native macOS terminal built with SwiftUI. It combines a real PTY-backed shell session with AI-assisted explanations, error help, and Git-focused workflows in a single desktop app.

The current product direction is intentionally focused:

- Terminal-first experience
- Help when commands fail or need explanation
- Git visibility and lightweight Git actions
- Simple visual customization through built-in terminal commands

## Highlights

- Real shell session running inside a pseudo-terminal, not a fake terminal mock
- Command mode and natural-language mode in one input experience
- Automatic AI explanations for commands and terminal errors
- Native macOS AI settings with provider selection, model configuration, and secure OpenAI API key storage
- Built-in safety checks for risky shell commands
- Git status panel with staging, unstaging, diff preview, commit assistance, and branch context
- Authentication and permission banners for common Git/macOS prompts
- Theme, accent, density, and glass-style customization through built-in `lama` commands
- Animated splash screen and modern macOS-focused UI

## Product Scope

LAMA S is currently optimized for these use cases:

- Running shell commands in a modern desktop terminal
- Understanding what a command does before running it
- Getting help when terminal errors appear
- Working with Git without leaving the app
- Customizing the visual terminal experience quickly

It is not currently positioned as:

- A full IDE
- A package manager UI
- A general project scaffolding platform
- A replacement for advanced Git desktop clients

## Architecture Overview

The app is organized into four primary layers:

1. `Views/`
   SwiftUI presentation layer for terminal UI, AI panel, banners, intro animation, and Git panels.

2. `Core/`
   Terminal runtime, command parsing, AI integration, safety rules, output parsing, and intent helpers.

3. `Git/`
   Repository state tracking, Git command execution, parsing, workflow helpers, and user-triggered actions.

4. `Models/`
   Shared models used across the UI and runtime layers.

More detailed documentation is available in:

- [Architecture](./docs/ARCHITECTURE.md)
- [Project Analysis](./docs/PROJECT_ANALYSIS.md)
- [Setup Guide](./Lama%20S/SETUP.md)
- [Contributing](./CONTRIBUTING.md)

## Directory Structure

```text
.
├── Lama S.xcodeproj/
├── Lama S/
│   ├── Core/
│   ├── Git/
│   ├── Models/
│   ├── Views/
│   ├── Assets.xcassets/
│   ├── LamaTerminalApp.swift
│   ├── Lama_SApp.swift
│   ├── Lama-S-Bridging-Header.h
│   ├── pty_spawn.c
│   ├── pty_spawn.h
│   └── SETUP.md
├── docs/
├── CONTRIBUTING.md
└── README.md
```

## How It Works

### Terminal runtime

`TerminalEngine` opens a PTY, spawns the user shell, reads raw bytes, strips control sequences, assembles output lines, and publishes them to SwiftUI.

### AI assistance

`AIService` supports the OpenAI Responses API and local Ollama chat endpoints. It handles:

- command explanation
- error explanation
- natural-language conversion
- streamed AI chat
- Git commit suggestion support

Provider resolution is runtime-driven:

- the app settings window allows `Automatic`, `OpenAI`, or `Ollama`
- `Automatic` prefers OpenAI when an API key is available
- without an OpenAI key, the app falls back to local Ollama
- environment variables still work as fallback/default inputs

### Git integration

`RepoStateManager` observes the current terminal directory, detects whether it is a Git repository, and publishes structured repository state to the UI. `GitActionEngine` performs user-approved Git actions.

### Custom terminal commands

Built-in commands are intercepted before hitting the shell. Current examples:

- `lama help`
- `lama theme list`
- `lama theme next`
- `lama color amber`
- `lama density compact`
- `lama glass off`
- `lama mode nl`
- `lama clear`
- `lama intro`
- `mkcd my-folder`
- `..`
- `home`

## AI Providers

LAMA S supports both:

- OpenAI / ChatGPT API
- local Ollama

Provider selection can happen in the app or through environment variables:

- use `LAMA S` -> `Settings...` to choose `Automatic`, `OpenAI`, or `Ollama`
- OpenAI API keys entered in the app are stored locally in the macOS Keychain
- if `OPENAI_API_KEY` is set, `Automatic` can use OpenAI immediately
- otherwise the app falls back to Ollama
- you can still force a provider with `LAMA_AI_PROVIDER=openai` or `LAMA_AI_PROVIDER=ollama`

Useful variables:

- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- `OLLAMA_MODEL`
- `OLLAMA_ENDPOINT`
- `LAMA_AI_PROVIDER`

If OpenAI is selected but the key is missing, or if the provider returns an HTTP error, LAMA S now surfaces a readable AI error message instead of failing silently.

The default OpenAI model is `gpt-5.4`. OpenAI's current models page lists GPT-5.4 as a frontier model and describes it as best for agentic, coding, and professional workflows. Source: https://developers.openai.com/api/docs/models/all

## Requirements

- macOS
- Xcode 26.x or compatible toolchain for the current project settings
- SwiftUI and AppKit support
- Optional:
  - Ollama for local AI usage
  - OpenAI API access

## Build

Open `Lama S.xcodeproj` in Xcode and run the `Lama S` scheme.

For CLI builds, a local DerivedData path works well:

```bash
xcodebuild -project "Lama S.xcodeproj" -scheme "Lama S" -configuration Debug -sdk macosx -derivedDataPath ".deriveddata" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

## Current Strengths

- Clear separation between shell runtime, AI, Git logic, and UI
- Native macOS interaction patterns
- Good foundation for command assistance and Git-aware terminal workflows
- Focused product scope instead of overloaded feature sprawl

## Current Limitations

- No automated test suite yet
- Some intent/workflow infrastructure exists but is only partially integrated
- AI configuration is now available in-app, but provider validation/testing can still improve
- Project setup currently assumes a local macOS development environment

## License

This project is licensed under the Lama Open Ecosystem License (LOEL v1.0). See [LOEL_LICENSE.txt](LOEL_LICENSE.txt) for details.

Attribution: Original Creator — Riber Shamo Elias. Contributors are listed in [CONTRIBUTORS.md](CONTRIBUTORS.md) and the /Contributors/ directory.
