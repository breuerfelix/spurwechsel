# Spurwechsel Design Tokens

## Purpose
Theme system is runtime-configurable and user-overridable from config. Source of truth lives in:

- `spurwechsel/Models/ConfigModels.swift`
- `spurwechsel/Models/ConfigFileModels.swift`
- `spurwechsel/State/ConfigResolver.swift`
- `spurwechsel/DesignSystem/AppTheme.swift`
- `spurwechsel/DesignSystem/ViewStyles.swift`

## Token Model
Each palette uses `ThemeToken -> ThemeColor`.

Supported tokens:

- `background`
- `backgroundSecondary`
- `panel`
- `panelRaised`
- `panelMuted`
- `border`
- `borderStrong`
- `foreground`
- `foregroundMuted`
- `foregroundDim`
- `accent`
- `accentForeground`
- `selection`
- `terminal`
- `terminalForeground`
- `success`
- `warning`
- `error`
- `info`
- `overlay`
- `overlayStrong`
- `shadow`

Hex values accept `#RRGGBB` or `#RRGGBBAA`.

## Theme Layers
- `ThemeSet`: light + dark palettes
- `ThemePalette`: concrete token map
- `SpurTheme`: SwiftUI-ready colors
- `TerminalTheme`: Ghostty terminal colors

`SpurwechselConfig.theme` stores effective theme after validation and fallback merge.

## Config Behavior
- user may override only subset of tokens
- missing tokens fall back to app defaults
- invalid token names are ignored
- invalid hex values produce diagnostics and fall back to defaults

## Runtime Behavior
- shell uses `layout.themeMode` to choose light or dark palette
- `ShellStore.themeSet` updates after config reload
- terminal surfaces use `projectConfig.theme.terminalTheme`

## When Editing Theme Code
- add token to `ThemeToken`
- add default values to both palettes
- update resolver if validation rules change
- confirm `SpurTheme` and terminal mapping both expose token
