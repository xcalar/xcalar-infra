#!/bin/bash
set -e

install_java8() {
    if command -v apt-get >/dev/null; then
        apt-get update
        apt-get purge -y openjdk-7-jdk || true
        apt-get install -y openjdk-8-jdk
        export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
    else
        unset JAVA_HOME
        yum remove -y java-1.7.0-openjdk-headless java-1.7.0-openjdk || true
        yum install -y java-1.8.0-openjdk-devel || true
        for dir in /usr/lib/jvm/java-1.8.0-openjdk /usr/lib/jvm/java-1.8.0 /usr/lib/jvm/java-1.8.0-openjdk.x86_64 /usr/lib/jvm/java-1.8.0-amazon-corretto.x86_64/{,jre} /usr/java/latest; do
            if test -e "$dir/bin/java"; then
                export JAVA_HOME=$dir
                break
            fi
        done
    fi

    if [ -n "$JAVA_HOME" ]; then
    cat > /etc/profile.d/zjava.sh <<EOF
export JAVA_HOME=$JAVA_HOME
export PATH="\$PATH:\$JAVA_HOME/bin"
EOF
    fi
}

install_java8
