# Contributing to LAMA S

## Development Principles

LAMA S should remain focused, approachable, and terminal-first.

When contributing, prefer:

- Small, understandable changes
- Native macOS behaviors over heavy abstractions
- Explicit user control over destructive or security-sensitive actions
- Clear separation of UI, terminal runtime, AI, and Git logic

## Local Setup

1. Open `Lama S.xcodeproj` in Xcode.
2. Review the setup instructions in [`Lama S/SETUP.md`](./Lama%20S/SETUP.md).
3. Configure either OpenAI or Ollama if you want AI-backed features.
4. Build and run the `Lama S` scheme.

## Project Areas

- `Lama S/Core/`
  Terminal runtime, AI integration, command parsing, safety logic

- `Lama S/Git/`
  Git state, parsing, workflows, and repo actions

- `Lama S/Views/`
  SwiftUI screens and reusable UI components

- `Lama S/Models/`
  Shared models used across multiple layers

## Contribution Guidelines

- Keep terminal behavior predictable.
- Do not auto-run dangerous commands without an explicit user action.
- Prefer extending existing architectural seams instead of bypassing them.
- Keep AI output parsing resilient and defensive.
- Document any new user-facing commands or workflows.
- If you add a new repository artifact, consider whether `.gitignore`, `README`, or setup docs should also be updated.
- Never commit real API keys or secrets to the repository.
- If you change AI integration, test both OpenAI and Ollama paths when possible.

## Before Opening a PR

- Make sure the project builds locally.
- Update docs for user-visible behavior changes.
- Include a short summary of:
  - what changed
  - why it changed
  - any follow-up work still needed

## Areas That Need Help

- Automated tests
- Provider validation and connection-test UX
- More robust error handling around AI/network failures
- Git workflow coverage and edge-case handling
- Public-release polish such as screenshots and licensing
