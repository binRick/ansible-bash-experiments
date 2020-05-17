#!/usr/bin/env bash
set -e
cd $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
export PATH=$(pwd)/bin:$PATH
source .submodules/ansi/ansi.sh
source .submodules/bash-concurrent/concurrent.lib.sh

ssh_bastion_host="${ssh_bastion_host:-undefined-ssh-bastion-env-var.com}"
ssh_user="${ssh_user:-undefined-user-env-var}"
bin_prefix="/home/$ssh_user/bin"
ssh_pass="${ssh_pass:-undefined-password-env-var}"
dns1_server="${dns1_server:-45.56.64.246}"
dns2_server="${dns2_server:-45.56.64.246}"
ssh_args="-oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oUser=${ssh_user}"
passh="command passh -P 'password:' -p 'env:__P' -c1"
[[ ! -f ~/.ssh/id_rsa ]] && ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -q




export __P="$ssh_pass"
rsync_cmd="$passh rsync -ar bin -e \"ssh $ssh_args\" $ssh_bastion_host:~$ssh_user/."
eval $rsync_cmd
export __P=



process_play_hosts(){
    ok_hosts_file=$(mktemp)
    failed_hosts_file=$(mktemp)
    sub_cmds_file=$(mktemp)
    host_list="$1"
    echo -e "\n\n\n\n"
    echo -e "[process_play_hosts] $host_list"
    echo -e "\n\n\n\n"
    for h in $host_list; do
        echo -e "h=$h"

        # bastion host => host check commands
        ping="~$ssh_user/bin/check_ping -H $h -w 3000.0,80% -c 5000.0,100% -p 1"
        ssh="~$ssh_user/bin/check_ssh -p 22 -H $h"
        tcp="~$ssh_user/bin/check_tcp -p 22 -H $h"
        dns1="~$ssh_user/bin/check_dns -s $dns1_server -H $h -q A"
        dns2="~$ssh_user/bin/check_dns -s $dns2_server -H $h -q A"
        authed_hostname="$bin_prefix/check_by_ssh -H $h -p 22 -u $ssh_user -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=ERROR -o'ProxyCommand ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=ERROR $ssh_bastion_host -W %h:%p' -C 'command hostname -f'"

        # commands executed on host proxied via bastion host
        updates_any="sudo -u root $bin_prefix/check_updates"
        updates_security="sudo -u root $bin_prefix/check_updates --no-boot-check --security-only"
        updates_kernel_boot="sudo -u root $bin_prefix/check_updates --boot-check-warning"
    
        ansi --yellow "$updates_any"
        ansi --yellow "$updates_security"
        ansi --yellow "$updates_kernel_boot"
        ansi --yellow "$authed_hostname"


        for sub_cmd in dns1 dns2 ping ssh tcp; do
            grep "^${sub_cmd}$" $sub_cmds_file -q || echo -e "$sub_cmd" >> $sub_cmds_file
            this_cmd="${!sub_cmd}"
            bastion_cmd="$passh command ssh $ssh_args \"$ssh_bastion_host\" ${this_cmd}"
            remote_cmd="command passh -P 'password:' -p 'env:__P' -c1 command ssh -J \"$ssh_bastion_host\" $ssh_args \"$h\" ${this_cmd}"
            set +e
            export __P="$ssh_pass"
            result="$(eval $bastion_cmd 2>/dev/null)"
            ec=$?
            export __P=
            set -e
            ec_color=cyan
            [[ "$ec" == "0" ]] && ec_color=green && echo -e "$h:$sub_cmd" >> $ok_hosts_file
            [[ "$ec" != "0" ]] && ec_color=red && echo -e "$h:$sub_cmd" >> $failed_hosts_file

            _result="$(echo -e "$result"|head -n1)"
            msg=" [$ssh_bastion_host => check $sub_cmd => $h]     $(ansi --$ec_color "$_result")"
            echo -e "$msg"
        done
    done
    
    echo -e "\n\nsub_cmds_file:"
    cat $sub_cmds_file

    echo -e "\n\nok:"
    cat $ok_hosts_file

    echo -e "\n\nfailed:"
    cat $failed_hosts_file

    echo -e "\n\nfailed by check type:"
    while read -r check; do 
        msg="    [$check]"
        echo -e "$(ansi --red "$msg")"
        while read -r host; do
            msg="         [$host] "
            echo -e "$(ansi --red "$msg")"
        done < <(grep ":${check}$" $failed_hosts_file|cut -d':' -f1)
    done < <(cat $sub_cmds_file)


    echo -e "\n\nok by check type:"
    while read -r check; do 
        msg="    [$check]"
        echo -e "$(ansi --green "$msg")"
        while read -r host; do
            msg="         [$host] "
            echo -e "$(ansi --green "$msg")"
        done < <(grep ":${check}$" $ok_hosts_file|cut -d':' -f1)
    done < <(cat $sub_cmds_file)





    failed_some="$(cat $failed_hosts_file|cut -d':' -f1|sort -u)"
    ok_some="$(cat $ok_hosts_file|cut -d':' -f1|sort -u)"

    echo -e "\n\nOK some:  \n$ok_some"
    echo -e "\n\nFAIL some:  \n$failed_some"

}




unique_hosts=""

play=""
patterns=""
hosts=""
host_list=""

read_list_hosts_output(){
    cat LIST_HOSTS_EXAMPLE_OUTPUT.txt
}
save_play_object(){
    play="$1"
    patterns="$2"
    host_list="$3"
    host_list="$(echo -e "$host_list"|tr ' ' '\n'|grep -v '^$'|tr '\n' ' ')"
    msg="play=$play patterns=$patterns host_list=$host_list"
    ansi --yellow "$msg"
}

handle_hosts(){
    play="$1"
    patterns="$2"
    host_list="$3"
    echo -e "[handle_hosts] $host_list"
    unique_hosts="$(echo -e "$unique_hosts" $(echo -e "$host_list") |tr ' ' '\n' |grep -v '^$' | sort -u|tr '\n' ' ')"
}


handle_play_object(){
    save_play_object "$1" "$2" "$3"
    handle_hosts "$1" "$2" "$3"
}

while read -r line; do
    [[ "$line " == play* && "$host_list" != "" && "$patterns" != "" ]] && \
        handle_play_object "$play" "$patterns" "$host_list"

    if [[ "$line " == play* ]]; then
        play="$line"
        patterns=""
        hosts=""
        host_lists=""
        continue
    fi
    [[ "$line " == pattern* ]] && patterns="$line" && continue
    [[ "$line " == hosts* ]] && hosts="$line" && continue
    [[ "$hosts" != "" ]] && host_list="$host_list $line"

done < <(read_list_hosts_output)


ansi --green "$unique_hosts"

process_play_hosts "$unique_hosts"

