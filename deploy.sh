#!/bin/bash

# redis-server
sudo apt-get install --force-yes -y --quiet redis-server

# utils
sudo apt-get install --force-yes -y --quiet wget tar curl

# mathjax 2.3
wget -O mathjax-2.3.0.zip https://github.com/mathjax/MathJax/archive/2.3.0.zip
unzip mathjax-2.3.0.zip -d public/ && mv public/MathJax-2.3.0 public/mathjax-2.3

# codemirror 3.22
wget http://codemirror.net/codemirror-3.22.zip
unzip codemirror-3.22.zip -d public/ && mv public/codemirror-3.22 public/codemirror

# phantomjs 1.9.7 x86_64
wget https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-1.9.7-linux-x86_64.tar.bz2
tar xf phantomjs-1.9.7-linux-x86_64.tar.bz2
sudo cp phantomjs-1.9.7-linux-x86_64/bin/phantomjs /usr/local/bin
rm -rf phantomjs-1.9.7-linux-x86_64*

# ruby 2.1 (rvm)
curl -sSL https://get.rvm.io | bash -s stable --ruby=2.1
echo 'source "$HOME/.rvm/scripts/rvm"' >> "$HOME/.bashrc"
source "$HOME/.rvm/scripts/rvm"
rvm use --default 2.1
gem install bundle

# rubygems & compass assets
bundle install
compass compile
