#!/bin/bash
DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
TARGET="${1:?Need to specify target directory}"

mkdir -p "${TARGET}"
reposync -c yum.conf --newest-only --gpgcheck --plugins --downloadcomps --download-metadata --download_path=${TARGET}
COMPS=($(ls ${TARGET}/*/comps.xml))
createrepo ${COMPS[@]/rhel-/-g rhel-} --verbose --workers=`nproc` --update --pretty ${TARGET}
