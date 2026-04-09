if status is-interactive
# Commands to run in interactive sessions can go here
end
# Created by newuser for 5.9


# >>> isolation template config.fish >>>

if status is-interactive
# Commands to run in interactive sessions can go here
end
# Created by newuser for 5.9

# Add paths only if they are not already in PATH
function add_to_path
    for dir in $argv
        if not contains $dir $PATH
            set -gx PATH $dir $PATH
        end
    end
end

function add_to_path_config
    set -gx PATH $argv $PATH
    echo add_to_path $argv >> ~/.config/fish/config.fish
end

function add_pwd_to_path_config
    set -gx PATH (pwd) $PATH
    echo add_to_path (pwd) >> ~/.config/fish/config.fish
end

set -gx LANG en_US.UTF-8

set -g proxy_port 17890
set -g proxy_ip 127.0.0.1

function proxy_on
    for var in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
        set -l cmd "set -gx $var http://$proxy_ip:$proxy_port"
        echo $cmd
        eval $cmd
    end
    set -gx no_proxy 127.0.0.1,localhost
    set -gx NO_PROXY 127.0.0.1,localhost
    echo -e "\033[32m[√] Proxy enabled\033[0m"
end

function proxy_off
    for var in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY no_proxy
        set -l cmd "set -e $var"
        echo $cmd
        eval $cmd
    end
    echo -e "\033[31m[×] Proxy disabled\033[0m"
end

function cuda
	set -l devs $argv[1]
	set -l argv $argv[2..-1]
	set -l cmd "CUDA_VISIBLE_DEVICES=$devs $argv"
	echo $cmd
	eval $cmd
end

function hfmon
	set -gx HF_ENDPOINT "https://hf-mirror.com"
end

function hfmoff
	set -e HF_ENDPOINT
end

function ca_off
	set -gx CURL_CA_BUNDLE ""
	set -gx REQUESTS_CA_BUNDLE ""
end

function ca_off
    set -gx __CURL_CA_BUNDLE_BACKUP $CURL_CA_BUNDLE
    set -gx __REQUESTS_CA_BUNDLE_BACKUP $REQUESTS_CA_BUNDLE

    set -gx CURL_CA_BUNDLE ""
    set -gx REQUESTS_CA_BUNDLE ""

    echo "CA bundle environment variables disabled and backed up."
end

function ca_on
    if set -q __CURL_CA_BUNDLE_BACKUP
        set -gx CURL_CA_BUNDLE $__CURL_CA_BUNDLE_BACKUP
    else
        set -e CURL_CA_BUNDLE
    end

    if set -q __REQUESTS_CA_BUNDLE_BACKUP
        set -gx REQUESTS_CA_BUNDLE $__REQUESTS_CA_BUNDLE_BACKUP
    else
        set -e REQUESTS_CA_BUNDLE
    end

    echo "CA bundle environment variables restored."
	echo "CURL_CA_BUNDLE=$CURL_CA_BUNDLE"
	echo "REQUESTS_CA_BUNDLE=$REQUESTS_CA_BUNDLE"
end

function start_if_not_running
	set -l process_name $argv[1]
	set -l command $argv[2..-1]

	if not pgrep -f "$process_name" >/dev/null
		echo "Starting $process_name..."
		eval $command &
		sleep 2
		echo "$process_name has been started successfully"
	else
		echo "$process_name is already running"
	end
end


# Canonical search roots (ignore any CUDA_DIRS inherited from the parent process).
set -gx CUDA_DIRS "$HOME/shared_software/cuda" "$HOME/software/cuda"
# Fish does not treat \t as a tab inside double quotes; use a real TAB (U+0009).
set -g __cuda_tab (printf '\t')

function __cuda_realpath -a p
	if command -v realpath >/dev/null 2>&1
		realpath "$p" 2>/dev/null; or echo "$p"
	else
		echo "$p"
	end
end

function __cuda_version_for_root -a root
	if not test -x "$root/bin/nvcc"
		return 1
	end
	set -l lines ("$root/bin/nvcc" -V 2>&1)
	for line in $lines
		set -l m (string match -r 'release ([0-9]+\.[0-9]+)' -- $line)
		if test (count $m) -ge 2
			echo $m[2]
			return 0
		end
	end
	set -l base (basename "$root")
	set -l m2 (string match -r '^cuda-([0-9]+\.[0-9]+)' -- $base)
	if test (count $m2) -ge 2
		echo $m2[2]
		return 0
	end
	return 1
end

function __cuda_collect_candidates
	set -l c
	for base in $CUDA_DIRS
		test -d "$base"; or continue
		for d in (command find "$base" -maxdepth 1 -mindepth 1 -type d -name 'cuda-*' 2>/dev/null)
			set -a c $d
		end
	end
	for d in /usr/local/cuda /opt/cuda /opt/homebrew/opt/cuda /usr/local/opt/cuda
		test -d "$d"; and set -a c $d
	end
	for d in (command find /usr/local -maxdepth 1 -mindepth 1 -type d -name 'cuda-*' 2>/dev/null)
		set -a c $d
	end
	printf '%s\n' $c
