#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/firewalld/Regression/broute-table-support
#   Description: Test for BZ#1752727 (RHEL 7.7 rebase of firewalld removed support for)
#   Author: Tomas Dolezal <todoleza@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc.
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
TESTRULE="-i someif -j redirect --redirect-target DROP"
TESTRULE_MATCH="-i someif -j redirect  ?--redirect-target DROP"

rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm $PACKAGE
        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        rlRun "pushd $TmpDir"
        rlRun "rlImport firewalld/main" || rlDie
        fwdSetup
        rlIsRHEL 7 || { fwdSetBackend iptables; fwdRestart ; }
    rlPhaseEnd

check_broute_rules() {
    rlLogInfo "checking broute rules in ebtables"
    rlRun -s "ebtables-save"
    mv $rlRun_LOG ebtables-save.output
    rlRun -s "ebtables -t broute -L"
    mv $rlRun_LOG ebtables-broute.output

    rlAssertGrep "-j BROUTING_direct" ebtables-broute.output
    rlAssertGrep "$TESTRULE_MATCH" ebtables-broute.output -E

    rlAssertGrep "-A BROUTING -j BROUTING_direct" ebtables-save.output
    rlAssertGrep "-A BROUTING_direct $TESTRULE_MATCH" ebtables-save.output -E
}
    rlPhaseStartTest
        rlRun "firewall-cmd --direct --add-rule eb broute BROUTING 0 $TESTRULE"
        check_broute_rules

        rlRun "firewall-cmd --runtime-to-permanent"
        rlRun "firewall-cmd --reload"
        check_broute_rules
    rlPhaseEnd

    rlPhaseStartCleanup
        fwdCleanup
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
