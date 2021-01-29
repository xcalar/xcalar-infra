## Start at "START HERE"

To publish something as a internal package for deployment,
1) Change kind to ServiceCatalog in mainTemplate.json and run

```
    make
    url=`../../bin/installer-url.sh -d s3 ./xdp-standard-package.zip | grep https`
    az managedapp definition create -n xcalarAppDef -l "westcentralus" --resource-group "blim-xcalar" --lock-level None --display-name "Xcalar Data Platform" --description "For internal deployment only" --authorizations "a015a485-ab1c-4e03-b275-3505e2b12249:8e3af657-a8ff-443c-a75c-2fe8c4bcb635" --package-file-uri "$url" --debug
```


To publish this into Azure marketplace,
1) Delete applianceDefinitionId from mainTemplate.json
2) Change kind to "marketplace"


## deployFromAzureMP.sh

- Verify your license: ./check-license.sh 'YOURLICENSE' NUM_NODES
- This same license should've been part of the data you pasted into parameters.main.json
- Now run create your resource group in the same location as you specified during template deployment ui
```
  export GROUP=mygroup-1
  export LOCATION=westus2

  az group create -n $GROUP -l $LOCATION
```
- If that succeeds, run deployFromAzureMP.sh
```
  ./deployFromAzureMP.sh -g $GROUP
```
It'll take a while ~10min or so. If you did this on a local Linux machine, it'll open up chrome to your GROUP. If not, it'll
out the URL.

- Now run get your IP address. Use the gui or cli:
```
  az vm list-ip-addresses -g $GROUP -otable

  VirtualMachine    PublicIPAddresses    PrivateIPAddresses
  ----------------  -------------------  --------------------
  xdp-standard-vm0  52.247.205.127       10.0.0.4
  xdp-standard-vm1                       10.0.0.5
  xdp-standard-vm2                       10.0.0.6

```

- And finally

```
  ssh youruser@PublicIpFromAbove
```

You should also be able to browse to the domainNameLabel you specified during template creation (yourdnsname.westus2.cloudapp.azure.com)

If you wish to redeploy the same template, you'll need to specify a new domainNameLabel. Either in the json, or append a
parameter to ./deployFromAzureMP.sh -g $GROUP -- --parameters domainNameLabel=myotherunusedname-1


### 11/22/2017 UPDATE

More information on the [Azure wiki](http://wiki.int.xcalar.com/mediawiki/index.php/Azure#Default_SSH_Access)

The new template supoprts ssh key auth by default. Copy /netstore/infra/azure/id_azure to ~/.ssh and add to your agent:

```
 mkdir -m 0700 -p ~/.ssh
 chmod 0700 ~/.ssh
 cp /netstore/infra/azure/id_azure ~/.ssh
 chmod 0600 ~/.ssh/id_azure
 ssh-add ~/.ssh/id_azure
```

If you get an error from ssh-add, you need to run the ssh-agent:

```
 eval $(ssh-agent)
 # OR
 ssh-agent bash
```

Add the following to your ~/.ssh/config

```
 Host *.cloudapp.azure.com
    User azureuser
    Port 22
    ForwardAgent            yes
    PubKeyAuthentication    yes
    PasswordAuthentication  no
    UserKnownHostsFile      /dev/null
    StrictHostKeyChecking   no
    IdentityFile ~/.ssh/id_azure
```

Make sure to `chmod 0600 ~/.ssh/config` or SSH will refuse to parse it.

Now you can ssh into the head node (vm0). From there you can ssh into all the other nodes, because SSH Agent
forwarding is enabled. All the nodes have aliases set up that are named `vm<NODE_ID>`. This means you can
`ssh vm1`, `ssh vm2`, etc.

```
 ssh abakshi-103-cluster.westus2.cloudapp.azure.com
 Last login: Sun Dec  3 19:17:26 2017 from xcalar-186.tisch.gvad.net

 [azureuser@abakshi-103-cluster-vm0 ~]$ ssh -A vm1
 Last login: Sun Dec  3 19:18:43 2017 from 10.0.0.4

 [azureuser@abakshi-103-cluster-vm1 ~]$ ssh -A vm2
 Last login: Sun Dec  3 19:14:40 2017 from 10.0.0.4
```
az role definition list --name Owner --query [].name --output tsv
az ad group show --group ManagedAppAdmin --query objectId --output tsv
