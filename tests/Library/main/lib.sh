#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib.sh of /CoreOS/firewalld/Library/main
#   Description: Manages firewalld configuration, restoration and other stuff
#   Author: Tomas Dolezal <todoleza@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   library-prefix = fwd
#   library-version = 0.1
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

: <<'=cut'
=pod

=head1 NAME

firewalld/main - Manages firewalld configuration, state and cleanup

=head1 DESCRIPTION

firewalld BeakerLib library to aid basic and advanced setup workflows.

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

: <<'=cut'
=pod

=head1 VARIABLES

Below is the list of global variables.

=over

=item fwd_IGNORE_CONFIG

Makes fwdSetup not drop existing config nor assert default configuration
state.

=item fwd_VERIFY_RPM

Makes fwdSetup assert integrity of installed files by RPM.

=back

=cut

__fwdPACKAGES=(
    firewalld
    selinux-policy
    nftables
    libnftnl
    libmnl
    iptables
    ipset
    NetworkManager
    )
__fwd_CONF_FILE="/etc/firewalld/firewalld.conf"

__fwd_SETUP_DONE=false

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

: <<'=cut'
=pod

=head1 FUNCTIONS

=cut

__fwdStart() {
    #should capture service state by issuing rlService command (consumed by Cleanup)
    rlServiceStart firewalld
    # a blocking command is used
    rlRun "firewall-cmd --state" 0 "firewalld started"
}
__fwdStop() {
    rlServiceStop firewalld
    firewall-cmd --state -q
    if [[ $? -ne 252 ]]; then
        rlFail "Could not stop firewalld daemon"
    else
       return 0
    fi
}

__fwdCleanConfig() {
    local fwconfdir
    local ret=0
    for fwconfdir in /etc/firewalld/*/; do
        if [[ -z $(find "$fwconfdir" -type d -empty) ]]; then
            rm -vf -- $fwconfdir/*
            ret=1
        fi
    done
    return $ret
}

__fwdCleanDebugLog() {
    local logfile="/var/log/firewalld"
    truncate -s 0 "$logfile" || \
        rlFail "failed to remove debug log data"
    restorecon "$logfile"
}

__fwdSubmitLog() {
    # call me just once, else I'll probably overwrite output by last invocation
    rlFileSubmit /var/log/firewalld firewalld.log
}

__fwdSetDebug() {
    local LEVEL=${1:-10}
    echo "FIREWALLD_ARGS=--debug=$LEVEL" >> /etc/sysconfig/firewalld || \
        rlFail "failed to enable debug flag"
}

__fwdLogFunctionEnter() {
    rlLogInfo "${FUNCNAME[1]} called"
}

__fwdAssertSetup() {
    if ! $__fwd_SETUP_DONE; then
        rlDie "${FUNCNAME[1]} called without calling fwdSetup first"
    fi
}

: <<'=cut'
=pod

=head2 fwdSetup

Asserts environment and starts firewalld. Configuration cleanup is attempted
and default state is verified.

    fwdSetup [-n|--no-start]

=over

=item -n|--no-start

Do not start service after setup.

=back

=cut

fwdSetup() {
    local NOSTART=false
    local ret=0

    __fwdLogFunctionEnter
    if $__fwd_SETUP_DONE; then
        rlDie "${FUNCNAME[0]} has already been called"
    fi
    __fwd_SETUP_DONE=true

    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--no-start)
                NOSTART=true
                shift
                ;;
            *)
                rlLogError "wrong parameter '$1' to ${FUNCNAME[0]}"
                ret=1
                shift
                ;;
        esac
    done
    rlFileBackup --namespace fwdlib --clean /etc/firewalld/ /etc/sysconfig/firewalld \
        /etc/sysconfig/network-scripts/
    if [[ -z $fwd_IGNORE_CONFIG ]]; then
        __fwdCleanConfig || rlLogWarning "default config directory was not clean"
        if [[ -z $fwd_VERIFY_RPM ]]; then
            rlRun "rpm -V firewalld" 0,1 "check firewalld configuration non-changed default state"
            if [[ $? -ne 0 ]]; then
                rlLogWarning "firewalld system configuration is not in default state"
                #rlLogWarning "accepted because fwd_VERIFY_RPM is not set"
            fi
        else
            rlRun "rpm -V firewalld" 0 "firewalld configuration is in non-changed default"
        fi
    fi
    __fwdSetDebug
    __fwdCleanDebugLog
    rlFileBackup --namespace fwdlib_setup --clean /etc/firewalld/ /etc/sysconfig/firewalld \
        /etc/sysconfig/network-scripts/
    if ! $NOSTART ; then
        __fwdStart
    else
        __fwdStop
    fi
}

: <<'=cut'
=pod

=head2 fwdCleanup

Restores configuration and service state before fwdSetup was called.

=cut

fwdCleanup() {
    __fwdAssertSetup
    __fwdLogFunctionEnter
    __fwdSubmitLog
    rlServiceStop firewalld
    rlRun "firewall-cmd --state" 252 "firewalld stopped"
    __fwdCleanDebugLog
    rlFileRestore --namespace fwdlib
    # make sure no configuration of firewall is left behind
    if iptables --version | grep -q "nf_tables"; then
        rlRun "nft flush ruleset" 0 "resetting system firewall configuration (nft / iptables-nft)"
    else
        rlLogInfo "not resetting system firewall configuration on behalf of firewalld (iptables-compat)"
#       for prefix in ip ip6; do
#           for table in $(cat /proc/net/${prefix}_tables_names); do
#               ${prefix}tables -t $table -F
#               ${prefix}tables -t $table -X
#               ${prefix}tables -t $table -Z
#               #todo: reset policies
#               #todo: ebtables cleanup
#               case $table in
#                   nat)
#                       ;;
#                   mangle)
#                       ;;
#                   security)
#                       ;;
#                   raw)
#                       ;;
#                   filter)
#                       ;;
#               esac
#           done
#       done
    fi
    __fwd_SETUP_DONE=false
    rlServiceRestore firewalld
}

: <<'=cut'
=pod

=head2 fwdRestart

Restarts firewalld service.

=cut

fwdRestart() {
    __fwdStart
}

: <<'=cut'
=pod

=head2 fwdResetConfig

Resets config to state after fwdSetup was called and drops runtime firewall config.

    fwdResetConfig [-n|--no-restart]

=over

=item -n|--no-restart

Do not restart firewalld after reseting permanent config.

=back

=cut
fwdResetConfig() {
    local NORESTART=false
    local ret=0

    __fwdAssertSetup
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--no-restart)
                NORESTART=true
                shift
                ;;
            *)
                rlLogError "wrong parameter '$1' to ${FUNCNAME[0]}"
                ret=1
                shift
                ;;
        esac
    done

    rlFileRestore --namespace fwdlib_setup
    if ! $NORESTART ; then
        __fwdStart
    fi
    return $ret
}

: <<'=cut'
=pod

=head2 fwdSetBackend

Sets firewalld backend to one of `nftables` or `iptables`. Attempt to
backend when the option is not available will cause Error and return 1.
If backend is not specified, it is set to nftables by default.

    fwdSetBackend [nftables|iptables]

=cut
fwdSetBackend() {
    local NEW_BACKEND="${1:-nftables}"

    if ! grep -q "FirewallBackend=" $__fwd_CONF_FILE; then
        rlLogError "${FUNCNAME[0]}: failed to set to $NEW_BACKEND, option not available"
        return 1
    fi

    if ! [[ $NEW_BACKEND =~ ^(iptables|nftables)$ ]]; then
        rlLogError "${FUNCNAME[0]}: wrong backend '$NEW_BACKEND' specified"
        return 1
    fi
    rlRun "sed -ie '/FirewallBackend=/ s/=.*/=$NEW_BACKEND/' $__fwd_CONF_FILE" 0 \
        "Set firewalld backend to $NEW_BACKEND"
}

