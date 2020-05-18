#!/bin/bash
set -e
cd $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
export PATH=$(pwd)/bin:$PATH
for f in .submodules/bash-concurrent/concurrent.lib.sh .submodules/ansi/ansi.sh .submodules/optparrse/optparse.bash v1-defaults.sh v1-args.sh; do source $f; done



validate_inputs(){
    if [[ "$ssh_user" == "" ]]; then
        ansi --green "Enter your SSH User:"
        read -r ssh_user
    fi
    if [[ "$ssh_bastion_host" == "" ]]; then
        ansi --green "Enter your Bastion Host:"
        read -r ssh_bastion_host
    fi
    if [[ "$ssh_pass" == "" ]]; then
        ansi --green "Enter your SSH Password:"
        read -s ssh_pass
        export __P="$ssh_pass"
    else
        export __P="$ssh_pass"
    fi
}

ssh_user_homedir="/home/$ssh_user"
bin_prefix="$ssh_user_homedir/bin"
dns1_server="${dns1_server:-45.56.64.246}"
dns2_server="${dns2_server:-45.56.64.246}"
ssh_args="-q -tt -oLogLevel=ERROR -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oUser=${ssh_user}"
passh="command passh -P 'password' -p 'env:__P' -c2"
[[ ! -f ~/.ssh/id_rsa ]] && ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -q
debug_mode="${debug_mode:-0}"


get_env(){
    setup_env="export PROMPT_COMMAND= PS1= PATH=\"~/.local/bin:\$PATH\" __P=\"$__P\" ANSIBLE_SSH_ARGS=\"-oStrictHostKeyChecking=no\""
    echo -e "$setup_env"
}

reset_all_ansi(){
    ansi::resetAttributes
    ansi::resetForeground
    ansi::resetBackground
    ansi::resetColor
}

validate_bastion(){
    set +e
    _validate_bastion | grep '0:TCP OK' | grep '0:SSH OK' 
    set -e
}

_validate_bastion(){
    ssh="$bin_prefix/check_ssh -p 22 -H $ssh_bastion_host"
    tcp="$bin_prefix/check_tcp -p 22 -H $ssh_bastion_host"
    sub_cmds_file=$(mktemp)
    for sub_cmd in tcp ssh; do
        grep "^${sub_cmd}$" $sub_cmds_file -q || echo -e "$sub_cmd" >> $sub_cmds_file
        cmd="${!sub_cmd}"
        bastion_cmd="command ssh $ssh_args \"$ssh_bastion_host\" ${cmd} 2>/dev/null"
        out="$(wrap_passh "$bastion_cmd")"
        exit_code="$(echo -e "$out"|grep '^exit_code='|cut -d'=' -f2|head -n1)"
        out="$(echo -e "$out"|grep '^exit_code=' -v|grep -v 'Shared conn' | hardened_list|tr ',' ' ')"
        [[ "$debug_mode" == "1" ]] && \
            >&2 echo -e "\n [$sub_cmd]   exit_code=$exit_code\n\n      out=$out\n"
        ec_color=cyan
        echo -e "       $sub_cmd:$exit_code:$out"
    done
}


strip_ansi(){
    sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g"
}

hardened_list(){
    tr '\n' ' ' | tr ' ' '\n' | grep -v '^$' | tr '\n' ' ' | tr ' ' ',' | strip_ansi | sed 's/[[:space:]]/ /g'|sed 's/^[[:space:]]//g'
}

wrap_passh(){
    set +e
    cmd="$(_wrap_passh "$@")"
    err=$(mktemp)
    out="$(eval $cmd 2>$err| egrep -v '^SSH password:|^BECOME password')"
    ec=$?
    set -e
    echo -e "exit_code=$ec\n$out"
    >&2 cat $err
}

_wrap_passh(){
    cmd="$passh $@"
    echo -e "$cmd"
}

