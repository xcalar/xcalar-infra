# customer PoC

These parameters were used to deploy 3 node XDP clusters on Azure.

```
    $ cd $XLRINFRADIR/azure
    $ INSTALLER=/netstore/builds/ReleaseCandidates/xcalar-2.0.1-RC10/prod/xcalar-2.0.1-3198-installer-el7
    $ RG=abakshi-test-rg
    $ PARAMS=`pwd`/devTestLabs/gspoc/parameters.json
    $ VMCOUNT=3

    $ ./azure-cluster.sh -i $INSTALLER -n $RG -c $VMCOUNT -p $PARAMS
    Succeeded  0e0057a9-08da-4094-8ecf-ddaa728ff1bc
    + for op in validate create
    + deploy_name=
    + '[' create = create ']'
    + deploy_name='--name abakshi-test-rg-deploy'
    + az group deployment create --resource-group abakshi-test-rg --name abakshi-test-rg-deploy --template-file /home/abakshi/xcalar-infra/azure/xdp-standard/devTemplate.json --parameters @devTestLabs/gspoc/parameters.json installerUrl=https://xcrepo.blob.core.windows.net/builds/prod/xcalar-2.0.1-3198-installer-el7 'installerUrlSasToken=?se=2019-09-06T14%3A38Z&sp=r&sv=2018-11-09&sr=b&sig=3Vwf3MOJpZCaseixO2q%2Bx4uLoX2WmZ1wu7H0HDwxJnk%3D' domainNameLabel=abakshi-test-rg customScriptName=devBootstrap.sh bootstrapUrl=https://s3-us-west-2.amazonaws.com/xcrepo/bysha1/941a4796523610dd0e4f5093a42354a8bde19e65/devBootstrap.sh adminEmail=abakshi@xcalar.com scaleNumber=3 appName=abakshi-test-rg vmSize=Standard_E8s_v3

```

