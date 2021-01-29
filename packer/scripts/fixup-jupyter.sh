#!/bin/bash

set -x

# 2. Fix allow_remote to jupyter
JUPYTER_CONF=/var/opt/xcalar/.jupyter/jupyter_notebook_config.py
sed -i '/c.NotebookApp.allow_remote_access/d' $JUPYTER_CONF
echo "c.NotebookApp.allow_remote_access = True" >> $JUPYTER_CONF

exit 0
