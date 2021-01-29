## Running playbooks

0. Run `make` in the root directory of this project, `XLRINFRADIR`. Make
sure that `XLRINFRADIR` is set to where the project is location in your
~/.bashrc, and add `$XLRINFRADIR/bin` to your `PATH`.

```
export XLRINFRADIR=$HOME/xcalar-infra
export PATH=$XLRINFRADIR/bin:$PATH

source $XLRINFRADIR/azure/azure-sh-lib

```

If you're not using Xcalar Python Virtualenv from `XLRDIR`, add
```
. ~/.local/lib/xcalar-infra/bin/activate
```
To your `~/.bashrc`, after running `make`.


1. Add a section in `inventory/hosts` with the group name of the new resource group. This
section should list out the hosts you wish to modify. For example, we have group
`trial-jyen-rg-01` with a VM we wish to apply ansible to (change `ansible_user` and `ansible_*_pass`
variables.

```
[trial-jyen-rg-01]
trial-jyen-01-vm0.westus2.cloudapp.azure.com     ansible_user=jyen  ansible_ssh_pass=b3JmJfdb  ansible_become_pass=b3JmJfdb
```

2. Add the group to the parent group `trial`. We use this mainly as a sanity
check by limiting what playbooks you can run against a group.

```
[trial:children]
someOtherGroups
trial-jyen-rg-01
```

3. Find an unused DNS name.  Use the `host` command to check

```
host xdp-preview-105.xcalar.io
xdp-preview-105.xcalar.io is an alias for trial-element22-01.westus2.cloudapp.azure.com.
trial-element22-01.westus2.cloudapp.azure.com has address 52.183.27.27
```

That one's taken by trial-element22...


```
host xdp-preview-106.xcalar.io
xdp-preview-106.xcalar.io has address 130.211.225.110
```

Returns 130.211.255.110, which is a 'catch all' IP we have registered all all xcalar.io names
that aren't pointing somewhere specific


4. Add details of your change to `group_vars/groupname` For example, you'll need
to provide the sudo password and the desired DNS name.  Create the group vars file
with the username, password, the CNAME given by the cloud provider, and your desired name

```
# group_vars/trial-jyen-rg-01
given_name: trial-jyen-01-vm0.westus2.cloudapp.azure.com
desired_name: xdp-preview-106.xcalar.io.
```

5. That's it! Run with `--check` once just to sanity check, add `-l $GROUP` to limit the
actions to your group and pass in what playbook to apply. Enter the ssh password once,
and press enter the second time.


```
$ ./run.sh --check -l trial-jyen-rg-01 trial.yml

SSH password:
SUDO password[defaults to SSH password]:

PLAY [trial] *****************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************

TASK [Gathering Facts] *******************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************
ok: [trial-jyen-01.westus2.cloudapp.azure.com]

TASK [caddy : Copy certs] ****************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************
changed: [trial-jyen-01.westus2.cloudapp.azure.com] => (item=cert.pem)
changed: [trial-jyen-01.westus2.cloudapp.azure.com] => (item=cert.key)

TASK [caddy : Configure Caddyfile] *******************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************
changed: [trial-jyen-01.westus2.cloudapp.azure.com]

TASK [dns : Generating Route53 request for xdp-preview-106.xcalar.io. to point to trial-jyen-01.westus2.cloudapp.azure.com] **************************************************************************************************************************************************************************************************************************************************************************************************************
skipping: [trial-jyen-01.westus2.cloudapp.azure.com]

TASK [dns : Configure Route53] ***********************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************
skipping: [trial-jyen-01.westus2.cloudapp.azure.com]

RUNNING HANDLER [caddy : restart-caddy] **************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************
skipping: [trial-jyen-01.westus2.cloudapp.azure.com]

PLAY RECAP *******************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************
trial-jyen-01.westus2.cloudapp.azure.com : ok=3    changed=2    unreachable=0    failed=0

```


6. If that worked, run again without `--check`

## TIPs

- If something fails, rerun and add `-vvv`
