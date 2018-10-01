#!/bin/bash

ansible-vault encrypt --output workdir/secrets.yml workdir/secrets-orig.yml
