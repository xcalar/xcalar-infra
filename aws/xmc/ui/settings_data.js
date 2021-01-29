//Put cloudformation template here
settings_data=
{
    "AWSTemplateFormatVersion": "2010-09-09",
    "Description": "XCE AWS CloudFormation Template -  **WARNING** This template creates a cluster of Amazon EC2 instances. You will be billed for the AWS resources used if you create a stack from this template.",
    "Parameters": {
        "VpcId": {
            "Type": "AWS::EC2::VPC::Id",
            "Description": "VpcId of your existing Virtual Private Cloud (VPC)",
            "ConstraintDescription": "must be the VPC Id of an existing Virtual Private Cloud.",
            "Default": "vpc-22f26347"
        },
        "Subnet": {
            "Type": "AWS::EC2::Subnet::Id",
            "Description": "The SubnetId in your Virtual Private Cloud (VPC)",
            "ConstraintDescription": "must be a list of at least two existing subnets associated with at least two different availability zones. They should be residing in the selected Virtual Private Cloud.",
            "Default": "subnet-b9ed4ee0"
        },
        "AvZone": {
            "Type": "AWS::EC2::AvailabilityZone::Name",
            "Description": "An Availability Zone, such as us-west-2a.",
            "ConstraintDescription": "Must be a valid availabiliy zone",
            "Default": "us-west-2c"
        },
        "SGList": {
            "Type": "List<AWS::EC2::SecurityGroup::GroupName>",
            "Description": "A list of existing security groups.",
            "Default": "default,open-to-users-at-home,open-to-office"
        },
        "KeyName": {
            "Description": "Name of an existing EC2 KeyPair to enable SSH access to the instance",
            "Type": "AWS::EC2::KeyPair::KeyName",
            "ConstraintDescription": "must be the name of an existing EC2 KeyPair.",
            "Default": "xcalar-us-west-2"
        },
        "InstallerUrl": {
            "Description": "XCE Installer",
            "Type": "String",
            "MinLength": "4",
            "MaxLength": "2047",
            "AllowedPattern": "http[s]?://.*",
            "ConstraintDescription": "Must be a valid url.",
            "Default": "https://s3.us-west-2.amazonaws.com/xcrepo/builds/prod/xcalar-1.4.0-1882-installer?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAJU4DLXF3P2I7WGCQ%2F20180606%2Fus-west-2%2Fs3%2Faws4_request&X-Amz-Date=20180606T201342Z&X-Amz-Expires=604200&X-Amz-SignedHeaders=host&X-Amz-Signature=1c7688b3de9457f92b30eff9dccefa094de3388cdd86b618eebd48e342049558"
        },
        "BootstrapUrl": {
            "Description": "XCE Bootstrap Script",
            "Type": "String",
            "MinLength": "8",
            "MaxLength": "2047",
            "AllowedPattern": "http[s]?://.*",
            "ConstraintDescription": "Must be a valid url.",
            "Default": "http://repo.xcalar.net/scripts/aws-asg-bootstrap-v6.sh"
        },
        "LicenseKey": {
            "Description": "XCE License",
            "Type": "String",
            "MinLength": "0",
            "MaxLength": "1024"
        },
        "AdminUsername": {
            "Description": "XD Administrator name used to log into the GUI",
            "Type": "String",
            "MinLength": "5",
            "MaxLength": "128"
        },
        "AdminPassword": {
            "Description": "XD Administrator password",
            "NoEcho": true,
            "Type": "String",
            "MinLength": "5",
            "MaxLength": "128"
        },
        "AdminEmail": {
            "Description": "Email of the administrator",
            "Type": "String"
        },
        "InstanceType": {
            "Description": "XCE EC2 instance type",
            "Type": "String",
            "Default": "m5.2xlarge",
            "AllowedValues": [
                "m5.xlarge",
                "m5.2xlarge",
                "m5.4xlarge",
                "m5.12xlarge",
                "m5.24xlarge",
                "c5.2xlarge",
                "c5.4xlarge",
                "c5.9xlarge",
                "c5.18xlarge",
                "r4.2xlarge",
                "r4.4xlarge",
                "r4.8xlarge",
                "r4.16xlarge",
                "i3.large",
                "i3.xlarge",
                "i3.2xlarge",
                "i3.4xlarge",
                "i3.8xlarge",
                "i3.16xlarge",
                "m5d.xlarge",
                "m5d.2xlarge",
                "m5d.4xlarge",
                "m5d.12xlarge",
                "m5d.24xlarge",
                "c5d.2xlarge",
                "c5d.4xlarge",
                "c5d.9xlarge",
                "c5d.18xlarge",
                "x1.16xlarge",
                "x1.32xlarge"
            ],
            "ConstraintDescription": "must be a valid EC2 instance type."
        },
        "ELRelease": {
            "Description": "Enterprise Linux Distro. RHEL7 is RedHat Enterprise Linux 7.4, EL7 is CentOS 7.4",
            "Type": "String",
            "Default": "EL7",
            "AllowedValues": [
                "RHEL7",
                "EL7"
            ]
        },
        "SSHLocation": {
            "Description": " The IP address range that can be used to SSH to the EC2 instances",
            "Type": "String",
            "MinLength": "9",
            "MaxLength": "18",
            "Default": "0.0.0.0/0",
            "AllowedPattern": "(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})/(\\d{1,2})",
            "ConstraintDescription": "must be a valid IP CIDR range of the form x.x.x.x/x."
        },
        "HTTPLocation": {
            "Description": " The IP address range to allow HTTP access from",
            "Type": "String",
            "MinLength": "9",
            "MaxLength": "18",
            "Default": "0.0.0.0/0",
            "AllowedPattern": "(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})/(\\d{1,2})",
            "ConstraintDescription": "must be a valid IP CIDR range of the form x.x.x.x/x."
        },
        "InstanceCount": {
            "Description": "Number of EC2 instances to launch",
            "Type": "Number",
            "Default": "1"
        },
        "RootSize": {
            "Description": "Size of root disk",
            "Type": "Number",
            "Default": "64"
        },
        "SwapSize": {
            "Description": "Size of swap disk. NOTE: This should be at least 2x the amount of memory.",
            "Type": "Number",
            "Default": "64"
        }
    },
    "Mappings": {
        "RegionMap": {
            "us-east-1": {
                "RHEL7": "ami-6871a115",
                "EL7": "ami-0f80d62666b176446",
                "AmazonLinux": "ami-14c5486b"
            },
            "us-west-2": {
                "RHEL7": "ami-28e07e50",
                "EL7": "ami-02ff71c14348cdca4",
                "AmazonLinux": "ami-e251209a"
            }
        }
    },
    "Metadata": {
        "AWS::CloudFormation::Interface": {
            "ParameterGroups": [
                {
                    "Label": {
                        "default": "Xcalar Configuration"
                    },
                    "Parameters": [
                        "LicenseKey",
                        "InstallerUrl",
                        "AdminEmail",
                        "AdminUsername",
                        "AdminPassword",
                        "BootstrapUrl"
                    ]
                },
                {
                    "Label": {
                        "default": "Instance configuration"
                    },
                    "Parameters": [
                        "InstanceType",
                        "InstanceCount",
                        "RootSize",
                        "SwapSize",
                        "ELRelease"
                    ]
                },
                {
                    "Label": {
                        "default": "Security configuration"
                    },
                    "Parameters": [
                        "KeyName",
                        "SSHLocation",
                        "HTTPLocation"
                    ]
                },
                {
                    "Label": {
                        "default": "Network configuration"
                    },
                    "Parameters": [
                        "VpcId",
                        "Subnet",
                        "AvZone",
                        "SGList"
                    ]
                }
            ],
            "ParameterLabels": {
                "InstallerUrl": {
                    "default": "XCE Installer Url:"
                },
                "LicenseKey": {
                    "default": "XCE License Key:"
                },
                "InstanceType": {
                    "default": "Server size:"
                },
                "KeyName": {
                    "default": "Key pair:"
                },
                "SSHLocation": {
                    "default": "SSH CIDR range:"
                },
                "HTTPLocation": {
                    "default": "HTTP CIDR range:"
                },
                "AvZone": {
                    "default": "Availability Zone:"
                },
                "BootstrapUrl": {
                    "default": "Bootstrap Url:"
                },
                "InstanceCount": {
                    "default": "Cluster size:"
                }
            }
        }
    },
    "Resources": {
        "SGDefault": {
            "Type": "AWS::EC2::SecurityGroup",
            "Properties": {
                "GroupDescription": "SSH",
                "VpcId": {
                    "Ref": "VpcId"
                },
                "SecurityGroupIngress": [
                    {
                        "CidrIp": {
                            "Ref": "SSHLocation"
                        },
                        "IpProtocol": "tcp",
                        "FromPort": "22",
                        "ToPort": "22"
                    },
                    {
                        "CidrIp": {
                            "Ref": "HTTPLocation"
                        },
                        "IpProtocol": "tcp",
                        "FromPort": "443",
                        "ToPort": "443"
                    },
                    {
                        "CidrIp": {
                            "Ref": "HTTPLocation"
                        },
                        "IpProtocol": "tcp",
                        "FromPort": "80",
                        "ToPort": "80"
                    }
                ]
            }
        },
        "InstanceProfile": {
            "Type": "AWS::IAM::InstanceProfile",
            "Properties": {
                "Roles": [
                    {
                        "Ref": "Role"
                    }
                ]
            }
        },
        "Role": {
            "Type": "AWS::IAM::Role",
            "Properties": {
                "AssumeRolePolicyDocument": {
                    "Version": "2012-10-17",
                    "Statement": [
                        {
                            "Effect": "Allow",
                            "Principal": {
                                "Service": "ec2.amazonaws.com"
                            },
                            "Action": "sts:AssumeRole"
                        }
                    ]
                },
                "Path": "/",
                "Policies": [
                    {
                        "PolicyName": "Ec2Describe",
                        "PolicyDocument": {
                            "Version": "2012-10-17",
                            "Statement": [
                                {
                                    "Effect": "Allow",
                                    "Action": [
                                        "ec2:DescribeInstances",
                                        "ec2:DescribeTags",
                                        "autoscaling:DescribeAutoScalingGroups"
                                    ],
                                    "Resource": "*"
                                }
                            ]
                        }
                    }
                ]
            }
        },
        "PlacementGroup": {
            "Type": "AWS::EC2::PlacementGroup",
            "Properties": {
                "Strategy": "cluster"
            }
        },
        "InstanceGroup": {
            "Type": "AWS::AutoScaling::AutoScalingGroup",
            "Properties": {
                "PlacementGroup": {
                    "Ref": "PlacementGroup"
                },
                "AvailabilityZones": [
                    {
                        "Ref": "AvZone"
                    }
                ],
                "LaunchConfigurationName": {
                    "Ref": "LaunchConfig"
                },
                "MinSize": {
                    "Ref": "InstanceCount"
                },
                "MaxSize": {
                    "Ref": "InstanceCount"
                },
                "DesiredCapacity": {
                    "Ref": "InstanceCount"
                }
            },
            "CreationPolicy": {
                "ResourceSignal": {
                    "Timeout": "PT15M",
                    "Count": {
                        "Ref": "InstanceCount"
                    }
                }
            }
        },
        "LaunchConfig": {
            "Type": "AWS::AutoScaling::LaunchConfiguration",
            "Properties": {
                "ImageId": {
                    "Fn::FindInMap": [
                        "RegionMap",
                        {
                            "Ref": "AWS::Region"
                        },
                        {
                            "Ref": "ELRelease"
                        }
                    ]
                },
                "BlockDeviceMappings": [
                    {
                        "DeviceName": "/dev/sda1",
                        "Ebs": {
                            "VolumeSize": {
                                "Ref": "RootSize"
                            },
                            "VolumeType": "gp2",
                            "DeleteOnTermination": true
                        }
                    },
                    {
                        "DeviceName": "/dev/sdm",
                        "Ebs": {
                            "VolumeSize": {
                                "Ref": "SwapSize"
                            },
                            "VolumeType": "gp2",
                            "DeleteOnTermination": true
                        }
                    },
                    {
                        "DeviceName": "/dev/sdb",
                        "VirtualName": "ephemeral0"
                    },
                    {
                        "DeviceName": "/dev/sdc",
                        "VirtualName": "ephemeral1"
                    },
                    {
                        "DeviceName": "/dev/sdd",
                        "VirtualName": "ephemeral2"
                    },
                    {
                        "DeviceName": "/dev/sde",
                        "VirtualName": "ephemeral3"
                    }
                ],
                "IamInstanceProfile": {
                    "Ref": "InstanceProfile"
                },
                "InstanceType": {
                    "Ref": "InstanceType"
                },
                "SecurityGroups": {
                    "Ref": "SGList"
                },
                "KeyName": {
                    "Ref": "KeyName"
                },
                "EbsOptimized": true,
                "UserData": {
                    "Fn::Base64": {
                        "Fn::Sub": "#!/bin/bash -x\nset -x\nset +e\nsafe_curl() { curl -4 --location --retry 20 --retry-delay 3 --retry-max-time 60 \"$@\"; }\nyum install -y epel-release\nyum install -y jq nfs-utils curl\nRELEASE_RPM=$(rpm -qf /etc/redhat-release)\nRELEASE=$(rpm -q --qf %{VERSION} $RELEASE_RPM)\nELVERSION=\"$(echo $RELEASE | sed -e 's/Server//g')\"\nif ! test -e /opt/aws/bin/cfn-init; then\n  yum install -y awscli\n  rpm -q aws-cfn-bootstrap || yum localinstall -y http://repo.xcalar.net/deps/aws-cfn-bootstrap-1.4-18.el$ELVERSION.noarch.rpm\nfi\nexport PATH=\"$PATH:/opt/aws/bin\"\n# Install the files and packages from the metadata\n/opt/aws/bin/cfn-init -v --stack ${AWS::StackName} --resource InstanceGroup --region ${AWS::Region}\ntry=20\nsafe_curl -L https://storage.googleapis.com/repo.xcalar.net/deps/discover-1.gz | gzip -dc > /usr/local/bin/discover\nchmod +x /usr/local/bin/discover\nfor try in {0..20}; do\n  echo >&2 \"Waiting to get IPs ..\"\n  sleep 10\n  IPS=($(set -o pipefail; discover addrs provider=aws addr_type=private_v4 \"tag_key=aws:cloudformation:stack-id\" \"tag_value=${AWS::StackId}\" | tee IPS.txt )) && break\ndone\nmkdir -p /etc/xcalar\ntest -n \"${LicenseKey}\" && echo \"${LicenseKey}\" | base64 -d | gzip -dc > /etc/xcalar/XcalarLic.key\nif [ $? -ne 0 ]; then\n    test -n \"${LicenseKey}\" && echo \"${LicenseKey}\" > /etc/xcalar/XcalarLic.key\nfi\nsafe_curl -fL \"${BootstrapUrl}\" -o /usr/local/bin/aws-asg-bootstrap.sh && \\\nchmod +x /usr/local/bin/aws-asg-bootstrap.sh && \\\n/bin/bash -x /usr/local/bin/aws-asg-bootstrap.sh ${InstanceCount} \"${InstallerUrl}\" 2>&1 | tee /var/log/aws-asg-bootstrap.log\nrc=$?\n# Signal the status from cfn-init\n/opt/aws/bin/cfn-signal -e $rc --stack ${AWS::StackName} --resource InstanceGroup --region ${AWS::Region}\nif [ -n \"${AdminUsername}\" ]; then\n    XCE_HOME=\"$(cat /etc/xcalar/default.cfg | grep \"^Constants.XcalarRootCompletePath\" | cut -d'=' -f2)\"\n    mkdir -p $XCE_HOME/config\n    chown -R xcalar:xcalar $XCE_HOME/config\n    jsonData='{ \"defaultAdminEnabled\": true, \"username\": \"'${AdminUsername}'\", \"email\": \"'${AdminEmail}'\", \"password\": \"'${AdminPassword}'\" }'\n    echo \"Creating default admin user ${AdminUsername} (${AdminEmail})\"\n    safe_curl -H \"Content-Type: application/json\" -X POST -d \"$jsonData\" \"http://127.0.0.1:12124/login/defaultAdmin/set\"\nelse\n    echo \"\\$AdminUsername is not specified\"\nfi\nexit $rc\n"
                    }
                }
            }
        }
    }
}