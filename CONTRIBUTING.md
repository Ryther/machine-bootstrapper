# Contributing to machine-bootstrapper

Thank you for your interest in contributing to machine-bootstrapper! This guide will help you get started with the development workflow and conventions.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Development Setup](#development-setup)
- [Commit Convention](#commit-convention)
- [Branch Naming Convention](#branch-naming-convention)
- [Docker-Based Tooling](#docker-based-tooling)
- [GitHub Rulesets](#github-rulesets)
- [Pull Request Process](#pull-request-process)

## Prerequisites

- **Git**: Version control system
- **Docker** (recommended): For using standardized development tools without local installation
- **POSIX shell**: sh, bash, zsh, or similar for running scripts

## Development Setup

### Clone the Repository

```bash
git clone git@github.com:Ryther/machine-bootstrapper.git
cd machine-bootstrapper
```

### Install Development Tools (Optional)

You can install tools locally or use Docker aliases (see [Docker-Based Tooling](#docker-based-tooling)).

#### Local Installation

**Commitizen (Python-based):**
Supported version: 4.10.0
```bash
# Using pip
pip3 install --user commitizen

# Verify installation
cz version
```

**ShellCheck:**
Supported version: 0.11.0
```bash
# Debian/Ubuntu
sudo apt-get install shellcheck

# macOS
brew install shellcheck

# Fedora/RHEL
sudo dnf install ShellCheck
```

## Commit Convention

This project uses **Conventional Commits** with GitHub issue references. All commits **must** follow this format:

```
<type>(<scope>): [gh-<issue>] <description>

[optional body]

[optional footer]
```

### Commit Types

| Type | Description |
|------|-------------|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation only changes |
| `style` | Code style changes (formatting, missing semicolons, etc.) |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvements |
| `test` | Adding or correcting tests |
| `build` | Changes to build system or external dependencies |
| `ci` | Changes to CI configuration files and scripts |
| `chore` | Other changes that don't modify src or test files |
| `devcontainer` | Changes to development container configuration |
| `conf` | Configuration changes |

### Scope (Optional)

Scope can be anything specifying the place of the commit change:
- `bootstrap` - Changes to bootstrap.sh
- `docs` - Documentation changes
- `ci` - CI/CD configuration
- `workflow` - GitHub Actions workflows
- `readme` - README.md changes
- etc.

### Examples

```bash
# Feature with scope
feat(bootstrap): [gh-1] add SSH key generation with QR code display

# Fix without scope
fix: [gh-15] resolve path handling for spaces in filenames

# Documentation
docs(readme): [gh-7] update installation instructions

# Configuration
conf(commitizen): [gh-23] add custom type definitions
```

### Using Commitizen

Commitizen provides an interactive prompt to create properly formatted commits:

```bash
# Using local installation
cz commit

# Using Docker alias (see below)
git-cz commit
```

Follow the prompts to:
1. Select commit type
2. Enter scope (optional)
3. Enter GitHub issue number (e.g., `42` for `gh-42`)
4. Write short description
5. Add body/footer (optional)

## Branch Naming Convention

Branch names **must** follow this pattern:

```
<type>/gh-<issue>_<description>
```

### Examples

```bash
feat/gh-1_add-ssh-key-generation
fix/gh-15_resolve-path-handling
docs/gh-7_update-installation-guide
refactor/gh-42_improve-error-handling
```

### Creating a New Branch

```bash
# Create and switch to a new branch
git checkout -b feat/gh-42_add-new-feature
```

## Docker-Based Tooling

To avoid version mismatches and local installation complexity, we provide Docker-based aliases for all development tools.

### Setup Docker Aliases

Add these aliases to your shell configuration file (`~/.bashrc`, `~/.zshrc`, etc.):

- Commitizen:
  ```bash
  alias cz='docker run --rm -it -v "$PWD":/app --entrypoint /bin/sh commitizen/commitizen:4.10.0 -c '\''git config --global --add safe.directory /app && cz "$@"'\'' --'
  ```
- ShellCheck
  ```bash
  alias shellcheck='docker run --rm -v "$(pwd):/mnt" koalaman/shellcheck:v0.11.0'
  ```
Reload your shell configuration:
```bash
source ~/.bashrc  # or ~/.zshrc
```

### Using Docker Aliases

```bash
# Create a commit using Commitizen
cz c

# Run ShellCheck on bootstrap.sh
shellcheck bootstrap.sh
```

### Advantages of Docker-Based Tooling

* ✅ **No local installation required** - Just need Docker
* ✅ **Version consistency** - Everyone uses the same tool versions
* ✅ **Clean environment** - No conflicts with system packages
* ✅ **Cross-platform** - Works on Linux, macOS, Windows (with WSL)
* ✅ **Easy updates** - Pull new image versions as needed

## GitHub Rulesets

This repository uses GitHub Rulesets to enforce code quality and conventions. The rulesets are configured in `_test/` and can be uploaded to GitHub:

### Ruleset Enforcement

The following rules are enforced:

1. **Commit Message Format**: All commits must match:
   ```
   ^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|devcontainer|conf)(\(.+\))?: \[gh-\d+\] .+$
   ```

2. **Branch Naming**: All feature branches must match:
   ```
   ^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|devcontainer|conf)/gh-\d+_.+$
   ```

3. **PR Required**: Direct pushes to `main` are blocked; all changes must go through pull requests

4. **Status Checks**: ShellCheck CI must pass before merging

## Pull Request Process

1. **Create an issue** on GitHub describing the problem or feature
2. **Create a branch** following the naming convention: `type/gh-N_description`
3. **Make changes** and commit using conventional commits format
4. **Test locally**:
   ```bash
   # Run ShellCheck
   shellcheck bootstrap.sh

   # Test the script
   bash -n bootstrap.sh  # Syntax check
   ```
5. **Push your branch**:
   ```bash
   git push origin feat/gh-42_your-feature
   ```
6. **Open a Pull Request** on GitHub:
   - Reference the issue in the PR description: `Closes #42`
   - Ensure CI checks pass (ShellCheck)
   - Wait for review and approval
7. **Squash and merge** or **Merge** (with clean commit history)

### PR Title Convention

PR titles should follow the same convention as commits:
```
feat(bootstrap): [gh-42] add SSH key generation
```

## Development Workflow Example

```bash
# 1. Create issue on GitHub: "Add verbose logging"
# Issue number: gh-84

# 2. Create feature branch
git checkout -b feat/gh-84_add-verbose-logging

# 3. Make changes
vim bootstrap.sh

# 4. Test changes
shellcheck bootstrap.sh
bash -n bootstrap.sh

# 5. Commit using commitizen
cz commit

# Follow prompts:
# - Type: feat
# - Scope: bootstrap
# - Issue: 84
# - Description: add verbose logging option

# 6. Push branch
git push origin feat/gh-84_add-verbose-logging

# 7. Open PR on GitHub
# Title: feat(bootstrap): [gh-84] add verbose logging option
# Body: Closes #84

# 8. Wait for CI and review
# 9. Merge when approved
```

## Questions or Issues?

If you have questions or encounter issues:

1. Check existing [GitHub Issues](https://github.com/Ryther/machine-bootstrapper/issues)
2. Review the [README.md](README.md) for project overview
3. Create a new issue if needed

Thank you for contributing! 🎉
