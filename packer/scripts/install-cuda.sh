#!/bin/bash
set -ex

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
if [ $(id -u) != 0 ]; then
	echo >&2 "ERROR: Must run as root"
	exit 3
fi

CUDA_VERSION=${CUDA_VERSION:-10.0}
BASE_URL="${BASE_URL:-https://storage.googleapis.com/repo.xcalar.net/deps/nvidia}"
case "$CUDA_VERSION" in
    10.0)
        CUDA_COMPONENTS="${CUDA_COMPONENTS:-NVIDIA-Linux-x86_64-455.23.05.run cuda_10.0.130_410.48_linux.run cudnn-10.0-linux-x64-v7.6.5.32.tgz}"
        PYTHON_PKGS="${PYTHON_PKGS:-tensorflow-gpu==1.13.1 pandas==0.22 keras==2.4.3}"
        ;;
    10.1)
        CUDA_COMPONENTS="${CUDA_COMPONENTS:-NVIDIA-Linux-x86_64-455.23.05.run cuda_10.1.243_418.87.00_linux.run cudnn-10.0-linux-x64-v7.6.5.32.tgz}"
        PYTHON_PKGS="${PYTHON_PKGS:-tensorflow-gpu==1.13.1 pandas==0.22 keras==2.4.3}"
        ;;
    11.1)
        CUDA_COMPONENTS="${CUDA_COMPONENTS:-NVIDIA-Linux-x86_64-455.23.05.run cuda_11.1.0_455.23.05_linux.run cudnn-10.0-linux-x64-v7.6.5.32.tgz}"
        PYTHON_PKGS="${PYTHON_PKGS:-tensorflow>=2.0 pandas==0.22 keras==2.4.3}"
        ;;
    *) echo >&2 "ERROR: Don't know how to install CUDA $CUDA_VERSION";;
esac


## Install cuda deps
TMP=$(mktemp -d -t cuda.XXXXXX)
cd "$TMP"

for ii in $CUDA_COMPONENTS; do
	curl -f -L -O "${BASE_URL}/${ii}"
	case "$ii" in
        NVIDIA*.run)
			yum install -y dkms kernel-devel
            bash "$ii" --accept-license --no-questions  --silent
            ;;
		cuda_*.run)
			yum install -y dkms kernel-devel
			bash "$ii" --silent --toolkit
			BN=$(basename $(readlink -f /usr/local/cuda) | sed 's/\./-/g')
            test -e /etc/ld.so.conf.d/${BN}.conf || echo "$(readlink -f /usr/local/cuda/lib64)" > /etc/ld.so.conf.d/${BN}.conf
			ldconfig
			;;
		cudnn*.tgz)
			tar zxf "$ii" --strip-components=1 -C /usr/local/cuda/
			ldconfig
			;;
	esac
done
cd -
rm -rf "$TMP"

cp $DIR/nvidia-check.sh /usr/local/bin/nvidia-check.sh
cp $DIR/nvidia-check.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable nvidia-check.service

chmod +x /usr/local/bin/nvidia-check.sh
set +e
/usr/local/bin/nvidia-check.sh
set -e
## Install new packages
/opt/xcalar/bin/python3 -m pip install --no-cache-dir -U pip
/opt/xcalar/bin/python3 -m pip install --no-cache-dir $PYTHON_PKGS \
	-c <(sed '/tensorflow/d; /pandas/d' /opt/xcalar/share/doc/xcalar-python3*/requirements.txt)
