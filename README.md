# claude-code-bedrock

A Docker image for running [Claude Code](https://claude.ai/code) with [Amazon Bedrock](https://aws.amazon.com/bedrock/) inside a [Docker Sandbox](https://docs.docker.com/ai/sandboxes/) (`sbx`).

```
docker.io/thath/claude-code-bedrock
```

## What this is

`docker/sandbox-templates:claude-code` — the official base image used by `sbx` — does not include the AWS CLI or any AWS credential handling. This image adds:

- **AWS CLI v2** (multi-arch: `linux/amd64` and `linux/arm64`)
- **An entrypoint** that bridges a known `sbx` quirk: `sbx` mounts host directories at their original host path (e.g. `/Users/alice/.aws`) rather than at the container user's `$HOME` (`/home/agent`). The entrypoint detects those mounts and symlinks them into `$HOME` before Claude Code starts.

Everything else — Claude Code itself, Node.js, git — comes from the upstream `docker/sandbox-templates:claude-code` base image.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (for building)
- [`sbx`](https://docs.docker.com/ai/sandboxes/) — Docker Sandboxes CLI
- An [AWS account](https://aws.amazon.com/) with [Amazon Bedrock model access](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html) enabled
- AWS credentials configured locally (SSO, IAM user, or any standard method)

## Quick start

### 1. Configure Claude Code for Bedrock

Create `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_PROFILE": "your-aws-profile",
    "AWS_REGION": "us-east-1",
    "ANTHROPIC_MODEL": "us.anthropic.claude-sonnet-4-6"
  }
}
```

Replace `your-aws-profile` with the profile name from your `~/.aws/config`, and set `region` to the AWS region where you have Bedrock access.

Available model IDs can be found in the [Amazon Bedrock documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/model-ids.html). Use cross-region inference profile IDs (prefixed with `us.`) for higher availability.

### 2. Run in a sandbox

```bash
cd ~/my-project
sbx run --template thath/claude-code-bedrock claude . ~/.aws:ro ~/.claude:ro
```

`sbx` pulls the image from Docker Hub on first use. On subsequent runs for the same project, omit `--template` to reuse the existing sandbox:

```bash
sbx run claude-my-project
```

## How credentials work

`sbx` mounts host directories at their literal host path inside the sandbox VM. For example, `~/.aws` on a Mac becomes `/Users/alice/.aws` inside the container — not `/home/agent/.aws`.

The entrypoint (`entrypoint.sh`) resolves this automatically:

1. It parses `/proc/mounts` for `virtiofs` entries (the filesystem type used by `sbx`) to find where `~/.aws` and `~/.claude` were mounted.
2. It creates symlinks from `/home/agent/.aws` and `/home/agent/.claude` to those mount points.
3. It then hands off to `claude --dangerously-skip-permissions`.

`~/.claude/settings.json` contains the `env` block that Claude Code reads to configure Bedrock — specifically `CLAUDE_CODE_USE_BEDROCK`, `AWS_PROFILE`, `AWS_REGION`, and `ANTHROPIC_MODEL`. These are injected into the process environment at startup, so standard AWS credential resolution picks up the named profile from the symlinked `~/.aws/config`.

### Supported credential types

Any credential type supported by the AWS SDK credential chain works:

| Method | How to use |
|--------|-----------|
| AWS SSO | Configure a named profile in `~/.aws/config`, mount `~/.aws:ro` |
| IAM user access keys | `~/.aws/credentials` file, mount `~/.aws:ro` |
| ECS task role / EC2 instance profile | No mount needed; SDK resolves via instance metadata |

### Note on `--dangerously-skip-permissions`

The base image runs Claude Code with `--dangerously-skip-permissions`. This is the standard way to run Claude Code inside a sandbox, where the container boundary itself provides isolation. Do not use this flag outside of a sandboxed environment.

## Managing sandboxes

```bash
# List all sandboxes
sbx ls

# Stop a sandbox without removing it
sbx stop claude-my-project

# Remove a sandbox
sbx rm claude-my-project
```

## Building the image yourself

```bash
# Build locally (current architecture only)
./build.sh

# Build multi-arch and push to Docker Hub
./build.sh --push

# Build multi-arch, push, and also tag a specific version
./build.sh --push --tag 1.2.3
```

`--push` requires that you are logged in to Docker Hub (`docker login`) and that you update the `IMAGE` variable in `build.sh` to point to your own repository.

## Automated releases via GitHub Actions

The included `.github/workflows/release.yml` workflow builds and pushes a multi-arch image automatically:

- **On a git tag** (`v*`): pushes `latest` and a version tag derived from the tag name (e.g. `git tag v1.2.3` → `1.2.3` and `latest`).
- **On manual trigger** (`workflow_dispatch`): pushes `latest` and an optional additional tag.

### Setup

Add the following secrets to your GitHub repository (**Settings → Secrets and variables → Actions**):

| Secret | Value |
|--------|-------|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | A Docker Hub [access token](https://hub.docker.com/settings/security) with `Read & Write` scope |

Then update the `IMAGE` variable at the top of `.github/workflows/release.yml` to match your Docker Hub repository.

### Releasing a new version

```bash
git tag v1.2.3
git push origin v1.2.3
```

The workflow pushes `thath/claude-code-bedrock:1.2.3` and `thath/claude-code-bedrock:latest`.

## Repository structure

```
.
├── Dockerfile             # Extends docker/sandbox-templates:claude-code with AWS CLI
├── entrypoint.sh          # Symlinks host-mounted dirs into $HOME at startup
├── build.sh               # Local build and Docker Hub push script
├── .dockerignore          # Keeps build context minimal
└── .github/
    └── workflows/
        └── release.yml    # Automated multi-arch build and push on git tags
```

## Related

- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code) — Claude Code documentation
- [Claude Code with Amazon Bedrock](https://docs.anthropic.com/en/docs/claude-code/bedrock) — Bedrock setup guide
- [docker/sandbox-templates](https://hub.docker.com/r/docker/sandbox-templates) — upstream base images
- [Docker Sandbox docs](https://docs.docker.com/sandbox/) — `sbx` CLI documentation
