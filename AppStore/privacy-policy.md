# Privacy Policy for TodoApp

**Last Updated: February 2026**

## Overview

TodoApp is designed with privacy as a core principle. Your todo data stays on your device in a markdown file you control.

## Data Collection

### What We Don't Collect
- We do not collect any personal information
- We do not track your usage
- We do not have analytics
- We do not have user accounts
- We do not store your todos on any server

### Local Data Storage
All your todos, goals, and settings are stored locally on your Mac:
- **Todo File**: Stored in a location you choose (typically your Documents folder)
- **Preferences**: Stored in standard macOS user defaults
- **API Key** (if used): Stored securely in macOS Keychain

## Optional AI Feature

TodoApp includes an optional AI-powered tag suggestion feature that uses Anthropic's Claude API.

### How It Works
- This feature is **disabled by default**
- You must provide your own Anthropic API key to enable it
- When you click the suggestion button, the text of your current todo is sent to Anthropic's API
- The API returns suggested tags, which are displayed in the app

### What Is Sent
When you use the AI suggestion feature, only the following is transmitted:
- The text of the single todo item you're requesting suggestions for
- Your API key (for authentication)

### What Is NOT Sent
- Your complete todo list
- Your goals
- Any other personal information
- Usage analytics

### Anthropic's Privacy
When using the AI feature, your data is subject to Anthropic's privacy policy and terms of service. We recommend reviewing their policies at https://www.anthropic.com/privacy

## Third-Party Services

The only third-party service TodoApp connects to is:
- **Anthropic API** (api.anthropic.com) - Only when you explicitly use the AI tag suggestion feature

## Data Security

- Your API key is stored in macOS Keychain, Apple's secure credential storage
- All network requests to Anthropic use HTTPS encryption
- Your todo file is a plain text file with standard macOS file permissions

## Children's Privacy

TodoApp does not knowingly collect any information from children under 13.

## Changes to This Policy

We may update this privacy policy from time to time. Any changes will be reflected in the "Last Updated" date.

## Contact

If you have questions about this privacy policy, please visit our GitHub repository:
https://github.com/horiag-dev/todoapp

---

## Summary

**In plain terms**: TodoApp stores everything locally on your Mac. The only time any data leaves your device is if you choose to use the optional AI tag suggestions, which sends only the current todo text to Anthropic's API.
