# Contributing

Testing Locally:

```shell
asdf plugin test <plugin-name> <plugin-url> [--asdf-tool-version <version>] [--asdf-plugin-gitref <git-ref>] [test-command*]

# TODO: adapt this
asdf plugin test anchor-lang https://github.com/inspi-writer001/asdf-anchor-lang.git "anchor-lang --help"
```

Tests are automatically run in GitHub Actions on push and PR.
