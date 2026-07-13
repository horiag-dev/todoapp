# Big Rocks First — macOS installer

## Install

1. Copy the `.tar.gz` file to your work Mac.
2. Open Terminal and run:

   ```sh
   tar -xzf big-rocks-first-macos-*.tar.gz
   cd big-rocks-first-macos-*
   ./install.sh
   ```

3. When Claude opens its login flow, sign in with the Claude account supplied by
   your employer. Choose the subscription/Team/Enterprise option, not Console API
   billing.
4. On first app launch, select your existing todo Markdown file or create one.

The installer requires macOS, Node.js 18+, npm, and internet access while it
installs locked dependencies and authenticates Claude. It creates:

- `~/Applications/Big Rocks First.app`
- `~/.local/bin/big-rocks-first`
- `~/.local/share/big-rocks-first` (application code)
- `~/Library/Application Support/Big Rocks First` (runtime PID only)
- `~/Library/Logs/Big Rocks First/service.log`

Your todo Markdown, `.bigrocks` history, and Claude credentials stay outside the
application directory. The archive contains no personal todo data or credentials.

## Launch and stop

Open **Big Rocks First** from `~/Applications`, or run:

```sh
~/.local/bin/big-rocks-first
~/.local/bin/big-rocks-first --stop
```

The launcher deliberately ignores inherited Anthropic API-key variables so the
Claude subscription login is used. If your company explicitly requires Bedrock,
Vertex, Foundry, or API-key authentication, launch with
`BIGROCKS_USE_ENV_AUTH=1`.

## Work-device note

Your employer must allow Claude Code / Agent SDK use and your work Claude plan
must include it. Follow your organization's software-installation and data-handling
policies before selecting a work Markdown file.