list_bastion_local_bin(){
    set +e
    sub_cmd="ls ~/.local/bin"
    cmd="ssh $ssh_args $ssh_bastion_host \"$sub_cmd\""
    out="$(wrap_passh "$cmd")"
    exit_code="$(echo -e "$out"|grep '^exit_code='|cut -d'=' -f2|head -n1)"
    out="$(echo -e "$out"|grep '^exit_code=' -v|tr '[[:space:]]' '\n'|grep -v '^$'|tr '\n' ' ')"
    set -e
    [[ "$exit_code" == "0" ]] && echo -e "$out" && return
    echo -e "exit_code:$exit_code"
}

list_bastion_bin(){
    sub_cmd="ls $bin_prefix"
    cmd="ssh $ssh_args $ssh_bastion_host \"$sub_cmd\""
    out="$(wrap_passh "$cmd")"
    exit_code="$(echo -e "$out"|grep '^exit_code='|cut -d'=' -f2|head -n1)"
    out="$(echo -e "$out"|grep '^exit_code=' -v|tr '[[:space:]]' '\n'|grep -v '^$'|tr '\n' ' ')"
    set -e
    [[ "$exit_code" == "0" ]] && echo -e "$out" && return
    echo -e "exit_code=$exit_code\n$out"
}

rsync_local_bin_to_bastion(){
    set +e
    rsync_cmd="$passh rsync -var bin -e \"ssh $ssh_args\" $ssh_bastion_host:$bin_prefix/../."
    out="$(wrap_passh "$rsync_cmd")"
    exit_code="$(echo -e "$out"|grep '^exit_code='|cut -d'=' -f2|head -n1)"
    out="$(echo -e "$out"|grep '^exit_code=' -v)"
    echo -e "rsync exited $exit_code, $out"
    set -e
}

find_hosts_ping_ok(){
   _find_hosts_ping "$1" 2>/dev/null
}

find_hosts_ping_fail(){
  _find_hosts_ping "$1" >/dev/null
}

_find_hosts_ping(){
    host_list="$1"
    ok_hosts_file=$(mktemp)
    failed_hosts_file=$(mktemp)
    remote_cmd="id"
    forks="5"
    for h in $host_list; do
        ping_cmd="$bin_prefix/check_ping -H $h -w 3000.0,80% -c 5000.0,100% -p 1"
        bastion_cmd="$passh command ssh $ssh_args \"$ssh_bastion_host\" ${ping_cmd}"
        [[ "$debug_mode" == "1" ]] && \
            >&2 ansi --yellow "$ping_cmd" && \
            >&2 ansi --cyan "$bastion_cmd"
        set +e
        out="$(eval $bastion_cmd 2>/dev/null | head -n1)"
        if [[ "$out" == "PING OK"* ]]; then
            echo -e "$h"
        else
            >&2 echo -e "$h"
        fi
        ec=$?
        set -e
        [[ "$debug_mode" == "1" ]] && \
            >&2 echo -e "ec=$ec, out=\"$out\""
    done

}

find_hosts_auth(){
    while read -r line; do
        _host="$(echo -e "$line"|cut -d' ' -f1)"
        if [[ "$line" == *"rc=0"* ]]; then
            msg="   line OK!: $line" 
            msg_color="green"
            echo -e "$_host"
        elif [[ "$line" == *"FAILED"* ]]; then
            msg="   FAILED!: $line" 
            msg_color="red"
            >&2 echo -e "$_host"
        elif [[ "$line" == *"UNREACHABLE"* ]]; then
            msg="   UNREACHABLE!: $line" 
            msg_color="red"
            >&2 echo -e "$_host"
        else
            msg="unknown line handler: $line"
            msg_color="red"
            >&2 echo -e "$(ansi --$msg_color "$msg")"
        fi
        [[ "$options" == "with_sudo" ]] && \
            >&2 echo -e "$(ansi --$msg_color "$msg")"
    done < <(find_hosts_auth_lines "$1" "$2")
}

find_hosts_auth_ok(){
    set +e
    find_hosts_auth "$1" "$2" 2>/dev/null
    set -e
}

find_hosts_auth_fail(){
    set +e
    find_hosts_auth "$1" "$2" >/dev/null
    set -e
}

find_hosts_auth_lines(){
    _find_hosts_auth_ok "$1" "$2" | grep ' | ' | cut -d' ' -f1,3,5
}

