# spurwechsel

`spurwechsel` is a macOS program to enhance human context switching. In the AI era, I think the most important skill for developers will be handling many agents, reviewing code and switching different tasks really fast.

The name is derived from the german Autobahn. Who wants to drive fast in germany has to switch lanes pretty often since many people are not able to stay on the right lane. Sadly.

## Install

```sh
brew install code-server # optional for vscode inside spurwechsel (recommended)
brew install --cask breuerfelix/tap/spurwechsel
```

## Features

Current:

- handle multiple agents
- one sticky terminal session (use tmux or zellij if you need multiplexing)
- `code-server` to have a built-in VSCode experience

Planned:

- git diff view + commenting like codex / cursor has
- some kind of kanban board view per project with mcp / cli agent integration
- task buttons, execute custom commands like `npm install` or complex ones that generate commit messages and commit changes
- integrate agents like `claude`, `opencode` deeper so the left side panel can show which agent needs input or is currently working

## Config

Config file path:

- `~/.spurwechsel/config.yaml`
- override with `SPURWECHSEL_CONFIG_PATH`

Default config values:

```yaml
version: 1

codeServer:
  port: 8080

projects:
  - path: "/Users/tenxdev/code/random-project-no-one-cares-about"
    name: "Insane Tool"

agents:
  - name: claude
    command: claude
    default: true
  # when using opencode I recommend setting the theme to 'system' with /theme
  # it feels like opencode is baked in the app with that theme
  - name: opencode
    command: opencode
  - name: codex
    command: codex

shortcuts:
  - action: toggle-command-bar
    key: k
    modifiers: [command]
  - action: create-default-agent
    key: t
    modifiers: [command]

theme: {}
```

`projects` stores repo roots only. Worktrees come from git state. `theme: {}` means built-in light and dark palettes stay active until you override tokens.

<details>
<summary>Default theme values</summary>

```yaml
theme:
  light:
    background: "#F8FBFF"
    backgroundSecondary: "#E9EEF6"
    panel: "#FFFFFF"
    panelRaised: "#EDF2F8"
    panelMuted: "#E7EDF5"
    border: "#D7E1EC"
    borderStrong: "#B8C7D8"
    foreground: "#152033"
    foregroundMuted: "#5D6C80"
    foregroundDim: "#8190A3"
    accent: "#2B8AE6"
    accentForeground: "#FFFFFF"
    selection: "#DDEBFA"
    terminal: "#E4EDF7"
    terminalForeground: "#152033"
    success: "#178A4C"
    warning: "#AD6B00"
    error: "#C64545"
    info: "#1F78D1"
    overlay: "#0000001F"
    overlayStrong: "#00000085"
    shadow: "#0000001F"
  dark:
    background: "#0A0A0A"
    backgroundSecondary: "#0A0A0A"
    panel: "#181818"
    panelRaised: "#202020"
    panelMuted: "#121212"
    border: "#262626"
    borderStrong: "#303030"
    foreground: "#F4F0EA"
    foregroundMuted: "#A0A0A0"
    foregroundDim: "#6E6E6E"
    accent: "#C7771A"
    accentForeground: "#0A0A0A"
    selection: "#31240B"
    terminal: "#161616"
    terminalForeground: "#F4F0EA"
    success: "#62E08B"
    warning: "#FFC85C"
    error: "#FF6B6B"
    info: "#64C5FF"
    overlay: "#00000057"
    overlayStrong: "#00000085"
    shadow: "#00000057"
```

</details>

More detail:

- [docs/configuration.md](./docs/configuration.md)
- [docs/design-tokens.md](./docs/design-tokens.md)
