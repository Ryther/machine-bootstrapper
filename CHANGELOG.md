## v3.4.1 (2025-11-30)

### Bug Fixes

- **bootstrap**: [gh-1] in dry run create the temp dir only when cloning

## v3.4.0 (2025-11-30)

### Features

- **bootstrap**: [gh-1] use temp dir for dry-run clone

## v3.3.1 (2025-11-30)

### Bug Fixes

- **bootstrap**: [gh-1] avoid dirname/basename in version parsing

## v3.3.0 (2025-11-30)

### Features

- **bootstrap**: [gh-1] add --provisioning-tag
- **bootstrap**: [gh-1] show runtime version

## v3.2.0 (2025-11-30)

### Features

- **bootstrap**: [gh-1] propagate dry-run flag to provisioning script with interactive prompt

## v3.1.0 (2025-11-30)

### Features

- **bootstrap**: [gh-1] add automatic provisioning repository update on re-run

## v3.0.0 (2025-11-30)

### BREAKING CHANGE

- provisioning script no longer runs with sudo by default

### Features

- **bootstrap**: [gh-1] parametrize the sudo execution of the provisioning script and make it not default

## v2.0.1 (2025-11-29)

### Bug Fixes

- **bootstrap**: use consistent absolute path for script execution

## v2.0.0 (2025-11-29)

### Features

- **bootstrap**: replace positional params with explicit flags

## v1.0.1 (2025-11-29)

### Bug Fixes

- **bootstrap**: force SSH identity when cloning private repository

### Documentation

- **boostrap**: fix version in the docstring
- **readme**: fix version badge and workflow reference

## v1.0.0 (2025-11-29)

### Bug Fixes

- **release**: exclude generated artifacts from source tarball to prevent tar file changed error
- **commitizen**: migrate to cz_customize and fix version tracking patterns

### Chores

- **gitignore**: add comprehensive gitignore baseline

### Code Refactoring

- **bootstrap**: centralize logging with unified log function

### Configuration

- **version**: add version tracking with commitizen integration
- **commitizen**: add Python commitizen configuration

### Documentation

- **readme**: add shellcheck workflow badge and refine version badge style
- **contributing**: improve commitizen docker alias with git safe directory
- **bootstrap**: add comprehensive header and docstrings to bootstrap script
- **readme**: update documentation with enhanced flow diagram and contributing guide
- **contributing**: add comprehensive contribution guide with Docker tooling
- **project**: add comprehensive project documentation

## v0.1.1 (2025-11-28)

### Features

- **repo**: initial commit
