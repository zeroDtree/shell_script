version=$1
cd Python-$version
sudo rm -rf /usr/local/software/python-$version
./configure --prefix=/usr/local/software/python-$version
sudo make
sudo make install
