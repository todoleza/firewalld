firewalld BeakerLib TODOs
=========================

# Setup
 * init library
  * Assert system state
   - important system packages
   - verify configuration is clean, warn/fail if not (prametrizable via TESTPARAM)
 * configuration/logs backup and pre-cleaning
 * set important parameters
  * backend
   - emit log messages
   - restart firewalld ?
  * debug level (for systemd in sysconfig)

# Procedures
 * match rule in ruleset
  * generic matching applicable for nft/ipt
   - make use of `jq`, for iptables verify both families or select via parameter [-4|-6]
  * specific rule type match usable for nft/ipt
 * add file to logs bundle
## NAMESPACES ( for functional tests )
 * consider putting them into a separate library
 * get inspiration from tests/kernel/networking
 * ns management
  - create/delete multiple namespaces
 * start/stop/restart firewalld in [arg] namespace
  - e.g. `startfwd --netns mynetns`
 * wrap arg as command for namespace

# Finalization
 * get rid of own running namespaces
 * bundle and submit logs
 * restore backed up files and service states

 vim: filetype=markdown