_find_hosts_auth_ok(){
    host_list="$1"
    options="$2"
    with_sudo=0
    [[ "$options" == "with_sudo" ]] && with_sudo=1

    ok_hosts_file=$(mktemp)
    host_list="$(echo -e "$host_list"|hardened_list)"
    failed_hosts_file=$(mktemp)
    remote_cmd="id"
    forks="5"
    cmd_a="ansible $host_list -u $ssh_user -f $forks -i $host_list -k -m command -a '$remote_cmd'"
    cmd_a_sudo="$cmd_a -bK"
    _cmd="hostname -f;pwd;id;ls bin;pip3 install ansible==2.8.11 --user --upgrade"
    cmd="command -v ansible;ansible --version"
    cmd="$cmd;$cmd_a"
    cmd_sudo="$cmd_a_sudo"
    cmd="$(_wrap_passh "$cmd")"
    cmd_sudo="$passh $cmd_sudo"
    setup_env=$(get_env)
    cmd="sh -c '$setup_env && $cmd'"
    cmd_sudo="sh -c '$setup_env && $cmd_sudo'"
    bastion_cmd="$passh command ssh $ssh_args \"$ssh_bastion_host\" \"$cmd\""
    bastion_cmd_sudo="$passh command ssh $ssh_args \"$ssh_bastion_host\" \"$cmd_sudo\""


    [[ "$debug_mode" == "1" ]] && \
        >&2 ansi --yellow "$cmd" && \
        >&2 ansi --yellow --bg-black --bold --underline "$cmd_sudo" && \
        >&2 ansi --cyan "$bastion_cmd" && \
        >&2 ansi --yellow --bg-black --bold --underline "$bastion_cmd_sudo"
 
    if [[ "$out" == "PING OK"* ]]; then
        echo -e "$h"
    else
        >&2 echo -e "$h"
    fi

    
    set +e
    if [[ "$with_sudo" == "1" ]]; then
        eval $bastion_cmd_sudo
        ec=$?
    else
        eval $bastion_cmd   
        ec=$?
    fi
    set -e

    [[ "$debug_mode" == "1" ]] && \
        >&2 echo -e "ec=$ec, with_sudo=$with_sudo, "

}

parse_ansible_output_lines(){
    _results=""
    _ok=
    while read -r line; do
        if [[ "$line" == *"rc=0"* ]]; then
            _host="$(echo -e "$line"|cut -d' ' -f1)"
            _ok=1
            msg="   line OK!: $line" 
            msg_color="green"
            echo -e "$_host"
        elif [[ "$line" == *"FAILED"* ]]; then
            _host="$(echo -e "$line"|cut -d' ' -f1)"
            msg="   FAILED!: $line" 
            msg_color="red"
            >&2 echo -e "$_host"
        elif [[ "$line" == *"UNREACHABLE"* ]]; then
            _host="$(echo -e "$line"|cut -d' ' -f1)"
            msg="   UNREACHABLE!: $line" 
            msg_color="red"
            >&2 echo -e "$_host"
        else
            _type="output"
            msg=" [$_host] [$_ok] unknown line handler: $line"
            msg_color="red"
            >&2 echo -e "$(ansi --$msg_color "$msg")"
        fi
    done < <(echo -e "$1")
}

extract_ansible_command_outputs_and_exit_codes(){
    out="$1"
    parsed="$(parse_ansible_output_lines "$out")"
    echo -e "parsed=$parsed"
    echo -e "$_results"
}

