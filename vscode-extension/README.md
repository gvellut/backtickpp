# Backtick++ VS Code Extension

This is the VS Code extension component of Backtick++. It provides the user interface and commands for advanced window switching on macOS.

## Development

1. Install dependencies: `npm install`
2. Compile TypeScript: `npm run compile`
3. Open in VS Code and press F5 to launch Extension Development Host

## Building

- `npm run compile` - Compile TypeScript
- `npm run watch` - Watch mode for development
- `npx vsce package` - Create VSIX package

The extension requires the Swift helper process to be built and available at `../swift-helper/.build/release/backtick-plus-plus-helper`.
