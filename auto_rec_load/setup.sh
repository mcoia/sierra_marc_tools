#!/bin/bash


cp vars.yml.example vars.yml
cp auto_rec_load.conf.example auto_rec_load.conf
cp run.example run
cp db_seed.db.example db_seed.db

# edit vars.yml to your environment

apt-get install ansible
ansible-playbook setup_playbook.yml -vvvv -e "hosts=127.0.0.1"

# edit db_seed.db (makes it easier to load the database)
# edit run
# edit auto_rec_load.conf