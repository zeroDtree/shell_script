# shell_script

A few useful scripts. Pass `--help` to a script for its options.

## Environments

- [`uv_install.sh`](uv_install.sh) installs the uv binary.
- [`auv.fish`](auv.fish) adds Fish commands (`list`, `activate`, `create`, `delete`) for virtualenvs under `~/.uv/venvs`, and forwards every other command to `uv`.
- [`miniconda_install.sh`](miniconda_install.sh) installs Miniconda on Linux and disables auto-activation of base.
- [`micromamba_install.sh`](micromamba_install.sh) installs micromamba and pins conda-forge.
- [`conda_env_mgr.sh`](conda_env_mgr.sh) packs an environment with conda-pack, or unpacks that archive and runs conda-unpack.
- [`cuda_install.sh`](cuda_install.sh) installs the CUDA toolkit only, from a Linux runfile, into a user prefix.

## Proxy

- [`clash_install.sh`](clash_install.sh) downloads a Clash binary, gunzips it, and marks it executable.
- [`clash_switch.sh`](clash_switch.sh) turns on the Clash HTTP API if needed and switches the active node in a proxy group.

## Repos and files

- [`update_repo.sh`](update_repo.sh) clones a repository or fast-forwards an existing checkout.
- [`git_re_init.sh`](git_re_init.sh) rebuilds the current repository from its origin and keeps submodules.
- [`mv_to_home.sh`](mv_to_home.sh) moves a path into a user's home directory and runs `chown -R`.
