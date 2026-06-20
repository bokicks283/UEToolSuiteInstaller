# Repository test instructions

- Use `Tests/Run-UEToolSuiteTests.ps1` as the public suite entrypoint.
- Select the narrowest named suite.
- Use `-FailFast` while iterating.
- Do not run mutating/exclusive suites in an active working tree unless required and understood.
- Packaging tests are required when managed payload files or manifests change.
- Tests should describe protected behavior rather than mirror implementation.
- Never weaken an assertion to accommodate a new implementation.
