#!/bin/bash

if ! test -e $HOME/.gpg.env; then
    gpg-agent --daemon --pinentry-program /usr/bin/pinentry-curses --write-env-file $HOME/.gpg.env
fi
source $HOME/.gpg.env
export GPG_AGENT_INFO
if [ -S "$(echo $GPG_AGENT_INFO | sed -e 's/:.*$//g')" ]; then
	printf "$(cat ~/.gpg.env); export GPG_AGENT_INFO\n"
	exit 0
fi
