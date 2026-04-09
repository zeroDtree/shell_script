sudo apt update

# 1. Basic system tools (networking, editors, terminal multiplexers)
sudo apt install -y \
    wget curl git git-lfs vim ssh openssh-server \
    fish zsh tmux screen tree parallel \
    dos2unix enca patchelf

# 2. Build and development toolchain (C++, Rust, Python, Go tooling, etc.)
sudo apt install -y \
    build-essential cmake autoconf make \
    gcc g++ python3-dev cargo rustc \
    libboost-all-dev libarchive-dev libxml2-dev libgmp-dev zlib1g-dev

# 3. High-performance computing (HPC) and math libraries (research/simulation)
sudo apt install -y \
    libblas-dev liblapack-dev libfftw3-dev \
    libscalapack-mpi-dev mpi-default-dev libopenmpi-dev \
    libxc-dev libnetcdf-dev libmsgpack-dev libspatialindex-dev

# 4. Bioinformatics, chemistry, and 3D visualization
sudo apt install -y \
    ncbi-blast+ clustalo openbabel \
    pymol clinfo

# 5. System monitoring, stress testing, and GPU tools
sudo apt install -y \
    htop btop nvtop stress \
    graphviz dkms

# 6. Downloads, proxies, and remote connectivity
# Note: v2raya and gsutil usually need an extra PPA or repo; this section covers basic packages only
sudo apt install -y \
    aria2 axel proxychains4 openvpn \
    mutt msmtp

# 7. Compression, filesystem tools, and multimedia
sudo apt install -y \
    unrar p7zip-full rar zip \
    gparted xfsprogs uidmap extundelete \
    ffmpeg mplayer