check_updates_hosts(){
    host_list="$1"
    host_list="$(echo -e "$host_list"|tr '\n' ' ' |tr ' ' ','|sed 's/^,//g'|sed 's/,$//g')"
    forks="5"
    md="$(mktemp -d)"
    module_args="-a \"bin/check_updates\" --tree $md"
    module="script"

    cmd="~/.local/bin/ansible $host_list -u $ssh_user -f $forks -i $host_list, -m $module $module_args -bkK -c ssh"
    setup_env=$(get_env)
    cmd="sh -c '$setup_env && $cmd 2>/dev/null; [[ -d \"$md\" ]] && (tar -cf - $md|base64 -w0)'"


    bastion_cmd="command ssh $ssh_args \"$ssh_bastion_host\" ${cmd}"
    #ansi --yellow "$cmd"
    ansi --yellow --bg-black "$bastion_cmd"

    set +e
    out="$(wrap_passh "$bastion_cmd" 2>&1)"
    exit_code="$(echo -e "$out"|grep '^exit_code='|cut -d'=' -f2|head -n1)"
    tree_base64="$(echo -e "$out"|grep '^tar: ' -A1|tail -n1)"
    out="$(echo -e "$out"|grep '^exit_code=' -v|grep -v '^export '|grep -v '^tar: ' -B9999)"
    set -e

    ansi --yellow "$cmd"
    ansi --green "$out"
    ansi --cyan "$exit_code"
    ansi --white --underline "$tree_base64"
 
    echo Check update

}
reboot_hosts(){
    host_list="$1"
    host_list="$(echo -e "$host_list"|tr '\n' ' ' |tr ' ' ','|sed 's/^,//g'|sed 's/,$//g')"
    forks="5"

    # live mode
    #module="reboot"
    #module_args=""

    # dev mode
    module_args="-a 'id'"
    module="command"


    cmd="~/.local/bin/ansible $host_list -u $ssh_user -f $forks -i $host_list, -m $module $module_args -bk -c ssh"
    setup_env=$(get_env)
    cmd="sh -c '$setup_env && $cmd 2>/dev/null'"


    bastion_cmd="command ssh $ssh_args \"$ssh_bastion_host\" ${cmd}"
    #ansi --yellow "$cmd"
    #ansi --yellow --bg-black "$bastion_cmd"

    set +e
    _err=$(mktemp)
    out="$(wrap_passh "$bastion_cmd" 2>$_err)"
    exit_code="$(echo -e "$out"|grep '^exit_code='|cut -d'=' -f2|head -n1)"
    out="$(echo -e "$out"|grep '^exit_code=' -v|grep -v '^export ')"    
    err="$(cat $_err)"
    set -e

    ansi --yellow "$cmd"
    ansi --red "$err"
    ansi --green "$out"
    ansi --cyan "$exit_code"
    
    echo REBOOT OK
}
xxxxxxxxxxx(){
    for h in $host_list; do
        echo -e "h=$h"
        cmd="sudo -u root $bin_prefix/check_updates"
        this_cmd="${cmd}"
        bastion_cmd="$passh command ssh $ssh_args \"$ssh_bastion_host\" ${this_cmd}"
        remote_cmd="command passh -P 'password:' -p 'env:__P' -c1 command ssh -J \"$ssh_bastion_host\" $ssh_args \"$h\" ${this_cmd}"
ansi --yellow "$remote_cmd"
        set +e
        result="$(eval $bastion_cmd 2>/dev/null)"
        ec=$?
        set -e
        ec_color=cyan
        [[ "$ec" == "0" ]] && ec_color=green && echo -e "$h:$sub_cmd" >> $ok_hosts_file
        [[ "$ec" != "0" ]] && ec_color=red && echo -e "$h:$sub_cmd" >> $failed_hosts_file

        _result="$(echo -e "$result"|head -n1)"
        msg=" [$ssh_bastion_host => check $sub_cmd => $h]     $(ansi --$ec_color "$_result")"
        echo -e "$msg"
   done

   echo -e "\n\nok:"
   cat $ok_hosts_file

   echo -e "\n\nfailed:"
   cat $failed_hosts_file

}

collect_facts_return_dir(){
    host_list="$1"
    host_list="$(echo -e "$host_list"|tr ' ' ',')"
    facts_dir="$(mktemp -d)"
    cmd="command ansible -i $host_list -m setup --tree $facts_dir/ all"
    set +e
    out="$(eval $cmd)"
    ec=$?
    set -e
    [[ "$debug_mode" == "1" ]] && \
        >&2 echo -e "\n\nfacts exited $ec with output \"$(echo -e "$out"|wc -l)\" bytes to facts dir $facts_dir\n\n"
    echo -e "$facts_dir"
}

