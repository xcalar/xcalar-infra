#!/bin/bash
if [ $# -eq 0 ]; then
    if [ -n "$GERRIT_REFSPEC" ]; then
        changeBranch="change-${GERRIT_CHANGE_NUMBER}-${GERRIT_PATCHSET_NUMBER}"
        git fetch origin ${GERRIT_REFSPEC}:${changeBranch}
        git checkout $changeBranch
    elif [ -n "$GIT_PREVIOUS_COMMIT" ]; then
        set -- $GIT_PREVIOUS_COMMIT $GIT_COMMIT
    else
        set -- HEAD
    fi
fi
git diff --name-only "$@"
