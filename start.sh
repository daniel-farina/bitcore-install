#!/bin/bash

# Source NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" # This loads nvm 
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion 

# Start Bitcore Services (and Daemon)
nvm use v9 #v4

./node_modules/bitcore-node/bin/bitcore-node start
# (run this from where you ran `bitcore create x` (btcp-bitcore-node))
# (or, if set up like the >= 5.0 bitpay website instructions, just `bitcored`)
