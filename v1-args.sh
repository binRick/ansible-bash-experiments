

optparse.define short=f long=ansible-playbook-list-hosts-file desc="path to ansible playbook list hosts output" variable=LIST_HOSTS_OUTPUT_FILE default=$DEFAULT_LIST_HOSTS_OUTPUT_FILE
optparse.define short=v long=verbose desc="Set flag for verbose mode" variable=verbose_mode value=true default=false
optparse.define short=u long=ssh-user desc="ssh_user" variable=ssh_user default=
optparse.define short=b long=ssh-bastion-host desc="ssh_bastion_host" variable=ssh_bastion_host default=
optparse.define short=K long=expected-kernel-version desc="expected_kernel_version" variable=expected_kernel_version default="$(uname -r)"
optparse.define short=F long=cached-facts-dir desc="report_dir" variable=report_dir default=
optparse.define short=0 long=skip-bastion-server-validation desc="skip_bastion_server_validation" variable=skip_bastion_server_validation default= value=1
optparse.define short=9 long=unique-hosts desc="unique_hosts" variable=_UNIQUE_HOSTS default=


## options
optparse.define short=0 long=skip-bastion-server-validation desc="skip_bastion_server_validation" variable=skip_bastion_server_validation default= value=1
optparse.define short=1 long=generate-report desc="_GENERATE_REPORT" variable=_GENERATE_REPORT default= value=1
optparse.define short=2 long=generate-report desc="_COLLECT_UNEXPECTED_KERNEL_HOSTS" variable=_COLLECT_UNEXPECTED_KERNEL_HOSTS default= value=1
optparse.define short=3 long=generate-report desc="_REBOOT_UNEXPECTED_KERNEL_HOSTS" variable=_REBOOT_UNEXPECTED_KERNEL_HOSTS default= value=1
optparse.define short=4 long=generate-report desc="This treats unique hosts as auth hosts => _SKIP_AUTH_HOSTS" variable=_SKIP_AUTH_HOSTS default= value=1
optparse.define short=5 long=generate-report desc="This treats ok auth hosts as sudo auth hosts => _SKIP_SUDO_AUTH_HOSTS" variable=_SKIP_SUDO_AUTH_HOSTS default= value=1



source $( optparse.build )

