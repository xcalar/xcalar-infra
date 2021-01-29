let ignoreList = [
    "license-text",
    "LambdaRole",
    "LicenseKey"
]

//fake data for testing , if Unit Testing is on , this data is shown in ui
let clusterData = {
    sortField: "clusterName",
    sortDirecton: "dec",
    selectedAll: false,
    clusters: [{
            fields: {
                "clusterName": "Xcalar-1", // Name of the Xcalar cluster
                "status": "Running", // Status string (Running, Stopped, Provisioning)
                "nodes": 4, // Number of nodes in cluster ,  
                "mode": "Mixed", // Xcalar Mode (Mixed, Modal, Open)
                "version": "1.4.1", // Xcalar Version
                "xem": "N/A", // N/A yet
                "xd": "192.168.2.1", // Link to XD , it is usually IP of node0                    
                "other": "", // Reserved                    
                "uptime": 345560, //uptime in seconds
                'Nodes': [
                    "192.162.2.1",
                    "192.162.2.2",
                    "192.162.2.3",
                    "192.162.2.4"
                ],
                "InstallerUrl": "N/A",
                "XcalarRoot": "N/A"
            }
        },
        {
            fields: {
                "clusterName": "Xcalar-2", // Name of the Xcalar cluster                    
                "status": "Running",
                "nodes": 2,
                "mode": "Op",
                "version": "1.4.1",
                "xem": "N/A",
                "xd": "192.168.2.5",
                "other": "", // Reserved 
                "uptime": 345560, //uptime in seconds
                'Nodes': [
                    "192.162.2.1",
                    "192.162.2.2"

                ],
                "InstallerUrl": "N/A",
                "XcalarRoot": "N/A"
            }
        },
        {
            fields: {
                "clusterName": "Xcalar-3", // Name of the Xcalar cluster
                "status": "Stopped",
                "nodes": 4,
                "mode": "Mixed",
                "version": "1.4.1",
                "xem": "N/A",
                "xd": "192.168.2.1",
                "other": "", // Reserved 
                "uptime": 345560, //uptime in seconds
                'Nodes': [
                    "192.162.2.1",
                    "192.162.2.2",
                    "192.162.2.3",
                    "192.162.2.4"
                ],
                "InstallerUrl": "N/A",
                "XcalarRoot": "N/A"
            }
        },
        {
            fields: {
                "clusterName": "Xcalar-4", // Name of the Xcalar cluster
                "status": "Provisioning",
                "nodes": 4,
                "mode": "Mixed",
                "version": "1.4.1",
                "xem": "N/A",
                "xd": "192.168.2.1",
                "other": "", // Reserved 
                "uptime": 345560, //uptime in seconds
                'Nodes': [
                    "192.162.2.1",
                    "192.162.2.2",
                    "192.162.2.3",
                    "192.162.2.4"
                ],
                "InstallerUrl": "N/A",
                "XcalarRoot": "N/A"
            }
        }
    ]
}

/*Hintbox data for settings , setting name is extracted from ui and hashed here to get actual help data */
let helpData = {
    "InstallerUrl": "XCE Installer",
    "AdminEmail": "Email of the administrator",
    "AdminUsername": "XD Administrator name used to log into the GUI",
    "AdminPassword": "XD Administrator password",
    "BootstrapUrl": "XCE Bootstrap Script",
    "InstanceType": "XCE EC2 instance type",
    "RootSize": "Size of root disk",
    "SwapSize": "Size of swap disk. NOTE: This should be at least 2x the amount of memory.",
    "ImageId": "ID of an existing Amazon Machine Image (AMI)",
    "ELRelease": "Enterprise Linux Distro. RHEL7 is RedHat Enterprise Linux 7.4, EL7 is CentOS 7.4",
    "KeyName": "Name of an existing EC2 KeyPair to enable SSH access to the instance",
    "SSHLocation": " The IP address range that can be used to SSH to the EC2 instances",
    "HTTPLocation": " The IP address range to allow HTTP access from",
    "VpcId": "VpcId of your existing Virtual Private Cloud (VPC)",
    "Subnet": "The SubnetId in your Virtual Private Cloud (VPC)",
    "AvZone": "An Availability Zone, such as us-west-2a.",
    "SGList": "A list of existing security groups.",
    "roleARN": "arn role to create clusters"
}