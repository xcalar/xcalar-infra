#!/bin/bash

# Instance meta-data service v2
imds() {
    if [ -z "$IMDSV2_TOKEN" ]; then
        IMDSV2_TOKEN=$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    fi
    curl -fsS -H "X-aws-metadata-token: $IMDSV2_TOKEN" "http://169.254.169.254/latest/${1#/}"
}

aws_verify() {
       DOCUMENT=inst.json
       AWS=aws.pem
       SIGNATURE=sig.json
       PKCS7=pkcs7.pem

       (echo "-----BEGIN PKCS7-----"; imds /dynamic/instance-identity/pkcs7 ; echo; echo "-----END PKCS7-----") > $PKCS7 \
       && imds /dynamic/instance-identity/signature > $SIGNATURE \
       && imds /dynamic/instance-identity/document > $DOCUMENT \
       || return 3
	cat <<-EOF > $AWS
	-----BEGIN CERTIFICATE-----
	MIIC7TCCAq0CCQCWukjZ5V4aZzAJBgcqhkjOOAQDMFwxCzAJBgNVBAYTAlVTMRkw
	FwYDVQQIExBXYXNoaW5ndG9uIFN0YXRlMRAwDgYDVQQHEwdTZWF0dGxlMSAwHgYD
	VQQKExdBbWF6b24gV2ViIFNlcnZpY2VzIExMQzAeFw0xMjAxMDUxMjU2MTJaFw0z
	ODAxMDUxMjU2MTJaMFwxCzAJBgNVBAYTAlVTMRkwFwYDVQQIExBXYXNoaW5ndG9u
	IFN0YXRlMRAwDgYDVQQHEwdTZWF0dGxlMSAwHgYDVQQKExdBbWF6b24gV2ViIFNl
	cnZpY2VzIExMQzCCAbcwggEsBgcqhkjOOAQBMIIBHwKBgQCjkvcS2bb1VQ4yt/5e
	ih5OO6kK/n1Lzllr7D8ZwtQP8fOEpp5E2ng+D6Ud1Z1gYipr58Kj3nssSNpI6bX3
	VyIQzK7wLclnd/YozqNNmgIyZecN7EglK9ITHJLP+x8FtUpt3QbyYXJdmVMegN6P
	hviYt5JH/nYl4hh3Pa1HJdskgQIVALVJ3ER11+Ko4tP6nwvHwh6+ERYRAoGBAI1j
	k+tkqMVHuAFcvAGKocTgsjJem6/5qomzJuKDmbJNu9Qxw3rAotXau8Qe+MBcJl/U
	hhy1KHVpCGl9fueQ2s6IL0CaO/buycU1CiYQk40KNHCcHfNiZbdlx1E9rpUp7bnF
	lRa2v1ntMX3caRVDdbtPEWmdxSCYsYFDk4mZrOLBA4GEAAKBgEbmeve5f8LIE/Gf
	MNmP9CM5eovQOGx5ho8WqD+aTebs+k2tn92BBPqeZqpWRa5P/+jrdKml1qx4llHW
	MXrs3IgIb6+hUIB+S8dz8/mmO0bpr76RoZVCXYab2CZedFut7qc3WUH9+EUAH5mw
	vSeDCOUMYQR7R9LINYwouHIziqQYMAkGByqGSM44BAMDLwAwLAIUWXBlk40xTwSw
	7HX32MxXYruse9ACFBNGmdX2ZBrVNGrN9N2f6ROk0k9K
	-----END CERTIFICATE-----
	EOF
        openssl smime -verify -in $PKCS7 -inform PEM -content $DOCUMENT -certfile $AWS -noverify
}

export TMPDIR=$(mktemp -d /tmp/ec2-cert.XXXXXX)
chmod 0700 "$TMPDIR"
cd $TMPDIR
if aws_verify; then
        cd / && rm -rf $TMPDIR
        exit 0
fi
echo >&2 "All intermediate files are in TMPDIR=$TMPDIR"
exit 1
