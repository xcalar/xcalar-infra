SHELL=/bin/bash

trusted-user-ca.pem:
	vault read -field=public_key ssh/config/ca > $@

vault-ssh-admin:
	cat vault-role-admin.json | vault write ssh/roles/admin -
	cat vault-role-jenkins.json | vault write ssh/roles/jenkins -
	cat vault-role-cloud.json | vault write ssh/roles/cloud -



