FROM ubuntu:xenial

RUN apt-get update && apt-get install git -y
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
RUN echo "deb http://download.mono-project.com/repo/debian wheezy main" | tee /etc/apt/sources.list.d/mono-xamarin.list
RUN echo "deb http://download.mono-project.com/repo/debian wheezy-apache24-compat main" |  tee -a /etc/apt/sources.list.d/mono-xamarin.list
RUN echo "deb http://download.mono-project.com/repo/debian wheezy-libjpeg62-compat main" |  tee -a /etc/apt/sources.list.d/mono-xamarin.list
RUN apt-get update
RUN apt-get install ca-certificates-mono -y
RUN apt-get install mono-devel mono-complete referenceassemblies-pcl mono-xsp4 -y
#RUN apt-get install mono-devel mono-complete mono-xsp4 -y
#RUN apt-get install mono-devel ca-certificates-mono mono-xsp4 -y

RUN mono --version
RUN cert-sync /etc/ssl/certs/ca-certificates.crt

RUN git clone --recursive https://github.com/scriptcs/scriptcs
RUN cd ./scriptcs	 && ./build_brew.sh
ENTRYPOINT ["/scriptcs/artifacts/Release/bin/scriptcs"]
