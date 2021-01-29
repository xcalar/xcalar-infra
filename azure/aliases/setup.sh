#!/bin/bash

if ! az extension show -n alias >/dev/null; then
    az extension add -n alias
fi
DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
ln -sfT "$DIR/alias.ini" $HOME/.azure/alias
ln -sfT "$DIR/alias_tab_completion.json" $HOME/.azure/alias_tab_completion
