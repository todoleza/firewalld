#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/firewalld/Library/main
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

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGE="firewalld"
PHASE=${PHASE:-Test}

rlJournalStart
    rlPhaseStartSetup
        rlRun "rlImport firewalld/main"
        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        rlRun "pushd $TmpDir"
    rlPhaseEnd

#    # Create file
#    if [[ "$PHASE" =~ "Create" ]]; then
#        rlPhaseStartTest "Create"
#            fileCreate
#        rlPhaseEnd
#    fi

    # Self test
    if [[ "$PHASE" =~ "Test" ]]; then
        rlPhaseStartTest "firewalld Setup and Cleanup"
            rlRun "systemctl stop firewalld"
            rlRun "firewall-cmd --state" 252 "firewalld is not running"
            rlAssertGrep "DefaultZone=public" /etc/firewalld/firewalld.conf

            rlRun "fwdSetup -n"
            rlRun "firewall-cmd --state" 252 "firewalld is not runnig"
            rlRun "fwdCleanup"
            rlRun "fwdSetup"
            rlRun "firewall-cmd --state" 0 "firewalld is runnig"
            rlRun "ps -ef | grep firewalld | grep debug=10" 0 "debug level is set to 10"

            rlRun "firewall-cmd --set-default-zone work"
            rlRun "firewall-cmd --add-service tftp --permanent"
            rlRun "firewall-cmd --reload"
            rlAssertGrep "DefaultZone=work" /etc/firewalld/firewalld.conf
            rlAssertGrep "tftp" /etc/firewalld/zones/work.xml

            rlRun "fwdCleanup"
            rlRun "firewall-cmd --state" 252 "firewalld is not running"
            rlAssertGrep "DefaultZone=public" /etc/firewalld/firewalld.conf
            rlAssertNotExists /etc/firewalld/zones/work.xml
            rlFileBackup --clean /etc/firewalld /etc/sysconfig/firewalld
            rlRun "echo FOO=BAR >> /etc/sysconfig/firewalld"
            rlRun "fwdSetup" 0 "fwdSetup - run through check of modified firewalld sysconfig file"
            rlRun "fwdCleanup"
            # following cannot be run while having this test phase to pass (it must fail)
            #rlRun "fwd_VERIFY_RPM=1 fwdSetup"
            #rlRun "fwdCleanup"
            rlFileRestore
        rlPhaseEnd

        rlPhaseStartTest "ResetConfig"
            rlRun "fwdSetup"
            rlRun "firewall-cmd --set-default-zone work"
            rlRun "firewall-cmd --add-service tftp --permanent"
            rlRun "firewall-cmd --reload"
            rlAssertGrep "DefaultZone=work" /etc/firewalld/firewalld.conf
            rlAssertGrep "tftp" /etc/firewalld/zones/work.xml

            rlRun "fwdResetConfig"
            #rlRun "fwdRestart" # included in ResetConfig unless --no-restart is given
            rlRun "ps -ef | grep firewalld | grep debug=10" 0 "debug level is set to 10"
            rlAssertGrep "DefaultZone=public" /etc/firewalld/firewalld.conf
            rlAssertNotExists /etc/firewalld/zones/work.xml

            rlRun "firewall-cmd --add-service smtp"
            rlRun "fwdResetConfig -n"
            rlRun "fwdResetConfig --no-restart"
            rlRun "firewall-cmd --query-service smtp"

            rlRun "fwdResetConfig --badargument" 1
            rlRun "fwdResetConfig --mor -e" 1
            rlRun "fwdResetConfig -n"
            rlRun "fwdCleanup"
        rlPhaseEnd

        rlPhaseStartTest "SetBackend / GetBackend"
            rlRun "fwdSetup"
            rlRun "fwdGetBackend > >(tee backend.out)"
            if ! rlIsRHEL 7; then
                rlAssertGrep "^nftables$" backend.out
            else
                rlAssertGrep "^iptables$" backend.out
            fi
            rlRun "fwdSetBackend iptables"
            rlRun "fwdGetBackend > >(tee backend.out)"
            rlAssertGrep "^iptables$" backend.out
            rlAssertGrep "FirewallBackend=iptables" /etc/firewalld/firewalld.conf
            rlRun "fwdSetBackend nftables"
            rlAssertGrep "FirewallBackend=nftables" /etc/firewalld/firewalld.conf
            rlRun "fwdGetBackend > >(tee backend.out)"
            rlAssertGrep "^nftables$" backend.out
            rlRun "fwdSetBackend notiptables" 1 "invalid backend"
            rlRun "fwdSetBackend iptables" 0 "change to iptables again"
            rlRun "fwdSetBackend" 0 "reset to default backend (force to nftables)"
            rlAssertGrep "FirewallBackend=nftables" /etc/firewalld/firewalld.conf
            rlRun "sed -e '/FirewallBackend/d' -i /etc/firewalld/firewalld.conf" 0 "remove FirewallBackend option"
            rlRun "fwdSetBackend iptables" 1 "unsupported change"
            rlRun "fwdGetBackend > >(tee backend.out)" 1
            rlAssertNotDiffer backend.out /dev/null
            rlRun "fwdCleanup"
        rlPhaseEnd
    fi

    rlPhaseStartCleanup
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
