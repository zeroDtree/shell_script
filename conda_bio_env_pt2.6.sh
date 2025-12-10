# torch
pip install torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 --index-url https://download.pytorch.org/whl/cu124
# deeplearning package
pip install wandb tensorboard omegaconf pandas datasets exrex peft psutil torchdiffeq setuptools tqdm transformers==4.48.3 einops bitsandbytes graphviz torchviz matplotlib PyQt6 hydra-core ipykernel diffusers overrides ipywidgets tabulate fire flow_matching numpy safetensors biotite

# scatter-cluster
pip install torch-scatter -f https://data.pyg.org/whl/torch-2.6.0+cu124.html
pip install torch-cluster -f https://data.pyg.org/whl/torch-2.6.0+cu124.html
pip install  torch_geometric 

# bio
pip install fair-esm vina lmdb easydict openbabel-wheel rdkit scipy biopython openmm  absl-py  timm  seaborn  ml_collections Ninja dm-tree modelcif dgl black pylint autoflake opt_einsum pypulchra
pip install chempy scikit-learn tmtools

conda install -c conda-forge libstdcxx-ng=13 -y
conda install -c conda-forge -c schrodinger pymol-bundle
