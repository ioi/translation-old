#!/bin/bash

echo "acquiring root"
sudo whoami

echo "killing ruby"
killall ruby

echo "starting unicorns #1"
rm -f unicorn/pid && unicorn -c /home/linguist/Linguist/unicorn1.rb -D
echo "starting unicorns #2"
rm -f unicorn/pid && unicorn -c /home/linguist/Linguist/unicorn2.rb -D
echo "starting unicorns #3"
rm -f unicorn/pid && unicorn -c /home/linguist/Linguist/unicorn3.rb -D
echo "starting unicorns #4"
rm -f unicorn/pid && unicorn -c /home/linguist/Linguist/unicorn4.rb -D

echo "reloading nginx"
sudo /etc/init.d/nginx reload

echo "listing ports"
netstat -l -p --numeric-ports | grep -i '127.0.0.1:808'
