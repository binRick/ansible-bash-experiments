

optparse.define short=f long=ansible-playbook-list-hosts-file desc="path to ansible playbook list hosts output" variable=LIST_HOSTS_OUTPUT_FILE default=$DEFAULT_LIST_HOSTS_OUTPUT_FILE
optparse.define short=v long=verbose desc="Set flag for verbose mode" variable=verbose_mode value=true default=false
optparse.define short=u long=ssh-user desc="ssh_user" variable=ssh_user default=
optparse.define short=b long=ssh-bastion-host desc="ssh_bastion_host" variable=ssh_bastion_host default=

source $( optparse.build )

