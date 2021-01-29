Docker KDC
==========

    $ docker build -t $USER/kdc .
    $ docker run -d -p 88:88 -p 88/udp:88/udp --name kdc $USER/kdc


Creates and runs a Kerberos5 KDC in a Centos6 base image.
Default user/pass: cloudera/cloudera.
