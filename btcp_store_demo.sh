#!/bin/bash

# !!! EC2 - Make sure port 8001 is in your security group

# !!! Run this in a fresh environment. 

install_ubuntu() {

# Get Ubuntu Dependencies
sudo apt-get update 

sudo apt-get -y install \
  build-essential pkg-config libc6-dev m4 g++-multilib \
  autoconf libtool ncurses-dev unzip git python \
  zlib1g-dev wget bsdmainutils automake

# Install ZeroMQ libraries (Bitcore)
sudo apt-get -y install libzmq3-dev

}

make_swapfile() {

# You must have enough memory for the BTCP build to succeed.

local PREV=$PWD
cd /
sudo dd if=/dev/zero of=swapfile bs=1M count=3000
sudo mkswap swapfile
sudo chmod 0600 /swapfile
sudo swapon swapfile
echo "/swapfile none swap sw 0 0" | sudo tee -a etc/fstab > /dev/null
cd $PREV

}

prompt_swapfile() {

echo ""
echo "Can we make you a 3gb swapfile? EC2 Micro needs it because it takes a lot of memory to build BTCP."
echo ""
read -r -p "[y/N] " response
case "$response" in
    [yY][eE][sS]|[yY]) 
        make_swapfile
        ;;
    *)
        echo "Not creating swapfile."
        ;;
esac

}

clone_and_build_btcp() {

# Clone latest Bitcoin Private source, and checkout explorer-btcp
if [ ! -e ~/BitcoinPrivate ]
then
  git clone -b explorer-btcp https://github.com/BTCPrivate/BitcoinPrivate
fi

# Freshen up
#git checkout explorer-btcp
#git checkout -- .
#git pull

# Fetch BTCP/Zcash ceremony params
./BitcoinPrivate/btcputil/fetch-params.sh

# Build Bitcoin Private
./BitcoinPrivate/btcputil/build.sh -j$(nproc)

}

init_btcprivate_dotdir() {

# Make .btcprivate dir (btcpd hasn't been run) 
if [ ! -e ~/.btcprivate/ ]
then
  mkdir ~/.btcprivate
fi

# Make empty btcprivate.conf if needed; otherwise use existing
if [ ! -e ~/.btcprivate/btcprivate.conf ]
then

local RPCPASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
touch ~/.btcprivate/btcprivate.conf
cat << EOF > ~/.btcprivate/btcprivate.conf
#gen=1
#reindex=1
#showmetrics=0
#rpcport=7932
rpcuser=bitcoin
rpcpassword=$RPCPASSWORD
server=1
whitelist=127.0.0.1
txindex=1
addressindex=1
timestampindex=1
spentindex=1
zmqpubrawtx=tcp://127.0.0.1:28332
zmqpubhashblock=tcp://127.0.0.1:28332
rpcallowip=127.0.0.1
uacomment=bitcore
addnode=dnsseed.btcprivate.org
showmetrics=0
EOF

fi

cd ~/.btcprivate

# Download + decompress blockchain.tar.gz (blocks/, chainstate/) to quickly sync past block 300,000
fetch_btcp_blockchain

}

fetch_zcash_params() {

wget -qO- https://raw.githubusercontent.com/BTCPrivate/BitcoinPrivate/master/btcputil/fetch-params.sh | bash

}

fetch_btcp_blockchain() {

cd ~/.btcprivate

local FILE="blockchain-explorer.tar.gz"
wget -c https://storage.googleapis.com/btcpblockchain/$FILE
tar -zxvf $FILE
echo "Downloading and extracting blockchain files - Done."
rm -rf $FILE

}

fetch_btcp_binaries() {

mkdir -p ~/BitcoinPrivate/src
cd ~/BitcoinPrivate/src

local RELEASE="1.0.12"
local COMMIT="69aa9ce"
local FILE="btcp-${RELEASE}-explorer-${COMMIT}-linux.tar.gz"
wget -c https://github.com/BTCPrivate/BitcoinPrivate/releases/download/${RELEASE}-${COMMIT}/${FILE}
tar -zxvf $FILE
echo "Downloading and extracting BTCP files - Done."
rm -rf $FILE

}

