#!/bin/bash
set -e  # Exit the script if any statement returns a non-true return value

# ---------------------------------------------------------------------------- #
#                          Function Definitions                                #
# ---------------------------------------------------------------------------- #

# ---------------------------------------------------------------------------- #
#                      Runtime cache / HF configuration                        #
# ---------------------------------------------------------------------------- #

configure_caches() {
    local root="${HF_ROOT:-/workspace/.cache}"

    export HF_HOME="${HF_HOME:-${root}/huggingface}"
    export HF_DATASETS_CACHE="${HF_DATASETS_CACHE:-${HF_HOME}/datasets}"
    export DEFAULT_HF_METRICS_CACHE="${DEFAULT_HF_METRICS_CACHE:-${HF_HOME}/metrics}"
    export DEFAULT_HF_MODULES_CACHE="${DEFAULT_HF_MODULES_CACHE:-${HF_HOME}/modules}"
    export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE:-${HF_HOME}/hub}"
    export HUGGINGFACE_ASSETS_CACHE="${HUGGINGFACE_ASSETS_CACHE:-${HF_HOME}/assets}"

    export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-1}"

    export VIRTUALENV_OVERRIDE_APP_DATA="${VIRTUALENV_OVERRIDE_APP_DATA:-${root}/virtualenv}"
    export PIP_CACHE_DIR="${PIP_CACHE_DIR:-${root}/pip}"
    export UV_CACHE_DIR="${UV_CACHE_DIR:-${root}/uv}"

    mkdir -p \
        "$HF_HOME" \
        "$HF_DATASETS_CACHE" \
        "$DEFAULT_HF_METRICS_CACHE" \
        "$DEFAULT_HF_MODULES_CACHE" \
        "$HUGGINGFACE_HUB_CACHE" \
        "$HUGGINGFACE_ASSETS_CACHE" \
        "$VIRTUALENV_OVERRIDE_APP_DATA" \
        "$PIP_CACHE_DIR" \
        "$UV_CACHE_DIR"
}

# Start nginx service
start_nginx() {
    echo "Starting Nginx service..."

    # If both are empty -> NOT running on RunPod or Vast
    if [[ -z "${RUNPOD_POD_ID:-}" && -z "${VAST_CONTAINERLABEL:-}" ]]; then
        echo "GPU POD (Runpod or Vast) not detected, removing /etc/nginx/sites-available/default"
        rm -f /etc/nginx/sites-available/default
        if [[ -f /etc/nginx/sites-available/local ]]; then
            echo "Renaming /etc/nginx/sites-available/local to default"
            mv /etc/nginx/sites-available/local /etc/nginx/sites-available/default
            ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
        fi
    else
        echo "GPU POD (Runpod or Vast) detected, removing /etc/nginx/sites-available/local"
        rm -f /etc/nginx/sites-available/local
    fi

    service nginx start
}

# Execute script if exists
execute_script() {
    local script_path=$1
    local script_msg=$2
    if [[ -f ${script_path} ]]; then
        echo "${script_msg}"
        bash ${script_path}
    fi
}

# Setup ssh
setup_ssh() {
    if [[ $PUBLIC_KEY ]]; then
        echo "Setting up SSH..."
        mkdir -p ~/.ssh
        echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
        chmod 700 -R ~/.ssh

         if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
            ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -q -N ''
            echo "RSA key fingerprint:"
            ssh-keygen -lf /etc/ssh/ssh_host_rsa_key.pub
        fi

        if [ ! -f /etc/ssh/ssh_host_dsa_key ]; then
            ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key -q -N ''
            echo "DSA key fingerprint:"
            ssh-keygen -lf /etc/ssh/ssh_host_dsa_key.pub
        fi

        if [ ! -f /etc/ssh/ssh_host_ecdsa_key ]; then
            ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -q -N ''
            echo "ECDSA key fingerprint:"
            ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub
        fi

        if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
            ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -q -N ''
            echo "ED25519 key fingerprint:"
            ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
        fi

        service ssh start

        echo "SSH host keys:"
        for key in /etc/ssh/*.pub; do
            echo "Key: $key"
            ssh-keygen -lf $key
        done
    fi
}

export_env_vars() {
    echo "Exporting environment variables..."

    local outfile="/etc/pod_environment"
    : > "$outfile"

    # Keep interesting pod-related vars:
    #  - VAST_* / RUNPOD_*
    #  - HF_* and cache-related vars
    #  - ports for all the UIs
    #  - PATH for convenience
    printenv | grep -E '^(VAST_|RUNPOD_|HF_|PIP_CACHE_DIR=|UV_CACHE_DIR=|VIRTUALENV_OVERRIDE_APP_DATA=|CTRL_PNL_PORT=|FLUXGYM_PORT=|DIFFUSION_PIPE_UI_PORT=|KOHYA_UI_PORT=|TENSORBOARD_PORT=|COMFYUI_PORT=|JUPYTER_PORT=|PATH=|_=)' \
    | while IFS='=' read -r key val; do
        printf 'export %s=%q\n' "$key" "$val"
    done >> "$outfile"

    if ! grep -q 'source /etc/pod_environment' ~/.bashrc 2>/dev/null; then
        echo 'source /etc/pod_environment' >> ~/.bashrc
    fi
}

# Start jupyter lab
start_jupyter() {
    if [[ $JUPYTER_PASSWORD ]]; then
        echo "Starting Jupyter Lab..."
        mkdir -p /workspace && \
        cd / && \
        nohup python3.12 -m jupyter lab --allow-root --no-browser --port=8888 --ip=* --FileContentsManager.delete_to_trash=False --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' --ServerApp.token=$JUPYTER_PASSWORD --ServerApp.allow_origin=* --ServerApp.preferred_dir=/workspace & > /dev/null 2>&1 &
        echo "Jupyter Lab started"
    fi
}

# ---------------------------------------------------------------------------- #
#                               Main Program                                   #
# ---------------------------------------------------------------------------- #

echo "GPU Pod Started"

configure_caches
setup_ssh
start_nginx
execute_script "/scripts/comfy_setup.sh" "Running ComfyUI setup script..."
echo "ComfyUI Ready on port 0.0.0.0:$COMFYUI_PORT"
# Start JupyterLab
jupyter lab --ip=0.0.0.0 --port=$JUPYTER_PORT --ServerApp.base_url=/jupyter --no-browser --allow-root --ServerApp.allow_origin='*' --ServerApp.token='' --ServerApp.disable_check_xsrf=True --ServerApp.preferred_dir=/workspace --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' &
echo "JupyterLab started on /jupyter endpoint"
export_env_vars

execute_script "/scripts/setup_control_panel.sh" "Running control panel setup script..."

# Install and start TensorBoard
echo "Starting TensorBoard..."
python3.12 -m pip install tensorboard --root-user-action=ignore
tensorboard --logdir=/workspace/ComfyUI/models/loras --bind_all --path_prefix=/tensorboard --port=$TENSORBOARD_PORT &
echo "TensorBoard started on /tensorboard endpoint"

echo "Start script(s) finished, pod is ready to use."

wait