#!/bin/bash

az role definition create --role-definition "$(sed 's/\${ARM_SUBSCRIPTION_ID}/'${ARM_SUBSCRIPTION_ID}'/' "$1")"
