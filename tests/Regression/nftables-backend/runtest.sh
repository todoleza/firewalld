#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/firewalld/Regression/nftables-backend
#   Description: Test for BZ#1509026 ([RFE] firewalld Implement nftables backend)
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
LOGFILE="/var/log/firewalld"

IPSET4='ipsetv4'
IPSET6='ipsetv6'
VER_0_7_UP=false

# limit output lines by arbitrary number after firewalld reloads in certain log check calls
LINES_OF_CONTEXT=35

save_log_cursor() {
    rlLogInfo "log recency mark"
    _LOG_LINE="$(wc -l "$LOGFILE" | cut -d' ' -f 1)"
    [[ ${PIPESTATUS[0]} -eq 0 ]] || rlFail "could not read $LOGFILE"
}
get_recent_log() {
    rlRun "tail -n +$_LOG_LINE $LOGFILE > firewalld.log.recent" 0 "get recent log messages"
}
nft_grepper() {
    local grepstr="$1"
    local comment="$2"
    rlRun "nft -nn list ruleset | egrep '$grepstr'" 0 "$comment"
}
check_log_and_mark() {
    get_recent_log
    rlAssertNotGrep "ERROR" firewalld.log.recent
    cat firewalld.log.recent
    save_log_cursor
}
rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm $PACKAGE
        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        rlRun "pushd $TmpDir"
        rlCmpVersion 0.7 $(rpm -q --qf %{VERSION} firewalld)
        if [[ $? -eq 0 || $? -eq 2 ]]; then
            # new version
            VER_0_7_UP=true
        fi
        rlRun "rlImport firewalld/main" || rlDie
        fwdSetup
        rlRun "fwdGetBackend | grep nftables" 0 "verify nftables backend"
    rlPhaseEnd

    rlPhaseStartTest
        # service
        save_log_cursor
        rlRun "firewall-cmd --add-service smtp"
        #rlRun "nft -nn list ruleset | grep 'tcp dport 25 ct state new,untracked accept'"
        nft_grepper "tcp dport 25 ct state new,untracked accept"
        check_log_and_mark
        #  port
        rlRun "firewall-cmd --add-port 22335/tcp"
        rlRun "firewall-cmd --add-port 22336/udp"
        check_log_and_mark
        nft_grepper "tcp dport 22335 ct state new,untracked accept" "verify port rule presence"
        nft_grepper "udp dport 22336 ct state new,untracked accept" "verify port rule presence"
        #  protocol (SEE zone/protocol)
        #  module
        rlRun "firewall-cmd --add-service ftp" 0 "add ftp service with ftp module"
        if $VER_0_7_UP; then
            nft_grepper 'tcp dport 21 ct helper set "helper-ftp-tcp"' "helper presence"
        else
            nft_grepper 'tcp dport 21 ct helper "ftp"' "helper presence"
        fi
        rlAssertExists "/sys/module/nf_nat_ftp/"
        check_log_and_mark
        #  source/destination ports (UNTESTED)
        fwdRestart; save_log_cursor

        # zone
        #  source/dest
        rlRun "firewall-cmd --zone internal --add-source 192.0.2.40"
        rlRun "firewall-cmd --zone internal --add-source ::ffff:192.0.2.60"
        nft_grepper "ip saddr 192.0.2.40 goto .*internal"
        nft_grepper "ip6 saddr ::ffff:192.0.2.60 goto .*internal"
        check_log_and_mark
        #  protocol
        rlRun "firewall-cmd --add-protocol igmp" 0 "add protocol"
        nft_grepper "meta l4proto igmp ct state new,untracked accept" "verify protocol rule presence"
        check_log_and_mark
        #  icmp block
        rlRun "firewall-cmd --add-icmp-block time-exceeded"
        nft_grepper "icmp type time-exceeded reject with icmp"
        nft_grepper "icmpv6 type time-exceeded reject with icmpv6"
        check_log_and_mark
        #  forward
        rlRun "firewall-cmd --add-forward-port=port=22990-22999:proto=tcp:toaddr=127.0.0.2"
        if $VER_0_7_UP; then
            nft_grepper 'tcp dport 22990-22999 dnat to 127.0.0.2' "forward rule presence"
        else
            nft_grepper "tcp dport 22990-22999 mark set"
            nft_grepper "meta l4proto tcp mark 0x0[0-9]+ dnat to 127.0.0.2"
        fi
        check_log_and_mark
        #  masquerade
        rlRun "firewall-cmd --add-masquerade"
        nft_grepper 'oifname != "lo" masquerade'
        check_log_and_mark
        #  rich rule (not needed to cover)
        #  interface
        rlRun "firewall-cmd --add-interface ifcustom"
        nft_grepper '[oi]ifname "ifcustom" goto [a-zA-Z_]+_public'
        check_log_and_mark
        # ipset
        rlLogInfo "ipsets/zones"
        rlRun "firewall-cmd --new-ipset '$IPSET4' --permanent --type hash:ip"
        rlRun "firewall-cmd --new-ipset '$IPSET6' --permanent --type hash:ip --family inet6"
        fwdRestart
        save_log_cursor
        rlRun "firewall-cmd --ipset $IPSET4 --add-entry '192.0.2.12'"
        rlRun "firewall-cmd --ipset $IPSET6 --add-entry '::2'"
        # partial set match (also in ip/ip6 tables
        rlRun "nft list set inet firewalld $IPSET4 | grep '192.0.2.12'"
        rlRun "nft list set inet firewalld $IPSET6 | grep '::2'"
        rlRun "nft list set ip firewalld $IPSET4 | grep '192.0.2.12'"
        rlRun "nft list set ip6 firewalld $IPSET6 | grep '::2'"
        check_log_and_mark
        rlRun "firewall-cmd --add-source ipset:$IPSET4"
        rlRun "firewall-cmd --add-source ipset:$IPSET6"
        nft_grepper "ip daddr @$IPSET4 goto [a-zA-Z_]+_public"
        nft_grepper "ip6 daddr @$IPSET6 goto [a-zA-Z_]+_public"
        check_log_and_mark
        # helpers
         # modules covered in services above
        # direct (iptables only)
        # panic
         # covered in /CoreOS/firewalld/Regression/firewalld-panic-on-doesn-t-work
        #bash
        rlRun "firewall-cmd --state" 0 "verify firewalld reported state"

        rlLogInfo "use permanent config for sets in nft" # bz1738545
        check_log_and_mark
        rlRun "firewall-cmd --runtime-to-permanent"
        rlRun "firewall-cmd --reload"
        rlRun "firewall-cmd --state"
        # limit output lines by arbitrary number after firewalld reloads
        check_log_and_mark | grep -i ERROR -A $LINES_OF_CONTEXT
        rlRun "firewall-cmd --permanent --add-source ipset:$IPSET4"
        rlRun "firewall-cmd --permanent --add-source ipset:$IPSET6"
        rlRun "firewall-cmd --reload"
        rlRun "firewall-cmd --state"
        # limit output lines by arbitrary number after firewalld reloads
        check_log_and_mark | grep -i ERROR -A $LINES_OF_CONTEXT
    rlPhaseEnd

    rlPhaseStartCleanup
        fwdCleanup
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