find_hosts_with_unexpected_kernel_version(){
    _l=""
    while read -r host kernel_version; do
        [[ "$kernel_version" != "$expected_kernel_version" ]] && _l="$_l $host"
    done < <(find_host_kernels "$1" "$2"|grep ':' | tr ':' ' ')
    echo -e "$_l"
}

find_host_kernels(){
    set +e
    host_list="$1"
    report_dir="$2"
    [[ ! -d "$reports_dir" ]] && reports_dir="$(collect_facts_return_dir "$host_list")"
    [[ ! -d "$reports_dir" ]] && echo -e "invalid reports dir" && return 1
    host_list="$(echo -e "$host_list"||tr ',' ' ')"
    for h in $(echo -e "$host_list"|tr ',' ' ' | tr ' ' '\n'); do
        f="$report_dir/$h"
        [[ ! -f "$f" || ! -d "$report_dir" ]] && >&2 echo -e "missing $h in $report_dir!" && continue
        kernel="$(cat $f | jq '.ansible_facts.ansible_kernel' -Mrc)"
        echo -e "$h:$kernel"
    done
    set -e
}

cmdb_report(){
    host_list="$1"
    _t="$2"
    if [[ "$3" == "" ]]; then
        _d="$(collect_facts_return_dir "$host_list")"
    else
        _d="$3"
    fi

    _c="--columns name,os,ip,mem,cpus,kernel"
    cmd="python3 ~/.local/lib/ansiblecmdb/ansible-cmdb.py  -t $_t $_c  $_d/  2>/dev/null|grep -v '^$'"
    set +e
    out="$(eval $cmd)"
    ec=$?
    set -e

    [[ "$ec" != "0" ]] && \
        msg="\n\ncmdb exited $ec with output \"$(echo -e "$out"|wc -l)\" bytes\n\n$cmd\n\n" && \
        msg="$(ansi --red "$msg")" && \
        >&2 echo -e "$msg"

    [[ "$ec" == "0" ]] && \
        msg="$out" && \
        echo -e "$msg"
}

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
            result="$(eval $bastion_cmd 2>/dev/null)"
            ec=$?
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
    cat "$LIST_HOSTS_OUTPUT_FILE"
}
save_play_object(){
    play="$1"
    patterns="$2"
    host_list="$3"
    host_list="$(echo -e "$host_list"|tr ' ' '\n'|grep -v '^$'|tr '\n' ' ')"
    msg="play=$play patterns=$patterns host_list=$host_list"
    [[ "$debug_mode" == "1" ]] && \
        >&2 ansi --yellow "$msg" \
        echo -e "$msg"
}

handle_hosts(){
    play="$1"
    patterns="$2"
    host_list="$3"
    [[ "$debug_mode" == "1" ]] && \
        >&2 echo -e "[handle_hosts] $host_list"
    unique_hosts="$(echo -e "$unique_hosts" $(echo -e "$host_list") |tr ' ' '\n' |grep -v '^$' | sort -u|tr '\n' ' ')"

    [[ "$debug_mode" == "1" ]] && >&2 ansi --green "[handle_hosts] unique_hosts=$unique_hosts"
}


handle_play_object(){
    save_play_object "$1" "$2" "$3"
    handle_hosts "$1" "$2" "$3"
}

discover_unique_hosts(){
    set +e
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
    [[ "$debug_mode" == "1" ]] && >&2 ansi --green "$unique_hosts"
    set -e
}
summary_msg(){
    ansi::green
    ansi::bgBlack
    ansi::underline
    sudo_msg="\n\n$1:      $(ansi --cyan --bg-black "$2")  \n"
    echo -e "$sudo_msg"
    reset_all_ansi
}

