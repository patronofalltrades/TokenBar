// Claude Code runs `TokenBar --statusline` for each status line update. Do not start the UI on this path.
if CommandLine.arguments.contains("--statusline") {
    StatuslineBridge.main()
} else {
    TokenBarApp.main()
}