: <<'=cut'
=pod

=head2 fwdGetBackend

Returns name of firewalld backend as one of `nftables` or `iptables`.

    fwdGetBackend

=cut
fwdGetBackend() {
    local backend_name
    local firewalld_module_inits
    if ! grep -q "FirewallBackend=" $__fwd_CONF_FILE; then
        #rlLogError "${FUNCNAME[0]}: failed to set to $NEW_BACKEND, option not available"
        #return 1

        # for safety, check that nftables are not supported
        firewalld_module_inits=$(rpm -qa 'python*-firewall' -l | grep '__init__.py$')
        [[ $? -ne 0 ]] && rlFail "could not query firewalld python modules"
        if ! grep -q "nftables" $firewalld_module_inits; then
            # no nftables references, FALLBACK_FIREWALL_BACKEND not used
            echo "iptables"
        else
            rlLogErorr "configuration option missing, refusing call of ${FUNCNAME[0]}"
            return 1
        fi
        return
    fi

    rlRun "backend_name=\$(sed -rne '/FirewallBackend=/ s/.*=(.+)$/\\1/p' $__fwd_CONF_FILE)" 0 \
        "Getting firewalld backend"

    if ! [[ $backend_name =~ ^(iptables|nftables)$ ]]; then
        rlLogError "${FUNCNAME[0]}: wrong backend '$backend_name' detected"
        return 1
    fi
    echo "$backend_name"
}

# TODO: verify a rule is present in system firewall configuration
# TODO: abstract over iptables & nftables (using json output)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Execution
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#: <<'=cut'
#=pod
#
#=head1 EXECUTION
#
#This library supports direct execution. When run as a task, phases
#provided in the PHASE environment variable will be executed.
#Supported phases are:
#
#=over
#
#=item Create
#
#Create a new empty file. Use FILENAME to provide the desired file
#name. By default 'foo' is created in the current directory.
#
#=item Test
#
#Run the self test suite.
#
#=back
#
#=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Verification
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   This is a verification callback which will be called by
#   rlImport after sourcing the library to make sure everything is
#   all right. It makes sense to perform a basic sanity test and
#   check that all required packages are installed. The function
#   should return 0 only when the library is ready to serve.

fwdLibraryLoaded() {
    if rpm=$(rpm -q ${__fwdPACKAGES[0]}); then
        sepol=$(rpm -q selinux-policy)
        rlLogInfo "Library firewalld/main running with $rpm on $sepol in $(getenforce) mode"

        for pkg in ${__fwdPACKAGES[@]} kernel-$(uname -r); do
            rlAssertRpm $pkg
        done

        return 0
    else
        rlLogError "firewalld not installed"
        return 1
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Authors
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

: <<'=cut'
=pod

=head1 AUTHORS

=over

=item *

Tomas Dolezal <todoleza@redhat.com>

=back

=cut
