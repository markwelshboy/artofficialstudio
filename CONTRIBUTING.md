# Contributing

Thanks for your interest in improving this diffusion pod runtime!

This project is based on an original RunPod template. The goal of this fork is to:

- Make the container **provider-agnostic** (RunPod, Vast, local Docker, etc.).
- Move Hugging Face + pip + uv **cache configuration** out of the Dockerfile and into `start.sh`.
- Improve **Nginx behavior** based on environment variables (RunPod / Vast / local).
- Provide a cleaner base for ComfyUI / training workflows on GPU pods.

## Repository remotes

This fork typically uses two Git remotes:

- `origin` – this repository (e.g. `https://github.com/markwelshboy/artofficialstudio.git`)
- `upstream` – the original author's repo

If you have only `origin` and want to add `upstream`:

```bash
git remote add upstream https://github.com/ORIGINAL_AUTHOR/ORIGINAL_REPO.git
git fetch upstream