install_nvm_npm() {

cd ~

# Install npm 
sudo apt-get -y install npm

# Install nvm (npm version manager)
wget -qO- https://raw.githubusercontent.com/creationix/nvm/master/install.sh | bash

# Set up nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" # This loads nvm 
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion 

# Install node v4 (as the default)
nvm install v4
nvm use v4
nvm alias default v4

}

# MongoDB dependency for bitcore:

install_mongodb() {

sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 2930ADAE8CAF5059EE73BB4B58712A2291FA4AD5
# Ubuntu >= 16; for prior versions, see mongodb website
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.6 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-3.6.list
sudo apt-get update
sudo apt-get install -y mongodb-org

# Make initial empty db dir
sudo mkdir -p /data/db

}

install_bitcore() {

cd ~

# Install Bitcore (Headless)
npm install BTCPrivate/bitcore-node-btcp

# Create Bitcore Node
./node_modules/bitcore-node-btcp/bin/bitcore-node create btcp-explorer
cd btcp-explorer

# Install Insight API / UI (Explorer) (Headless)
../node_modules/bitcore-node-btcp/bin/bitcore-node install BTCPrivate/insight-api-btcp BTCPrivate/insight-ui-btcp BTCPrivate/store-demo # BTCPrivate/address-watch, BTCPrivate/bitcore-wallet-service (untested)

# Symlink to bitcore-node to btcp-explorer dir
ln -s node_modules/bitcore-node-btcp/bin/bitcore-node bitcore-node

local BITCORE_SERVICE_APP="store-demo" #address-watch, bitcore-wallet-service
local PORT=8001

# Create config file for Bitcore
cat << EOF > bitcore-node.json
{
  "network": "livenet",
  "port": $PORT,
  "services": [
    "bitcoind",
    "insight-api-btcp",
    "web"
  ],
  "servicesConfig": {
    "bitcoind": {
      "spawn": {
        "datadir": "$HOME/.btcprivate",
        "exec": "$HOME/BitcoinPrivate/src/btcpd"
       }
     },
     "insight-api-btcp": {
       "routePrefix": "api"
     }
  }
}
EOF

#TODO Prompt option + Automate SSL Setup (LetsEncrypt)
#"https": true,
#"privateKeyFile": "/etc/ssl/bws.bitpay.com.key",
#"certificateFile": "/etc/ssl/bws.bitpay.com.crt",

}

install_bower_browserify_js_libs() {
  echo "Globally installing bower, browserify"
  npm install -g bower browserify
  #sudo npm install -g pm2

  # Build bitcore-lib-btcp.js + copy to invoice server's js/ dir
  cd ~/btcp-explorer/node_modules/store-demo
  bower install --allow-root
  cd node_modules/bitcore-lib-btcp
  browserify --require ./index.js:bitcore-lib-btcp -o bitcore-lib-btcp.js
  cp bitcore-lib-btcp.js ~/btcp-explorer/node_modules/store-demo/static/js/bitcore-lib-btcp
}


run_install() {

echo ""
echo "BTCP Merchant Backend Setup - Installing dependencies."
echo ""

install_ubuntu > /dev/null

echo ""
echo "How would you like to fetch BTCP (btcpd and btcp-cli):"
echo "1) [fast] Download the latest binaries"
echo "2) [slow] Download + build from source code"
echo ""
read -r -p "[1/2] " response
case "$response" in
    [1]) 
        fetch_zcash_params
        fetch_btcp_binaries
        ;;
    [2])
        prompt_swapfile
        clone_and_build_btcp
        ;;
    *)
        echo "Neither; Skipped."
        ;;
esac

init_btcprivate_dotdir

install_nvm_npm

install_mongodb

install_bitcore

install_bower_browserify_js_libs

echo "Installation Complete."
echo "" 

# Verify that nvm is exported
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" # This loads nvm 
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion 

echo "To start the daemon + its interfaces, run:"
echo "cd ~/btcp-explorer; ./bitcore-node start"
echo ""
echo "Runs on port $PORT (bitcore-node.json)."
echo ""

}


# *** SCRIPT START ***

cd ~ 
run_install