end

function __cuda_enumerate_valid_roots
	set -l seen_real
	set -l roots_out
	for raw in (__cuda_collect_candidates)
		test -z "$raw"; and continue
		test -x "$raw/bin/nvcc"; or continue
		set -l rp (__cuda_realpath "$raw")
		contains $rp $seen_real; and continue
		set -a seen_real $rp
		set -a roots_out $raw
	end
	printf '%s\n' $roots_out
end

function __cuda_discover
	set -l pairs
	set -l seen_real
	for raw in (__cuda_collect_candidates)
		test -z "$raw"; and continue
		test -x "$raw/bin/nvcc"; or continue
		set -l rp (__cuda_realpath "$raw")
		contains $rp $seen_real; and continue
		set -a seen_real $rp
		set -l ver (__cuda_version_for_root "$raw")
		or continue
		set -a pairs "$ver$__cuda_tab$raw"
	end
	set -l seen_v
	set -l filtered
	for pair in $pairs
		set -l fields (string split $__cuda_tab -- $pair)
		set -l ver $fields[1]
		set -l pa $fields[2]
		contains $ver $seen_v; and continue
		set -a seen_v $ver
		set -a filtered "$ver$__cuda_tab$pa"
	end
	printf '%s\n' $filtered | sort -t $__cuda_tab -k1,1V
end

function __cuda_normalize_version_arg -a want
	if string match -qr '^[0-9]+\.[0-9]+$' -- $want
		echo $want
		return
	end
	if string match -qr '^[0-9]{3}$' -- $want
		set -l major (string sub -s 1 -l 2 -- $want)
		set -l minor (string sub -s 3 -l 1 -- $want)
		echo "$major.$minor"
		return
	end
	echo $want
end

function __cuda_strip_cuda_paths
	set -l roots (__cuda_enumerate_valid_roots)
	set -l newp
	for entry in $PATH
		set -l drop false
		for r in $roots
			if test "$entry" = "$r/bin"
				set drop true
				break
			end
		end
		if test "$drop" = false
			set -a newp $entry
		end
	end
	set -gx PATH $newp
	if set -q LD_LIBRARY_PATH
		set -l newld
		for entry in $LD_LIBRARY_PATH
			set -l drop false
			for r in $roots
				if test "$entry" = "$r/lib64"
					set drop true
					break
				end
			end
			if test "$drop" = false
				set -a newld $entry
			end
		end
		set -gx LD_LIBRARY_PATH $newld
	end
end

function __cuda_apply -a root
	__cuda_strip_cuda_paths
	set -gx CUDA_HOME "$root"
	set -gx CUDA_PATH "$root"
	if test -d "$root/lib64"
		set -gx LD_LIBRARY_PATH "$root/lib64" $LD_LIBRARY_PATH
	end
	set -gx PATH "$root/bin" $PATH
end

function use_cuda
	set -l version_to_use $argv[1]
	if test -z "$version_to_use"
		echo "Available CUDA installations:"
		for line in (__cuda_discover)
			test -z "$line"; and continue
			set -l fields (string split $__cuda_tab -- $line)
			echo "  $fields[1]  ->  $fields[2]"
		end
		echo "Usage: use_cuda <version>   (e.g. 12.4 or 124)"
		return 0
	end
	set -l want (__cuda_normalize_version_arg "$version_to_use")
	for line in (__cuda_discover)
		test -z "$line"; and continue
		set -l fields (string split $__cuda_tab -- $line)
		if test "$fields[1]" = "$want"
			__cuda_apply "$fields[2]"
			echo "Switched to CUDA $fields[1]"
			echo "CUDA_HOME = $CUDA_HOME"
			return 0
		end
	end
	echo "Unknown or unsupported CUDA version: $version_to_use"
	set -l avail (__cuda_discover)
	if test (count $avail) -eq 0
		echo "No CUDA installations found (expected bin/nvcc under scanned roots)."
	else
		echo -n "Available versions: "
		set -l names
		for line in $avail
			set -l f (string split $__cuda_tab -- $line)
			set -a names $f[1]
		end
		echo (string join ', ' $names)
	end
	return 1
end

set -l __cuda_lines (__cuda_discover)
if test (count $__cuda_lines) -gt 0
	set -l __cuda_last $__cuda_lines[-1]
	set -l __cuda_fields (string split $__cuda_tab -- $__cuda_last)
	__cuda_apply "$__cuda_fields[2]"
else
	echo "CUDA: no installation found (scanned CUDA_DIRS and common system paths)." >&2
end

alias g++ 'g++ -finput-charset=UTF-8 -fexec-charset=UTF-8'
alias c++ 'c++ -finput-charset=UTF-8 -fexec-charset=UTF-8'
alias ls 'ls --color'
# <<< isolation template config.fish <<<



# isolation (main.typ)
umask 027


function zls
	if tmux has-session -t "zls$argv" 2>/dev/null
		echo "tmux attach-session -t zls$argv"
		tmux attach-session -t "zls$argv"
	else
		tmux new-session -s "zls$argv"
	end
end