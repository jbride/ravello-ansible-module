#!/bin/bash

if [ -z "$APP_NAME" ]
then
  # Set this to whatever you want the app to be called
  APP_NAME="OCP-v3.11-CNS-Baseline"
  datest=`date +%Y%m%d%H%M%S`
  export APP_NAME="${APP_NAME}-${datest}"
fi


time /usr/bin/ansible-playbook --extra-vars \
	"application_name=${APP_NAME} blueprint_name=${APP_NAME}-bp" \
	-i ./inventory \
	--ask-vault-pass \
	main.yml
