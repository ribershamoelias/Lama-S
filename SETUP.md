# LAMA S Setup Guide

## Overview

This guide covers local setup for running and developing LAMA S in Xcode.

LAMA S is a native macOS app that uses:

- SwiftUI for the interface
- AppKit interop for glass effects and macOS integrations
- a PTY-backed shell session for the terminal runtime
- optional AI backends for explanations and command assistance

## Prerequisites

- macOS
- Xcode 26.x or a compatible version for the current project settings
- access to either:
  - OpenAI-compatible API credentials, or
  - a local Ollama installation

## Project Entry Point

The active application entry point is:

- `LamaTerminalApp.swift`

The file:

- `Lama_SApp.swift`

is intentionally kept empty to avoid duplicate `@main` definitions.

## Terminal Requirement

The app uses a PTY shell process. App Sandbox must remain disabled for this to work.

In Xcode:

1. Open the `Lama S` target.
2. Go to `Signing & Capabilities`.
3. Confirm that App Sandbox is disabled.

The project currently ships with:

- `ENABLE_APP_SANDBOX = NO`

## AI Configuration

LAMA S supports two configuration paths:

- recommended: configure AI inside the app via `LAMA S` -> `Settings...`
- optional: use environment variables in Xcode or your shell

## Option A: Configure AI in the app

Open:

- `LAMA S` -> `Settings...`

From there you can:

- choose `Automatic`, `OpenAI`, or `Ollama`
- set the OpenAI model
- enter the OpenAI API key
- set the Ollama model
- set a custom Ollama endpoint

The OpenAI API key entered in the app is stored locally in the macOS Keychain.

## Option B: OpenAI / ChatGPT API via environment

If `OPENAI_API_KEY` is present, LAMA S automatically prefers OpenAI.

Set this in your Xcode scheme environment:

```text
OPENAI_API_KEY=your_api_key_here
OPENAI_MODEL=gpt-5.4
```

Optional explicit provider override:

```text
LAMA_AI_PROVIDER=openai
```

## Option C: Ollama via environment

If no OpenAI API key is configured, LAMA S falls back to Ollama by default.

Install and run Ollama locally:

```bash
brew install ollama
ollama pull phi3
ollama serve
```

Default local endpoint assumptions in the app:

- endpoint: `http://localhost:11434/api/chat`
- model: `phi3`

Optional explicit provider override:

```text
LAMA_AI_PROVIDER=ollama
OLLAMA_MODEL=phi3
OLLAMA_ENDPOINT=http://localhost:11434/api/chat
```

## Build in Xcode

1. Open `Lama S.xcodeproj`
2. Select the `Lama S` scheme
3. Press `Cmd+R`

## Build from Terminal

Use a local DerivedData path to keep build artifacts inside the repository folder:

```bash
xcodebuild -project "Lama S.xcodeproj" -scheme "Lama S" -configuration Debug -sdk macosx -derivedDataPath ".deriveddata" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

## Main User Features

- terminal shell session
- natural language mode
- AI command explanation
- AI error explanation
- Git status and actions
- commit message assistance
- built-in visual customization commands

## Built-In LAMA Commands

Examples:

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

## Troubleshooting

### PTY fails to open

Check that App Sandbox is disabled.

### AI returns nothing

Check that:

- your selected provider is configured correctly in `Settings`, or
- Ollama is running locally, or
- your OpenAI API key is configured correctly

### Duplicate `@main` error

Make sure only `LamaTerminalApp.swift` contains the app entry point.

### Git panel does not appear

The current working directory must be inside a Git repository.

### Build fails because of signing

For local CLI builds, use:

- `CODE_SIGNING_ALLOWED=NO`
- `CODE_SIGNING_REQUIRED=NO`
