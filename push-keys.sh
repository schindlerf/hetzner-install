#!/bin/bash

# TODO: change to your needs
ssh-keygen -R server1.example.org
ssh-keygen -R server1
ssh-keygen -R 192.0.2.12

case $1 in
	del)
		;;
	*)
    # TODO: change to your needs
		ssh-copy-id server1
		;;
esac