available_unique_hosts_summary(){
    reset_all_ansi

    set +e

    ok_ping_hosts="$(find_hosts_ping_ok "$unique_hosts"|hardened_list)"
    msg="$(ansi --green --underline "ping ok:")   $ok_ping_hosts\n\n"
    summary_msg "ping ok" "$ok_ping_hosts"

    ok_auth_hosts="$(find_hosts_auth_ok "$ok_ping_hosts"|hardened_list)"
    msg="\n\nssh auth ok:      $(ansi --cyan --bg-black "$ok_auth_hosts")  \n"
    summary_msg "ssh auth ok" "$ok_auth_hosts"

    ok_sudo_auth_hosts="$(find_hosts_auth_ok "$ok_ping_hosts" "with_sudo"|hardened_list)"
    sudo_msg="\n\nssh sudo auth ok:      $(ansi --cyan --bg-black "$ok_sudo_auth_hosts")  \n"
    summary_msg "ssh sudo auth ok" "$ok_sudo_auth_hosts"


    set -e
}


validate_inputs


if [[ "$skip_bastion_server_validation" != "1" ]]; then
    validate_bastion || { echo -e "validate_bastion failed!" && exit 55; }
    rsync_local_bin_to_bastion >/dev/null 
    msg="$(ansi --cyan --bold "bastion bin:") $(ansi --green "$(list_bastion_bin)")" 
    echo -ne "$msg\n\n" 

    list_bastion_local_bin | grep ansible-playbook -q || wrap_passh "pip3 install ansible==2.8.11 --user"
    msg="$(ansi --cyan --bold "bastion local bin:") $(ansi --green "$(list_bastion_local_bin)")" 
    echo -ne "$msg\n\n"
fi

main(){
    if [[ "$_UNIQUE_HOSTS" == "" ]]; then
        echo -e "discovering hosts"
        discover_unique_hosts
        echo -e "unique_hosts=\"$unique_hosts\"\n\n"
    else
        echo -e "cached hosts!"
        unique_hosts="$(echo -e "$_UNIQUE_HOSTS"|tr ' ' ',')"
    fi


    if [[ "$_SKIP_AUTH_HOSTS" == "1" ]]; then
        src="unique"
        ok_auth_hosts="$(echo -e "$unique_hosts" |hardened_list)"
    else
        src="lookup"
        ok_auth_hosts="$(find_hosts_auth_ok "$unique_hosts" ""|hardened_list)"
    fi
    msg=" [src=$src]   :: ok_auth_hosts=\"$ok_auth_hosts\"\n\n"
    msg="$(ansi --yellow "$msg")"
    echo -e "$msg"

    if [[ "$_SKIP_SUDO_AUTH_HOSTS" == "1" ]]; then
        src="ok_auth_hosts"
        ok_sudo_auth_hosts="$(echo -e "$ok_auth_hosts" |hardened_list)"
    else
        src="lookup"
        ok_sudo_auth_hosts="$(find_hosts_auth_ok "$ok_auth_hosts" "with_sudo"|hardened_list)"
    fi
    msg=" [src=$src]   :: ok_sudo_auth_hosts=\"$ok_sudo_auth_hosts\"\n\n"
    msg="$(ansi --yellow "$msg")"
    echo -e "$msg"

    if [[ ! -d "$report_dir" ]]; then
        ansi --yellow "Collecting Facts..."
        report_dir="$(collect_facts_return_dir "$ok_auth_hosts")"
        ansi --yellow "Collected in $report_dir"
    fi

    if [[ "$_GENERATE_REPORT" == "1" ]]; then
        ansi --yellow "Generating Report"
        cmdb_report "$ok_auth_hosts" txt_table2.tpl "$report_dir"
    fi


    if [[ "$_COLLECT_UNEXPECTED_KERNEL_HOSTS" == "1" || "$_REBOOT_UNEXPECTED_KERNEL_HOSTS" == "1" ]]; then
        ansi --yellow "Collecting Unpexpected Kernel Hosts..."
        unexpected_kernel_hosts="$(find_hosts_with_unexpected_kernel_version "$ok_auth_hosts" "$report_dir")"

        ansi --yellow "expected_kernel_version=$expected_kernel_version"
        ansi --yellow "unexpected_kernel_hosts=$unexpected_kernel_hosts"
    fi

    if [[ "$_REBOOT_UNEXPECTED_KERNEL_HOSTS" == "1" ]]; then
        reboot_hosts "$unexpected_kernel_hosts"
    fi


    check_updates_hosts "$ok_sudo_auth_hosts"


    echo OK
}

main
