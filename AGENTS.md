run unit tests with `./scripts/test-macos.sh`.
document all flaky tests in flaky-tests.md.
do not run UI tests.
verify that the app builds with `./scripts/build-unsigned-macos.sh build`
do not verify if the app builds when just changing markdown files.
keep `CHANGELOG.md` current with high-level user-facing changes.

docs start: `docs/quick-links.md`
docs map:
- `docs/product-overview.md`: app scope and subsystem map
- `docs/app-architecture.md`: store/coordinator/runtime architecture
- `docs/layout-navigation.md`: shell and surface behavior
- `docs/configuration.md`: config file and validation rules
- `docs/workspace-and-git.md`: repo import and worktree lifecycle
- `docs/agent-runtime.md`: agent session and terminal runtime
- `docs/vscode-runtime.md`: `code-server` and webview runtime
- `docs/design-tokens.md`: theme tokens and overrides
