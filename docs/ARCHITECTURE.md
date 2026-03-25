# LAMA S Architecture

## Overview

LAMA S is a native macOS application that combines four responsibilities:

1. Running a real shell session inside a pseudo-terminal
2. Rendering terminal output in a modern SwiftUI interface
3. Calling AI services to explain commands and errors
4. Observing and assisting Git workflows in the current working directory

The codebase is intentionally split by responsibility rather than by framework.

## Runtime Flow

### 1. App launch

- `LamaTerminalApp.swift` is the active `@main` entry point.
- It loads `ContentView`.
- `ContentView` creates the root state objects:
  - `TerminalEngine`
  - `RepoStateManager`
  - `AIService`
  - `GitActionEngine`
  - `AISettingsStore`

### 2. Terminal session startup

- `TerminalEngine.start()` opens a PTY using `posix_openpt`.
- The shell process is spawned through the C bridge in `pty_spawn.c`.
- Output is read asynchronously through a dispatch read source.
- Raw bytes are decoded, cleaned, split into logical lines, and published to the UI.

### 3. User input processing

When a user submits text:

- Built-in LAMA commands are intercepted first
- `cd` and `ls` are handled as optimized local flows
- natural language is optionally routed to AI
- standard shell commands are written to the PTY
- command risk is checked by `SafetyEngine` before execution

### 4. Output enhancement

Terminal output is further enriched by:

- `LineParser` turning file-system paths into interactive UI elements
- `AuthEventDetector` surfacing authentication and permission banners
- automatic error capture for AI explanation

### 5. Git state tracking

- `RepoStateManager` watches the current directory
- it determines whether the directory belongs to a Git repository
- if so, it loads branch and file-change state
- the Git panel renders that structured state and enables actions through `GitActionEngine`

## Module Breakdown

## `Core/`

### `TerminalEngine.swift`

Primary runtime engine.

Responsibilities:

- shell lifecycle
- PTY I/O
- output line assembly
- local terminal command interception
- current-directory tracking
- command routing between shell and AI

Key design choice:

- The terminal remains a real shell, but some interactions are intentionally upgraded with app-native handling.

### `CommandParser.swift`

Responsibilities:

- basic tokenization
- parsing built-in LAMA commands
- AI prompt construction
- `[COMMAND]...[/COMMAND]` extraction from streamed AI responses

This file acts as the command interpretation seam between user input and downstream execution.

### `AIService.swift`

Responsibilities:

- OpenAI-compatible and Ollama-compatible request handling
- OpenAI Responses API request construction
- streamed and non-streamed AI responses
- JSON extraction and parsing for different AI tasks
- commit-message suggestion support
- provider selection through app settings and environment-based fallback

Key design choice:

- The service is intentionally thin and output-parser driven rather than deeply typed end-to-end.
- hosted OpenAI and local Ollama share one runtime path so the UI layer does not need provider-specific branching

### `AISettingsStore.swift`

Responsibilities:

- persist AI provider choice
- persist OpenAI and Ollama model preferences
- read environment-variable fallbacks
- expose resolved provider state to the UI

Key design choice:

- user-facing AI configuration is now part of the product surface instead of being hidden in development-only environment setup.

### `KeychainService.swift`

Responsibilities:

- store and load the OpenAI API key from the macOS Keychain

Key design choice:

- secrets should not be kept in plain UserDefaults when the app can rely on the native Keychain.

### `SafetyEngine.swift`

Responsibilities:

- regex-based detection of risky shell commands
- returns lightweight warnings before execution

This is a local-first safety layer that does not depend on AI availability.

### `LineParser.swift`

Responsibilities:

- detect local paths in terminal output
- convert valid paths into interactive UI segments

### `AuthEventDetector.swift`

Responsibilities:

- detect auth and permission-related terminal prompts
- convert them into contextual banners

## `Git/`

### `GitService.swift`

Low-level Git command execution wrapper around `Process`.

Responsibilities:

- execute Git commands asynchronously
- capture stdout/stderr
- disable interactive credential prompts in this Git-specific path

### `GitParser.swift`

Responsibilities:

- parse `git status --porcelain=v2 --branch`
- parse logs and branch lists
- translate raw Git CLI output into typed models

### `RepoStateManager.swift`

Responsibilities:

- maintain current repository state
- react to directory changes
- derive branch, change, merge, and rebase information

### `GitActionEngine.swift`

Responsibilities:

- user-triggered Git operations
- staging, unstaging, committing, switching branches, pushing, pulling

### `GitWorkflowEngine.swift`

High-level workflow helper for multi-step Git flows.

Current status:

- implemented
- only partially integrated into the current UI/runtime flow

## `Views/`

### `ContentView.swift`

Top-level composition root.

Responsibilities:

- own app state
- wire terminal, AI panel, intro overlay, and Git panel together
- route events between runtime and UI

### `TerminalView.swift`

Main terminal UI.

Responsibilities:

- header and chrome
- breadcrumb path navigation
- output rendering
- autocomplete strip
- input bar and mode switching
- quick access to AI settings

### `IntroView.swift`

Animated splash overlay that brands the app and introduces available commands.

### `AIPanelView.swift`

Renders AI states:

- loading
- streaming
- explanation
- warning
- command suggestions
- agent plans

### `GitStatusView.swift`

Git panel showing:

- branch state
- staged/unstaged/untracked files
- diffs
- commit entry point

### `CommitAssistantView.swift`

Sheet that requests AI-generated commit message suggestions for staged changes.

### `AISettingsView.swift`

Native macOS settings surface for:

- provider selection
- model configuration
- OpenAI API key entry
- Ollama endpoint configuration

### `AuthBannerView.swift` and `PermissionBannerView.swift`

Contextual guidance overlays for authentication and macOS permission events.

### `GlassView.swift`

Small AppKit bridge around `NSVisualEffectView`.

### `TerminalAppearance.swift` and `TerminalTheme.swift`

Visual system for theme presets, accent colors, density, and typography.

## `Models/`

### `Models.swift`

Contains the shared app models:

- terminal lines and segments
- safety warnings
- AI response types
- agent plan types
- panel states

## C Bridge

### `pty_spawn.c` and `pty_spawn.h`

These files provide the low-level PTY shell spawning bridge used from Swift.

This is the foundation that enables LAMA S to behave like a real terminal instead of only rendering command output from detached subprocesses.

## Architectural Strengths

- Clear layer separation
- Native macOS UI with minimal framework sprawl
- Real shell runtime rather than simulated command wrappers
- Git and AI logic are isolated from the presentation layer
- Local command handling allows UX improvements without compromising shell access

## Architectural Risks

- No automated tests around terminal parsing and Git parsing yet
- Some behavior is heuristic-driven and can drift over time
- AI parsing relies on resilient string extraction instead of strict schemas
- App-level configuration is not yet centralized in a settings system
- The codebase includes partially integrated workflow/intent paths that can confuse contributors if undocumented

## Recommended Evolution

1. Introduce tests for parsers and safety rules.
2. Add a dedicated settings model for AI/provider configuration.
3. Formalize the command routing pipeline as separate layers if complexity grows.
4. Decide whether `IntentEngine` and `GitWorkflowEngine` remain product features or become deferred/internal modules.
