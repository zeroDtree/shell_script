#!/usr/bin/env fish

# Define UV environment path
set UV_ENV_PATH "$HOME/.uv/venvs"

# Function to list all environments
function uv_list
    if test -d "$UV_ENV_PATH"
        echo "UV Environments:"
        ls $UV_ENV_PATH
    else
        echo "No UV environments found."
    end
end

# Function to activate an environment
function uv_activate
	set -l env_name $argv[1]
    if test -z "$env_name"
        echo "Usage: uv activate <env_name>"
        return 1
    end

    set ENV_PATH "$UV_ENV_PATH/$env_name"
    
    if test -d "$ENV_PATH"
        source "$ENV_PATH/bin/activate.fish"
        echo "Activated UV environment: $env_name"
    else
        echo "Environment '$env_name' not found."
    end
end

# Function to create a new environment
function uv_create
	set -l env_name $argv[1]
    if test -z "$env_name"
        echo "Usage: uv create <env_name>"
        return 1
    end

    set ENV_NAME $env_name
    set ENV_PATH "$UV_ENV_PATH/$ENV_NAME"

    uv venv $ENV_PATH $argv[2..-1]
    echo "Environment '$ENV_NAME' created!"
end

# Function to remove an environment
function uv_delete
	set -l env_name $argv[1]
    if test -z "$env_name"
        echo "Usage: uv remove <env_name>"
        return 1
    end

    set ENV_PATH "$UV_ENV_PATH/$env_name"

    if test -d "$ENV_PATH"
        rm -rf "$ENV_PATH"
        echo "Environment '$env_name' deleted."
    else
        echo "Environment '$env_name' not found."
    end
end

# Function to forward other uv commands
function uv
    if test (count $argv) -eq 0
        echo "Usage: uv <command> [arguments]"
        return 1
    end

    switch $argv[1]
        case "list"
            uv_list
        case "activate"
            uv_activate $argv[2]
        case "create"
            uv_create $argv[2..-1]
        case "delete"
            uv_delete $argv[2]
        case "*"
            # Pass all other commands directly to uv
            command uv $argv[1..-1]
    end
end
